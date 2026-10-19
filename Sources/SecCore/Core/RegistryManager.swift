import Foundation

public struct VaultRecord: Codable, Equatable {
    public let vaultPath: String
    public let plainPath: String
    public var lastLockedAt: Date?
    public var lastAccessedAt: Date?
    
    public init(vaultPath: String, plainPath: String, lastLockedAt: Date? = Date(), lastAccessedAt: Date? = nil) {
        self.vaultPath = vaultPath
        self.plainPath = plainPath
        self.lastLockedAt = lastLockedAt
        self.lastAccessedAt = lastAccessedAt
    }
}

public struct RegistryData: Codable {
    public var version: Int
    public var records: [VaultRecord]
    
    public init(version: Int = 1, records: [VaultRecord] = []) {
        self.version = version
        self.records = records
    }
}

public struct VaultStatusInfo: Codable {
    public let vaultPath: String
    public let plainPath: String
    public let vaultName: String
    public let plainName: String
    public let directory: String
    public let statusDescription: String
    public let statusCode: String // "protected", "unprotected", "missing_vault", "missing_decoy"
    public let vaultSizeBytes: Int64?
    public let lastModified: String?
}

public final class RegistryManager {
    public static let shared = RegistryManager()
    
    private var secDirectory: URL {
        return SecPaths.dataDirectory
    }
    
    private var registryFileURL: URL {
        return secDirectory.appendingPathComponent("registry.json")
    }
    
    private init() {
        ensureSecDirectory()
    }
    
    private func ensureSecDirectory() {
        let path = secDirectory.path
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(at: secDirectory, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }
    }
    
