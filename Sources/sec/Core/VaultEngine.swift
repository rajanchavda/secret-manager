import Foundation

public enum VaultError: LocalizedError {
    case targetFileNotFound(String)
    case vaultFileNotFound(String)
    case alreadyLocked(String)
    case invalidFileEncoding
    case writeFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .targetFileNotFound(let path):
            return "Secret file not found: \(path)"
        case .vaultFileNotFound(let path):
            return "Encrypted vault not found: \(path)"
        case .alreadyLocked(let path):
            return "File is already locked (\(path).vault already exists). Use 'sec edit' to modify or 'sec unlock' to decrypt."
        case .invalidFileEncoding:
            return "Unable to decode file content as UTF-8 text."
        case .writeFailed(let msg):
            return "Failed to write file: \(msg)"
        }
    }
}

public final class VaultEngine {
    public static let shared = VaultEngine()
    
    private init() {}
    
    /// Derives the corresponding .vault URL for a given target file URL
    public func vaultURL(for fileURL: URL) -> URL {
        return fileURL.appendingPathExtension("vault")
    }
    
    /// Derives the plain file URL from a .vault URL
    public func plainFileURL(for vaultURL: URL) -> URL {
        return vaultURL.deletingPathExtension()
    }
    
    /// Checks if a file's content matches sec's dummy masked placeholder
    public func isDummyContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("PROTECTED BY sec") ||
               trimmed.contains("locked_by_sec") ||
               trimmed.contains("_sec_locked")
    }
    
    /// Checks if a file is already locked or is itself a vault file
    public func isAlreadyLocked(fileURL: URL) -> Bool {
        if fileURL.pathExtension == "vault" {
            return true
        }
        let vault = vaultURL(for: fileURL)
        if FileManager.default.fileExists(atPath: vault.path) {
            return true
        }
        if let content = try? String(contentsOf: fileURL, encoding: .utf8), isDummyContent(content) {
            return true
        }
        return false
    }

    /// Locks a secret file (e.g. .env) by encrypting it to .env.vault and replacing .env with a dummy file.
    /// If force is false and the file is already locked, it aborts to prevent overwriting secrets with dummy values.
    public func lock(fileURL: URL, force: Bool = false) async throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultError.targetFileNotFound(fileURL.path)
        }
        
        // 1. Prevent locking a .vault file onto itself
        if fileURL.pathExtension == "vault" {
            throw VaultError.alreadyLocked(fileURL.lastPathComponent)
        }
        
        let vault = vaultURL(for: fileURL)
        
        // 2. Prevent re-locking if vault already exists or content is a dummy placeholder
        if !force {
            if isAlreadyLocked(fileURL: fileURL) {
                throw VaultError.alreadyLocked(fileURL.lastPathComponent)
            }
        }
        
        let plaintextData: Data
        do {
            plaintextData = try Data(contentsOf: fileURL)
        } catch {
            throw VaultError.targetFileNotFound(fileURL.path)
        }
        
        let originalAttrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let originalPerms = originalAttrs?[.posixPermissions] as? NSNumber
        
        let plaintextString = String(data: plaintextData, encoding: .utf8)
        
        // Touch ID / Passcode authentication (if session not already active)
        if !SessionManager.shared.isSessionActive() {
            try await BiometricAuth.shared.authenticate(reason: "sec requires Touch ID to lock and encrypt '\(fileURL.lastPathComponent)'")
            SessionManager.shared.startSession()
        }
        
        let masterKey = try KeychainManager.shared.getOrCreateMasterKey()
        let encryptedVaultData = try CryptoEngine.shared.encrypt(plaintext: plaintextData, keyData: masterKey)
        
        // Write vault file
        do {
            try encryptedVaultData.write(to: vault, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vault.path)
        } catch {
            throw VaultError.writeFailed("Could not write encrypted vault: \(error.localizedDescription)")
        }
        
        // Generate dummy masked file for .env, JSON, YAML, or arbitrary/binary secret files
        let dummyContent: String
        if let text = plaintextString {
            dummyContent = EnvParser.shared.generateDummyTemplate(from: text, fileName: fileURL.lastPathComponent)
        } else {
            dummyContent = """
            # ====================================================================
            # 🔒 PROTECTED BY sec (Touch ID Secret Vault)
            # Binary secret file (\(fileURL.lastPathComponent)) is shielded from AI agents.
            # Real secrets are encrypted in \(vault.lastPathComponent)
            # Unlock to disk: sec unlock \(fileURL.lastPathComponent)
            # ====================================================================
            """
        }
        
        do {
            try dummyContent.write(to: fileURL, atomically: true, encoding: .utf8)
            if let perms = originalPerms {
                try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: fileURL.path)
            }
        } catch {
            throw VaultError.writeFailed("Could not write masked dummy file: \(error.localizedDescription)")
        }
        
        // Ensure vault is ignored in git
        let parentDir = fileURL.deletingLastPathComponent()
        GitIgnoreManager.shared.ensureIgnored(in: parentDir, vaultFileName: vault.lastPathComponent)
        
        // Register vault in global registry
        RegistryManager.shared.register(vaultURL: vault, plainURL: fileURL)
        
        // Return list of discovered keys or the filename if arbitrary/binary content
        if let text = plaintextString {
            let parsed = EnvParser.shared.parse(text)
            if parsed.isEmpty {
                return [fileURL.lastPathComponent]
            }
            return Array(parsed.keys).sorted()
        } else {
            return [fileURL.lastPathComponent]
        }
    }
    
    /// Decrypts vault file and returns dictionary of environment variables in memory
    public func readDecryptedSecrets(vaultURL: URL) async throws -> [String: String] {
        let plaintextData = try await readDecryptedData(vaultURL: vaultURL, promptReason: "sec requires Touch ID to decrypt secrets for command execution")
        guard let plaintextString = String(data: plaintextData, encoding: .utf8) else {
            // Binary files have no text environment variables
            return [:]
        }
        return EnvParser.shared.parse(plaintextString)
    }
    
    /// Decrypts vault file and returns raw plaintext data in memory
    public func readDecryptedData(vaultURL: URL, promptReason: String) async throws -> Data {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            throw VaultError.vaultFileNotFound(vaultURL.path)
        }
        
        if !SessionManager.shared.isSessionActive() {
            try await BiometricAuth.shared.authenticate(reason: promptReason)
            SessionManager.shared.startSession()
        }
        
        let masterKey = try KeychainManager.shared.getMasterKey()
        let vaultData = try Data(contentsOf: vaultURL)
        let decrypted = try CryptoEngine.shared.decrypt(vaultData: vaultData, keyData: masterKey)
        RegistryManager.shared.touch(vaultURL: vaultURL)
        return decrypted
    }
    
    /// Completely unlocks the file back to plaintext on disk (removes .vault)
    public func unlockToDisk(vaultURL: URL) async throws {
        let plainFile = plainFileURL(for: vaultURL)
        let plaintextData = try await readDecryptedData(vaultURL: vaultURL, promptReason: "sec requires Touch ID to permanently unlock '\(plainFile.lastPathComponent)' to disk")
        
        do {
            try plaintextData.write(to: plainFile, options: .atomic)
            let name = plainFile.lastPathComponent.lowercased()
            if name.contains("rsa") || name.hasSuffix(".pem") || name.hasSuffix(".key") || name.contains("id_ed25519") || name.contains("id_ecdsa") {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plainFile.path)
            }
            try? FileManager.default.removeItem(at: vaultURL)
            RegistryManager.shared.unregister(vaultURL: vaultURL)
        } catch {
            throw VaultError.writeFailed("Failed to restore plaintext file: \(error.localizedDescription)")
        }
    }
    
    /// Updates the vault with new plaintext data and refreshes dummy file
    public func updateVault(vaultURL: URL, plaintextData: Data) async throws {
        let masterKey = try KeychainManager.shared.getOrCreateMasterKey()
        let encryptedVaultData = try CryptoEngine.shared.encrypt(plaintext: plaintextData, keyData: masterKey)
        
        try encryptedVaultData.write(to: vaultURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultURL.path)
        
        // Also refresh dummy file if valid utf-8 string
        if let plaintextString = String(data: plaintextData, encoding: .utf8) {
            let plainFile = plainFileURL(for: vaultURL)
            let dummyContent = EnvParser.shared.generateDummyTemplate(from: plaintextString, fileName: plainFile.lastPathComponent)
            try? dummyContent.write(to: plainFile, atomically: true, encoding: .utf8)
        }
    }
    
    /// Locates .env.vault or other .vault files in current directory or searches upwards in parent directories
    public func findNearestVault(startingAt startDir: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath), targetName: String = ".env.vault") -> URL? {
        var current = startDir.standardizedFileURL
        
        while true {
            let candidate = current.appendingPathComponent(targetName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            
            // If targetName is default (.env.vault), also check for standard variants in current directory
            if targetName == ".env.vault" {
                let variants = [".env.local.vault", ".env.development.vault", ".env.dev.vault", ".env.prod.vault", ".env.production.vault"]
                for v in variants {
                    let varCandidate = current.appendingPathComponent(v)
                    if FileManager.default.fileExists(atPath: varCandidate.path) {
                        return varCandidate
                    }
                }
                
                // If there is only one .vault file in the directory, use it automatically
                if let files = try? FileManager.default.contentsOfDirectory(atPath: current.path) {
                    let vaults = files.filter { $0.hasSuffix(".vault") }
                    if vaults.count == 1, let onlyVault = vaults.first {
                        return current.appendingPathComponent(onlyVault)
                    }
                }
            }
            
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                // Reached filesystem root
                break
            }
            current = parent
        }
        
        return nil
    }
}
