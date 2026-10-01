import Foundation
import CryptoKit

public enum SnapshotTrigger: String, Codable, CaseIterable {
    case manual = "Manual Backup"
    case preEdit = "Before Edit"
    case preUnlock = "Before Unlock"
    case tableSave = "Saved from Editor"
    case initialLock = "Initial Vault"
    case movedToTrash = "Moved to Trash"
    case autoSnapshot = "Auto Snapshot"
    
    public var iconName: String {
        switch self {
        case .manual:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .preEdit:
            return "pencil.circle.fill"
        case .preUnlock:
            return "lock.open.fill"
        case .tableSave:
            return "square.and.arrow.down.fill"
        case .initialLock:
            return "lock.shield.fill"
        case .movedToTrash:
            return "trash.fill"
        case .autoSnapshot:
            return "clock.arrow.circlepath"
        }
    }
}

public struct SnapshotRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public var version: Int
    public let vaultPath: String
    public let plainPath: String
    public let targetFileName: String
    public let projectName: String
    public let projectPath: String
    public let projectHash: String
    public let timestamp: Date
    public let trigger: SnapshotTrigger
    public let note: String?
    public let fileSizeBytes: Int64
    public let keyCount: Int
    public let snapshotFileName: String
    
    public init(
        id: UUID = UUID(),
        version: Int = 1,
        vaultPath: String,
        plainPath: String,
        targetFileName: String,
        projectName: String,
        projectPath: String,
        projectHash: String,
        timestamp: Date = Date(),
        trigger: SnapshotTrigger = .autoSnapshot,
        note: String? = nil,
        fileSizeBytes: Int64 = 0,
        keyCount: Int = 0,
        snapshotFileName: String
    ) {
        self.id = id
        self.version = version
        self.vaultPath = vaultPath
        self.plainPath = plainPath
        self.targetFileName = targetFileName
        self.projectName = projectName
        self.projectPath = projectPath
        self.projectHash = projectHash
        self.timestamp = timestamp
        self.trigger = trigger
        self.note = note
        self.fileSizeBytes = fileSizeBytes
        self.keyCount = keyCount
        self.snapshotFileName = snapshotFileName
    }
    
    public var relativeTime: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