    public func loadRegistry() -> RegistryData {
        ensureSecDirectory()
        guard let data = try? Data(contentsOf: registryFileURL) else {
            return RegistryData(records: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var registry = (try? decoder.decode(RegistryData.self, from: data)) ?? RegistryData(records: [])
        // Exclude any internal backup, snapshot, trash, or metadata files
        registry.records = registry.records.filter { record in
            !record.vaultPath.contains("/.sec/") && !record.vaultPath.hasSuffix(".vault.bak")
        }
        return registry
    }
    
    public func saveRegistry(_ registry: RegistryData) {
        ensureSecDirectory()
        var sanitized = registry
        sanitized.records = sanitized.records.filter { record in
            !record.vaultPath.contains("/.sec/") && !record.vaultPath.hasSuffix(".vault.bak")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sanitized) else { return }
        try? data.write(to: registryFileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryFileURL.path)
    }
    
    public func register(vaultURL: URL, plainURL: URL) {
        let standardizedVault = vaultURL.standardizedFileURL.resolvingSymlinksInPath().path
        let standardizedPlain = plainURL.standardizedFileURL.resolvingSymlinksInPath().path
        
        // Guard: Never register internal backup, trash, or metadata files
        if standardizedVault.contains("/.sec/") || standardizedVault.hasSuffix(".vault.bak") {
            return
        }
        
        var data = loadRegistry()
        if let idx = data.records.firstIndex(where: { $0.vaultPath == standardizedVault }) {
            data.records[idx].lastLockedAt = Date()
        } else {
            let record = VaultRecord(vaultPath: standardizedVault, plainPath: standardizedPlain, lastLockedAt: Date())
            data.records.append(record)
        }
        data.records.sort { $0.vaultPath < $1.vaultPath }
        saveRegistry(data)
    }
    
    public func touch(vaultURL: URL) {
        let standardizedVault = vaultURL.standardizedFileURL.resolvingSymlinksInPath().path
        var data = loadRegistry()
        if let idx = data.records.firstIndex(where: { $0.vaultPath == standardizedVault }) {
            data.records[idx].lastAccessedAt = Date()
            saveRegistry(data)
        } else {
            let plainURL = VaultEngine.shared.plainFileURL(for: vaultURL)
            register(vaultURL: vaultURL, plainURL: plainURL)
        }
    }
    
    public func unregister(vaultURL: URL) {
        let standardizedVault = vaultURL.standardizedFileURL.resolvingSymlinksInPath().path
        var data = loadRegistry()
        data.records.removeAll { $0.vaultPath == standardizedVault }
        saveRegistry(data)
    }
    
    public func cleanOrphanVault(at vaultURL: URL) {
        // Vaults must NEVER be automatically unlinked without explicit user intent.
        // Unregister from registry, but leave the encrypted vault intact on disk.
        unregister(vaultURL: vaultURL)
    }
    
    @discardableResult
    public func autoPrune(cleanOrphans: Bool = false) -> (removedCount: Int, remaining: [VaultRecord]) {
        var data = loadRegistry()
        let initialCount = data.records.count
        let fm = FileManager.default
        
        var toRemove: [String] = []
        for record in data.records {
            let vaultExists = fm.fileExists(atPath: record.vaultPath)
            if !vaultExists || record.vaultPath.contains("/.sec/") || record.vaultPath.hasSuffix(".vault.bak") {
                // The encrypted vault file itself was moved, deleted, or is an internal backup/trash file
                toRemove.append(record.vaultPath)
            }
        }
        
        data.records.removeAll { toRemove.contains($0.vaultPath) }
        let removedCount = initialCount - data.records.count
        if removedCount > 0 {
            saveRegistry(data)
        }
        return (removedCount, data.records)
    }
    
    public func prune() -> (removedCount: Int, remaining: [VaultRecord]) {
        return autoPrune(cleanOrphans: false)
    }
    
    public func inspectVault(record: VaultRecord) -> VaultStatusInfo {
        let vaultURL = URL(fileURLWithPath: record.vaultPath)
        let plainURL = URL(fileURLWithPath: record.plainPath)
        
        let vaultExists = FileManager.default.fileExists(atPath: record.vaultPath)
        let plainExists = FileManager.default.fileExists(atPath: record.plainPath)
        
        let directory = vaultURL.deletingLastPathComponent().path
        let vaultAttrs = try? FileManager.default.attributesOfItem(atPath: record.vaultPath)
        let fileSize = (vaultAttrs?[.size] as? NSNumber)?.int64Value
        
        let modDate: Date? = (vaultAttrs?[.modificationDate] as? Date) ?? record.lastLockedAt
        let dateStr: String?
        if let d = modDate {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            dateStr = df.string(from: d)
        } else {
            dateStr = nil
        }
        
        let statusCode: String
        let statusDesc: String
        
        if !vaultExists {
            statusCode = "missing_vault"
            statusDesc = "❌ Missing Vault (vault file was moved or deleted)"
        } else if !plainExists {
            statusCode = "missing_decoy"
            statusDesc = "⚠️ Decoy Missing (target file does not exist on disk, encrypted vault is preserved)"
        } else {
            if let content = try? String(contentsOfFile: record.plainPath, encoding: .utf8),
               VaultEngine.shared.isDummyContent(content) {
                statusCode = "protected"
                statusDesc = "🔒 Protected (Decoy active on disk)"
            } else {
                statusCode = "unprotected"
                statusDesc = "⚠️ Unprotected (Target file has unmasked plaintext content)"
            }
        }
        
        return VaultStatusInfo(
            vaultPath: record.vaultPath,
            plainPath: record.plainPath,
            vaultName: vaultURL.lastPathComponent,
            plainName: plainURL.lastPathComponent,
            directory: directory,
            statusDescription: statusDesc,
            statusCode: statusCode,
            vaultSizeBytes: fileSize,
            lastModified: dateStr
        )
    }
    
    /// Recursively scans a directory for .vault and .*.vault files, ignoring cache/dependency folders
    public func scan(directory: URL) -> [VaultRecord] {
        let fileManager = FileManager.default
        let standardRoot = directory.standardizedFileURL.resolvingSymlinksInPath()
        
        guard let enumerator = fileManager.enumerator(
            at: standardRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: []
        ) else {
            return []
        }
        
        let skipDirs: Set<String> = [
            ".sec", "backups", "trash", "Library", ".Trash", ".cache", "node_modules", ".git", ".build",
            "DerivedData", "Pods", ".npm", ".yarn", ".cargo", ".rustup",
            ".gradle", "venv", ".venv", "env", ".tox", ".docker", "dist",
            ".next", ".nuxt", "vendor", "Caches", ".system_generated"
        ]
        
        var discovered: [VaultRecord] = []
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]) else {
                continue
            }
            
            if resourceValues.isSymbolicLink == true {
                if resourceValues.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            if resourceValues.isDirectory == true {
                let name = fileURL.lastPathComponent
                if skipDirs.contains(name) || name == ".sec" {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            let filename = fileURL.lastPathComponent
            if filename.hasSuffix(".vault") && !filename.hasSuffix(".vault.bak") {
                let resolvedURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
                if resolvedURL.path.contains("/.sec/") {
                    continue
                }
                let plainURL = VaultEngine.shared.plainFileURL(for: resolvedURL)
                let record = VaultRecord(
                    vaultPath: resolvedURL.path,
                    plainPath: plainURL.path,
                    lastLockedAt: resourceValues.contentModificationDate
                )
                discovered.append(record)
            }
        }
        
        // Merge into persistent registry
        var data = loadRegistry()
        for record in discovered {
            if let idx = data.records.firstIndex(where: { $0.vaultPath == record.vaultPath }) {
                if record.lastLockedAt != nil {
                    data.records[idx].lastLockedAt = record.lastLockedAt
                }
            } else {
                data.records.append(record)
            }
        }
        data.records.sort { $0.vaultPath < $1.vaultPath }
        saveRegistry(data)
        
        return discovered
    }
}
