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
    
    /// Locks a secret file (e.g. .env) by encrypting it to .env.vault and replacing .env with a dummy file
    public func lock(fileURL: URL) async throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultError.targetFileNotFound(fileURL.path)
        }
        
        let vault = vaultURL(for: fileURL)
        
        let plaintextData: Data
        do {
            plaintextData = try Data(contentsOf: fileURL)
        } catch {
            throw VaultError.targetFileNotFound(fileURL.path)
        }
        
        guard let plaintextString = String(data: plaintextData, encoding: .utf8) else {
            throw VaultError.invalidFileEncoding
        }
        
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
        
        // Generate dummy masked file for .env, JSON, or arbitrary secret files
        let dummyContent = EnvParser.shared.generateDummyTemplate(from: plaintextString, fileName: fileURL.lastPathComponent)
        do {
            try dummyContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw VaultError.writeFailed("Could not write masked dummy file: \(error.localizedDescription)")
        }
        
        // Ensure vault is ignored in git
        let parentDir = fileURL.deletingLastPathComponent()
        GitIgnoreManager.shared.ensureIgnored(in: parentDir, vaultFileName: vault.lastPathComponent)
        
        // Return list of discovered keys or the filename if arbitrary content
        let parsed = EnvParser.shared.parse(plaintextString)
        if parsed.isEmpty {
            return [fileURL.lastPathComponent]
        }
        return Array(parsed.keys).sorted()
    }
    
    /// Decrypts vault file and returns dictionary of environment variables in memory
    public func readDecryptedSecrets(vaultURL: URL) async throws -> [String: String] {
        let plaintextData = try await readDecryptedData(vaultURL: vaultURL, promptReason: "sec requires Touch ID to decrypt secrets for command execution")
        guard let plaintextString = String(data: plaintextData, encoding: .utf8) else {
            throw VaultError.invalidFileEncoding
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
        return try CryptoEngine.shared.decrypt(vaultData: vaultData, keyData: masterKey)
    }
    
    /// Completely unlocks the file back to plaintext on disk (removes .vault)
    public func unlockToDisk(vaultURL: URL) async throws {
        let plainFile = plainFileURL(for: vaultURL)
        let plaintextData = try await readDecryptedData(vaultURL: vaultURL, promptReason: "sec requires Touch ID to permanently unlock '\(plainFile.lastPathComponent)' to disk")
        
        do {
            try plaintextData.write(to: plainFile, options: .atomic)
            try? FileManager.default.removeItem(at: vaultURL)
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
    
    /// Locates .env.vault in current directory or searches upwards in parent directories
    public func findNearestVault(startingAt startDir: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath), targetName: String = ".env.vault") -> URL? {
        var current = startDir.standardizedFileURL
        
        while true {
            let candidate = current.appendingPathComponent(targetName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
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
