import Foundation

public enum VaultFreshness: Equatable {
    case fresh
    case stale(plainURL: URL, plainModified: Date, vaultModified: Date)
    case orphan(vaultURL: URL)
    case missing
}

public enum VaultError: LocalizedError {
    case targetFileNotFound(String)
    case vaultFileNotFound(String)
    case alreadyLocked(String)
    case cannotLockDecoyFile(String)
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
        case .cannotLockDecoyFile(let path):
            return "Cannot lock '\(path)': File contains masked dummy placeholder content. Locking would destroy your real encrypted secrets. Use 'sec edit' or 'sec unlock'."
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
    
    /// Checks if a file's content matches sec's dummy masked placeholder.
    /// Matches the decoy header comment or a value that is exactly a placeholder; a real file
    /// that only mentions those words in passing is not treated as a decoy.
    public func isDummyContent(_ content: String) -> Bool {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") && trimmed.contains("PROTECTED BY sec") {
                return true
            }
        }
        return EnvParser.shared.containsPlaceholderValue(content)
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

    /// Safely creates a local and central multi-version backup of a vault before any destructive operation (synchronous dispatch)
    public func backupVault(at vaultURL: URL, trigger: SnapshotTrigger = .autoSnapshot, note: String? = nil) {
        Task {
            await backupVaultAsync(at: vaultURL, trigger: trigger, note: note)
        }
    }
    
    /// Safely creates a local and central multi-version backup of a vault (awaitable)
    @discardableResult
    public func backupVaultAsync(at vaultURL: URL, trigger: SnapshotTrigger = .autoSnapshot, note: String? = nil) async -> SnapshotRecord? {
        let fm = FileManager.default
        let resolvedVault = vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: resolvedVault.path) else { return nil }
        
        // 1. Local backup alongside the vault
        let localBackup = resolvedVault.appendingPathExtension("bak")
        try? fm.removeItem(at: localBackup)
        try? fm.copyItem(at: resolvedVault, to: localBackup)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localBackup.path)
        
        // 2. Central persistent deterministic multi-version snapshot in ~/.sec/backups/
        return try? await BackupEngine.shared.createSnapshot(for: resolvedVault, trigger: trigger, note: note)
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
        
        let plaintextString = String(data: plaintextData, encoding: .utf8)
        
        // Critical Safeguard: Never allow locking a file that already contains dummy decoy content,
        // even if force is true, as doing so would irrevocably replace real secrets with dummy placeholders.
        if let text = plaintextString, isDummyContent(text) {
            throw VaultError.cannotLockDecoyFile(fileURL.lastPathComponent)
        }
        
        let originalAttrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let originalPerms = originalAttrs?[.posixPermissions] as? NSNumber
        
        // Touch ID / Passcode authentication (if session not already active)
        if !SessionManager.shared.isSessionActive() {
            try await BiometricAuth.shared.authenticate(reason: "sec requires Touch ID to lock and encrypt '\(fileURL.lastPathComponent)'")
            SessionManager.shared.startSession()
        }
        
        // Finish snapshotting any existing vault before it is overwritten below
        await backupVaultAsync(at: vault)
        
        let masterKey = try KeychainManager.shared.getOrCreateMasterKey()
        let encryptedVaultData = try CryptoEngine.shared.encrypt(plaintext: plaintextData, keyData: masterKey)
        
        // Write vault file
        do {
            try encryptedVaultData.write(to: vault, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vault.path)
        } catch {
            throw VaultError.writeFailed("Could not write encrypted vault: \(error.localizedDescription)")
        }
        
        // The plaintext is about to be replaced by the decoy, so the vault must be durable first:
        // without this a crash or power loss could leave the decoy on disk and no readable vault.
        guard flushToDisk(vault) else {
            throw VaultError.writeFailed("Could not flush encrypted vault to disk; '\(fileURL.lastPathComponent)' was left untouched.")
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
        
        // Resolve target file URL to preserve symlinks rather than replacing them with regular files
        let targetFileURL = fileURL.resolvingSymlinksInPath()
        do {
            try dummyContent.write(to: targetFileURL, atomically: true, encoding: .utf8)
            if let perms = originalPerms {
                try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: targetFileURL.path)
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
    /// Pass the command being run so the Touch ID prompt shows exactly what is being authorized.
    public func readDecryptedSecrets(vaultURL: URL, command: [String]? = nil) async throws -> [String: String] {
        var promptReason = "sec requires Touch ID to decrypt secrets for command execution"
        if let command = command, !command.isEmpty {
            promptReason = "sec requires Touch ID to run '\(CallerInfo.displayCommand(command))' with secrets from '\(vaultURL.lastPathComponent)'"
        }
        let plaintextData = try await readDecryptedData(vaultURL: vaultURL, promptReason: promptReason)
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
    
    /// Completely unlocks the file back to plaintext on disk (moves .vault to Trash and .vault.bak for disaster recovery)
    public func unlockToDisk(vaultURL: URL) async throws {
        let plainFile = plainFileURL(for: vaultURL).resolvingSymlinksInPath()
        let plaintextData = try await readDecryptedData(vaultURL: vaultURL, promptReason: "sec requires Touch ID to permanently unlock '\(plainFile.lastPathComponent)' to disk")
        
        do {
            backupVault(at: vaultURL, trigger: .preUnlock, note: "Pre-unlock snapshot before restoring plaintext to disk")
            _ = try? await BackupEngine.shared.moveToTrash(vaultURL: vaultURL, reason: "Restored plaintext to disk")
            try writeOwnerOnly(plaintextData, to: plainFile)
            
            // Move vault to local .bak file instead of outright deleting it, ensuring user never loses secrets if plain file is damaged
            let localBak = vaultURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: localBak)
            try? FileManager.default.moveItem(at: vaultURL, to: localBak)
            RegistryManager.shared.unregister(vaultURL: vaultURL)
        } catch {
            throw VaultError.writeFailed("Failed to restore plaintext file: \(error.localizedDescription)")
        }
    }
    
    /// Forces a file and its directory entry onto stable storage (F_FULLFSYNC)
    func flushToDisk(_ url: URL) -> Bool {
        func fullSync(_ path: String) -> Bool {
            let fd = open(path, O_RDONLY)
            guard fd >= 0 else { return false }
            defer { close(fd) }
            // Some volumes (network, FAT) do not support F_FULLFSYNC; fall back to fsync there
            return fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0
        }
        guard fullSync(url.path) else { return false }
        _ = fullSync(url.deletingLastPathComponent().path)
        return true
    }
    
    /// Atomically replaces a file with content that is owner-only (0600) from the moment it exists,
    /// so restored plaintext is never briefly readable by other users.
    func writeOwnerOnly(_ data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).sec-\(UUID().uuidString)")
        let fd = open(tempURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            throw VaultError.writeFailed(String(cString: strerror(errno)))
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        guard rename(tempURL.path, url.path) == 0 else {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: tempURL)
            throw VaultError.writeFailed(reason)
        }
    }
    
    /// Updates the vault with new plaintext data and refreshes dummy file
    public func updateVault(vaultURL: URL, plaintextData: Data) async throws {
        // Zero-Data-Loss Guard: Prevent writing empty whitespace
        if let str = String(data: plaintextData, encoding: .utf8) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && !plaintextData.isEmpty {
                throw VaultError.writeFailed("Aborting update: payload contains only whitespace, which would wipe vault contents.")
            }
        }
        
        await backupVaultAsync(at: vaultURL, trigger: .tableSave, note: "Pre-save snapshot before modifying secrets")
        
        let masterKey = try KeychainManager.shared.getOrCreateMasterKey()
        let encryptedVaultData = try CryptoEngine.shared.encrypt(plaintext: plaintextData, keyData: masterKey)
        
        try encryptedVaultData.write(to: vaultURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultURL.path)
        
        // Also refresh dummy file if valid utf-8 string
        if let plaintextString = String(data: plaintextData, encoding: .utf8) {
            let plainFile = plainFileURL(for: vaultURL).resolvingSymlinksInPath()
            let dummyContent = EnvParser.shared.generateDummyTemplate(from: plaintextString, fileName: plainFile.lastPathComponent)
            try? dummyContent.write(to: plainFile, atomically: true, encoding: .utf8)
        }
    }
    
    /// Checks the freshness of a vault against its corresponding plain decoy file on disk
    public func checkVaultFreshness(vaultURL: URL) -> VaultFreshness {
        let fm = FileManager.default
        guard fm.fileExists(atPath: vaultURL.path) else {
            return .missing
        }
        
        let plainFile = plainFileURL(for: vaultURL)
        guard fm.fileExists(atPath: plainFile.path) else {
            return .orphan(vaultURL: vaultURL)
        }
        
        guard let content = try? String(contentsOf: plainFile, encoding: .utf8) else {
            return .fresh
        }
        
        if isDummyContent(content) {
            return .fresh
        }
        
        // Plain file has unmasked content: compare modification dates
        let plainAttrs = try? fm.attributesOfItem(atPath: plainFile.path)
        let vaultAttrs = try? fm.attributesOfItem(atPath: vaultURL.path)
        
        let plainDate = (plainAttrs?[.modificationDate] as? Date) ?? Date()
        let vaultDate = (vaultAttrs?[.modificationDate] as? Date) ?? Date.distantPast
        
        if plainDate > vaultDate {
            return .stale(plainURL: plainFile, plainModified: plainDate, vaultModified: vaultDate)
        }
        
        return .fresh
    }
    
    /// Locates .env.vault or other .vault files in current directory or searches upwards in parent directories
    public func findNearestVault(startingAt startDir: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath), targetName: String = ".env.vault") -> URL? {
        var current = startDir.standardizedFileURL
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        
        var insideGitRepo = false
        var probe = current
        while true {
            if FileManager.default.fileExists(atPath: probe.appendingPathComponent(".git").path) {
                insideGitRepo = true
                break
            }
            let parent = probe.deletingLastPathComponent()
            if parent.path == probe.path || probe.path == homeDir.path { break }
            probe = parent
        }
        
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
                
                // If there is only one .vault file in the directory, use it automatically.
                // Outside a git repository this only applies to the starting directory: a lone vault
                // found further up probably belongs to a different project.
                if (current.path == startDir.standardizedFileURL.path || insideGitRepo),
                   let files = try? FileManager.default.contentsOfDirectory(atPath: current.path) {
                    let vaults = files.filter { $0.hasSuffix(".vault") }
                    if vaults.count == 1, let onlyVault = vaults.first {
                        return current.appendingPathComponent(onlyVault)
                    }
                }
            }
            
            // Boundary safety: stop upward traversal at .git root or user home directory
            // The repository root is the last directory searched, including when the search starts there:
            // a project never inherits secrets from whatever happens to sit above its own repository.
            let gitDir = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                break
            }
            if current.path == homeDir.path {
                break
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