public struct TrashRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public let vaultPath: String
    public let plainPath: String
    public let projectName: String
    public let projectPath: String
    public let targetFileName: String
    public let removedAt: Date
    public let originalKeyCount: Int
    public let fileSizeBytes: Int64
    public let trashFileName: String
    public let reason: String
    
    public init(
        id: UUID = UUID(),
        vaultPath: String,
        plainPath: String,
        projectName: String,
        projectPath: String,
        targetFileName: String,
        removedAt: Date = Date(),
        originalKeyCount: Int = 0,
        fileSizeBytes: Int64 = 0,
        trashFileName: String,
        reason: String = "Vault unlocked or removed"
    ) {
        self.id = id
        self.vaultPath = vaultPath
        self.plainPath = plainPath
        self.projectName = projectName
        self.projectPath = projectPath
        self.targetFileName = targetFileName
        self.removedAt = removedAt
        self.originalKeyCount = originalKeyCount
        self.fileSizeBytes = fileSizeBytes
        self.trashFileName = trashFileName
        self.reason = reason
    }
    
    public var relativeTime: String {
        let seconds = Int(Date().timeIntervalSince(removedAt))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

public final class BackupEngine {
    public static let shared = BackupEngine()
    
    public static let maxAutomaticSnapshotsPerFile = 25
    
    private let fm = FileManager.default
    
    private var baseDir: URL {
        let home = fm.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".sec", isDirectory: true)
    }
    
    public var backupsDirectory: URL {
        return baseDir.appendingPathComponent("backups", isDirectory: true)
    }
    
    public var trashDirectory: URL {
        return baseDir.appendingPathComponent("trash", isDirectory: true)
    }
    
    private var trashIndexURL: URL {
        return trashDirectory.appendingPathComponent("trash_index.json")
    }
    
    private init() {
        ensureDirectories()
    }
    
    private func ensureDirectories() {
        try? fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.createDirectory(at: trashDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    
    // MARK: - Deterministic Project Hashing
    public static func deterministicProjectHash(for projectURL: URL) -> String {
        let standardized = projectURL.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(standardized.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    
    private func projectBackupDirectory(for projectURL: URL) -> URL {
        let hash = Self.deterministicProjectHash(for: projectURL)
        let dir = backupsDirectory.appendingPathComponent(hash, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }
    
    private func snapshotsIndexURL(for projectURL: URL) -> URL {
        return projectBackupDirectory(for: projectURL).appendingPathComponent("snapshots.json")
    }
    
    // MARK: - Index Management
    public func loadSnapshots(for projectURL: URL) -> [SnapshotRecord] {
        let indexFile = snapshotsIndexURL(for: projectURL)
        guard let data = try? Data(contentsOf: indexFile) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SnapshotRecord].self, from: data)) ?? []
    }
    
    private func saveSnapshots(_ list: [SnapshotRecord], for projectURL: URL) {
        let indexFile = snapshotsIndexURL(for: projectURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: indexFile, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexFile.path)
    }
    
    // MARK: - Snapshot Creation
    @discardableResult
    public func createSnapshot(
        for vaultURL: URL,
        trigger: SnapshotTrigger = .autoSnapshot,
        note: String? = nil,
        keyCountOverride: Int? = nil
    ) async throws -> SnapshotRecord {
        ensureDirectories()
        let resolvedVault = vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: resolvedVault.path) else {
            throw VaultError.vaultFileNotFound(resolvedVault.path)
        }
        
        let plainURL = VaultEngine.shared.plainFileURL(for: resolvedVault)
        let projectURL = plainURL.deletingLastPathComponent()
        let projectHash = Self.deterministicProjectHash(for: projectURL)
        let projectName = projectURL.lastPathComponent
        let targetFileName = plainURL.lastPathComponent
        
        let projDir = projectBackupDirectory(for: projectURL)
        var existingSnapshots = loadSnapshots(for: projectURL)
        
        // Calculate version for this specific file
        let fileSnapshots = existingSnapshots.filter { $0.targetFileName == targetFileName }
        let nextVersion = (fileSnapshots.map { $0.version }.max() ?? 0) + 1
        
        let snapshotId = UUID()
        let snapshotFileName = "\(snapshotId.uuidString).vault"
        let snapshotDestination = projDir.appendingPathComponent(snapshotFileName)
        
        // Copy vault file to snapshot destination with 0600 permissions
        try fm.copyItem(at: resolvedVault, to: snapshotDestination)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotDestination.path)
        
        // Also maintain a convenient local .bak alongside the vault file
        let localBak = resolvedVault.appendingPathExtension("bak")
        try? fm.removeItem(at: localBak)
        try? fm.copyItem(at: resolvedVault, to: localBak)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localBak.path)
        
        let attrs = try? fm.attributesOfItem(atPath: resolvedVault.path)
        let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        
        // Parse keys if available
        var keys = keyCountOverride ?? 0
        if keys == 0, SessionManager.shared.isSessionActive() {
            if let secrets = try? await VaultEngine.shared.readDecryptedSecrets(vaultURL: resolvedVault) {
                keys = secrets.count
            }
        }
        
        let record = SnapshotRecord(
            id: snapshotId,
            version: nextVersion,
            vaultPath: resolvedVault.path,
            plainPath: plainURL.path,
            targetFileName: targetFileName,
            projectName: projectName,
            projectPath: projectURL.path,
            projectHash: projectHash,
            timestamp: Date(),
            trigger: trigger,
            note: note,
            fileSizeBytes: fileSize,
            keyCount: keys,
            snapshotFileName: snapshotFileName
        )
        
        existingSnapshots.insert(record, at: 0)
        
        // Retention enforcement: prune oldest automatic snapshots exceeding limit
        let pruned = enforceRetentionLimit(snapshots: existingSnapshots, for: targetFileName, in: projDir)
        saveSnapshots(pruned, for: projectURL)
        
        return record
    }
    
    private func enforceRetentionLimit(
        snapshots: [SnapshotRecord],
        for targetFileName: String,
        in projectDir: URL
    ) -> [SnapshotRecord] {
        var result = snapshots
        let targetSnapshots = result.filter { $0.targetFileName == targetFileName }
        
        // Filter automatic snapshots eligible for pruning (keep manual backups)
        let prunable = targetSnapshots.filter { $0.trigger != .manual }
        if prunable.count > Self.maxAutomaticSnapshotsPerFile {
            let overflowCount = prunable.count - Self.maxAutomaticSnapshotsPerFile
            // Oldest prunable snapshots are at the end
            let toRemove = prunable.suffix(overflowCount)
            for item in toRemove {
                let fileURL = projectDir.appendingPathComponent(item.snapshotFileName)
                try? fm.removeItem(at: fileURL)
                result.removeAll { $0.id == item.id }
            }
        }
        return result
    }
    
    // MARK: - Snapshot Querying
    public func listAllSnapshots() -> [SnapshotRecord] {
        ensureDirectories()
        var all: [SnapshotRecord] = []
        guard let subdirs = try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        for dir in subdirs {
            let indexFile = dir.appendingPathComponent("snapshots.json")
            if let data = try? Data(contentsOf: indexFile) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let records = try? decoder.decode([SnapshotRecord].self, from: data) {
                    all.append(contentsOf: records)
                }
            }
        }
        return all.sorted { $0.timestamp > $1.timestamp }
    }
    
    public func listSnapshots(for projectURL: URL) -> [SnapshotRecord] {
        return loadSnapshots(for: projectURL).sorted { $0.timestamp > $1.timestamp }
    }
    
    public func snapshotFileURL(for record: SnapshotRecord) -> URL {
        let projDir = backupsDirectory.appendingPathComponent(record.projectHash, isDirectory: true)
        return projDir.appendingPathComponent(record.snapshotFileName)
    }
    
    // MARK: - Snapshot Restoration / Rollback
    public func restoreSnapshot(snapshotId: UUID, to destinationURL: URL? = nil) async throws {
        let all = listAllSnapshots()
        guard let snapshot = all.first(where: { $0.id == snapshotId }) else {
            throw VaultError.targetFileNotFound("Snapshot not found (\(snapshotId.uuidString))")
        }
        
        let snapshotSourceURL = snapshotFileURL(for: snapshot)
        guard fm.fileExists(atPath: snapshotSourceURL.path) else {
            throw VaultError.vaultFileNotFound("Snapshot vault file missing: \(snapshotSourceURL.path)")
        }
        
        let targetVaultURL = destinationURL ?? URL(fileURLWithPath: snapshot.vaultPath)
        let plainURL = VaultEngine.shared.plainFileURL(for: targetVaultURL)
        
        // Before overwriting current vault, create a pre-rollback snapshot of whatever is currently on disk
        if fm.fileExists(atPath: targetVaultURL.path) {
            _ = try? await createSnapshot(for: targetVaultURL, trigger: .autoSnapshot, note: "Auto-backup before rollback to v\(snapshot.version)")
        }
        
        // Atomically replace target vault with the snapshot vault payload
        let snapshotData = try Data(contentsOf: snapshotSourceURL)
        try snapshotData.write(to: targetVaultURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetVaultURL.path)
        
        // Read secrets from the restored snapshot to refresh the masked decoy file on disk
        if let decryptedSecrets = try? await VaultEngine.shared.readDecryptedSecrets(vaultURL: targetVaultURL) {
            var lines = ["# Managed by sec Pro (Restored from Snapshot v\(snapshot.version))"]
            for k in decryptedSecrets.keys.sorted() {
                lines.append("\(k)=\(decryptedSecrets[k] ?? "")")
            }
            let rawContent = lines.joined(separator: "\n")
            let dummy = EnvParser.shared.generateDummyTemplate(from: rawContent, fileName: plainURL.lastPathComponent)
            try? dummy.write(to: plainURL, atomically: true, encoding: .utf8)
        }
        
        // Re-register in active registry if not already registered
        RegistryManager.shared.register(vaultURL: targetVaultURL, plainURL: plainURL)
    }
    
    public func deleteSnapshot(snapshotId: UUID) throws {
        let all = listAllSnapshots()
        guard let snapshot = all.first(where: { $0.id == snapshotId }) else { return }
        
        let projectURL = URL(fileURLWithPath: snapshot.projectPath)
        var list = loadSnapshots(for: projectURL)
        list.removeAll { $0.id == snapshotId }
        saveSnapshots(list, for: projectURL)
        
        let fileURL = snapshotFileURL(for: snapshot)
        try? fm.removeItem(at: fileURL)
    }
    
    // MARK: - Trash Management (Soft Delete)
    public func loadTrash() -> [TrashRecord] {
        ensureDirectories()
        guard let data = try? Data(contentsOf: trashIndexURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TrashRecord].self, from: data)) ?? []
    }
    
    private func saveTrash(_ list: [TrashRecord]) {
        ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: trashIndexURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: trashIndexURL.path)
    }
    
    public func trashFileURL(for record: TrashRecord) -> URL {
        return trashDirectory.appendingPathComponent(record.trashFileName)
    }
    
    @discardableResult
    public func moveToTrash(vaultURL: URL, reason: String = "Vault unshielded or deleted") async throws -> TrashRecord {
        ensureDirectories()
        let resolvedVault = vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: resolvedVault.path) else {
            throw VaultError.vaultFileNotFound(resolvedVault.path)
        }
        
        let plainURL = VaultEngine.shared.plainFileURL(for: resolvedVault)
        let projectURL = plainURL.deletingLastPathComponent()
        let targetFileName = plainURL.lastPathComponent
        let projectName = projectURL.lastPathComponent
        
        // Take an immutable final snapshot in project backups as well
        _ = try? await createSnapshot(for: resolvedVault, trigger: .movedToTrash, note: reason)
        
        let trashId = UUID()
        let trashFileName = "\(trashId.uuidString).vault"
        let trashDestination = trashDirectory.appendingPathComponent(trashFileName)
        
        // Copy vault to trash directory
        try fm.copyItem(at: resolvedVault, to: trashDestination)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: trashDestination.path)
        
        var keyCount = 0
        if let secrets = try? await VaultEngine.shared.readDecryptedSecrets(vaultURL: resolvedVault) {
            keyCount = secrets.count
        }
        
        let attrs = try? fm.attributesOfItem(atPath: resolvedVault.path)
        let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        
        let trashRecord = TrashRecord(
            id: trashId,
            vaultPath: resolvedVault.path,
            plainPath: plainURL.path,
            projectName: projectName,
            projectPath: projectURL.path,
            targetFileName: targetFileName,
            removedAt: Date(),
            originalKeyCount: keyCount,
            fileSizeBytes: fileSize,
            trashFileName: trashFileName,
            reason: reason
        )
        
        var currentTrash = loadTrash()
        currentTrash.insert(trashRecord, at: 0)
        saveTrash(currentTrash)
        
        return trashRecord
    }
    
    public func restoreFromTrash(trashId: UUID) async throws -> URL {
        var currentTrash = loadTrash()
        guard let idx = currentTrash.firstIndex(where: { $0.id == trashId }) else {
            throw VaultError.targetFileNotFound("Trash entry not found (\(trashId.uuidString))")
        }
        let record = currentTrash[idx]
        let trashVaultURL = trashFileURL(for: record)
        guard fm.fileExists(atPath: trashVaultURL.path) else {
            throw VaultError.vaultFileNotFound("Trash vault file missing: \(trashVaultURL.path)")
        }
        
        let targetVaultURL = URL(fileURLWithPath: record.vaultPath)
        let plainURL = URL(fileURLWithPath: record.plainPath)
        let parentDir = targetVaultURL.deletingLastPathComponent()
        
        // Ensure parent directory exists
        try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Move/copy restored vault back to original path
        try? fm.removeItem(at: targetVaultURL)
        try fm.copyItem(at: trashVaultURL, to: targetVaultURL)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetVaultURL.path)
        
        // Refresh decoy file on disk
        if let decryptedSecrets = try? await VaultEngine.shared.readDecryptedSecrets(vaultURL: targetVaultURL) {
            var lines = ["# Managed by sec Pro (Restored from Trash)"]
            for k in decryptedSecrets.keys.sorted() {
                lines.append("\(k)=\(decryptedSecrets[k] ?? "")")
            }
            let raw = lines.joined(separator: "\n")
            let dummy = EnvParser.shared.generateDummyTemplate(from: raw, fileName: plainURL.lastPathComponent)
            try? dummy.write(to: plainURL, atomically: true, encoding: .utf8)
        }
        
        // Register in active registry
        RegistryManager.shared.register(vaultURL: targetVaultURL, plainURL: plainURL)
        
        // Remove from trash index and storage
        currentTrash.remove(at: idx)
        saveTrash(currentTrash)
        try? fm.removeItem(at: trashVaultURL)
        
        return targetVaultURL
    }
    
    public func purgeTrashItem(trashId: UUID) throws {
        var currentTrash = loadTrash()
        guard let idx = currentTrash.firstIndex(where: { $0.id == trashId }) else { return }
        let record = currentTrash[idx]
        let file = trashFileURL(for: record)
        try? fm.removeItem(at: file)
        currentTrash.remove(at: idx)
        saveTrash(currentTrash)
    }
    
    public func purgeAllTrash() throws {
        let currentTrash = loadTrash()
        for item in currentTrash {
            let file = trashFileURL(for: item)
            try? fm.removeItem(at: file)
        }
        saveTrash([])
    }
    
    // MARK: - Batch Backup All
    public func backupAllRegisteredVaults() async throws -> [SnapshotRecord] {
        let records = RegistryManager.shared.loadRegistry().records
        var created: [SnapshotRecord] = []
        for record in records {
            let vaultURL = URL(fileURLWithPath: record.vaultPath)
            if fm.fileExists(atPath: vaultURL.path) {
                if let snap = try? await createSnapshot(for: vaultURL, trigger: .manual, note: "Batch Manual Backup") {
                    created.append(snap)
                }
            }
        }
        return created
    }
}
