import Foundation
import SwiftUI
import SecCore

public enum EventSeverity: String, Codable {
    case shielded
    case success
    case warning
    case alert
    
    public var color: Color {
        switch self {
        case .shielded:
            return Color.blue
        case .success:
            return Color.green
        case .warning:
            return Color.orange
        case .alert:
            return Color.red
        }
    }
    
    public var iconName: String {
        switch self {
        case .shielded:
            return "shield.lefthalf.filled"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .alert:
            return "bell.badge.fill"
        }
    }
}

public struct RadarEvent: Identifiable, Equatable {
    public let id: UUID
    public let agentName: String
    public let action: String
    public let detail: String
    public let timestamp: Date
    public let severity: EventSeverity
    public let targetFile: String
    
    public init(
        id: UUID = UUID(),
        agentName: String,
        action: String,
        detail: String,
        timestamp: Date = Date(),
        severity: EventSeverity,
        targetFile: String = ".env"
    ) {
        self.id = id
        self.agentName = agentName
        self.action = action
        self.detail = detail
        self.timestamp = timestamp
        self.severity = severity
        self.targetFile = targetFile
    }
    
    public var relativeTime: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        return "\(hours)h ago"
    }
    
    public var agentIcon: String {
        switch agentName.lowercased() {
        case let name where name.contains("cursor"):
            return "wand.and.stars"
        case let name where name.contains("claude"):
            return "brain.head.profile"
        case let name where name.contains("copilot"):
            return "chevron.left.forwardslash.chevron.right"
        case let name where name.contains("terminal") || name.contains("npm") || name.contains("cargo"):
            return "terminal.fill"
        default:
            return "bolt.shield.fill"
        }
    }
}

public enum VaultProtectionStatus: String, Codable {
    case protectedWithDecoy = "Protected"
    case inRAM = "In Memory"
    case unprotected = "Unprotected"
    
    public var color: Color {
        switch self {
        case .protectedWithDecoy:
            return Color(nsColor: .systemGreen)
        case .inRAM:
            return Color(nsColor: .systemPurple)
        case .unprotected:
            return Color(nsColor: .systemOrange)
        }
    }
    
    public var iconName: String {
        switch self {
        case .protectedWithDecoy:
            return "lock.shield.fill"
        case .inRAM:
            return "memorychip.fill"
        case .unprotected:
            return "exclamationmark.triangle.fill"
        }
    }
}

public struct VaultFileInfo: Identifiable, Equatable, Hashable {
    public var id: String { filename }
    public var filename: String
    public var status: VaultProtectionStatus
    public var keyCount: Int
    public var lastModified: Date
    
    public init(
        filename: String,
        status: VaultProtectionStatus = .protectedWithDecoy,
        keyCount: Int = 0,
        lastModified: Date = Date()
    ) {
        self.filename = filename
        self.status = status
        self.keyCount = keyCount
        self.lastModified = lastModified
    }
}

public struct VaultItem: Identifiable, Equatable, Hashable {
    public let id: UUID
    public var directoryPath: String
    public var projectName: String
    public var targetFiles: [String]
    public var files: [VaultFileInfo]
    public var activeFile: String
    public var status: VaultProtectionStatus
    public var lastModified: Date
    public var keyCount: Int
    
    public init(
        id: UUID = UUID(),
        directoryPath: String,
        projectName: String,
        targetFiles: [String],
        files: [VaultFileInfo] = [],
        activeFile: String? = nil,
        status: VaultProtectionStatus = .protectedWithDecoy,
        lastModified: Date = Date(),
        keyCount: Int = 0
    ) {
        self.id = id
        self.directoryPath = directoryPath
        self.projectName = projectName
        self.targetFiles = targetFiles
        self.activeFile = activeFile ?? targetFiles.first ?? ".env"
        self.status = status
        self.lastModified = lastModified
        self.keyCount = keyCount
        
        if files.isEmpty {
            self.files = targetFiles.map {
                VaultFileInfo(filename: $0, status: status, keyCount: keyCount, lastModified: lastModified)
            }
        } else {
            self.files = files
        }
    }
    
    public var isFolderStack: Bool {
        return files.count > 1 || targetFiles.count > 1
    }
    
    public var totalFileCount: Int {
        return max(files.count, targetFiles.count)
    }
    
    public var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if directoryPath.hasPrefix(home) {
            return "~" + directoryPath.dropFirst(home.count)
        }
        return directoryPath
    }
}

public enum GracePeriodOption: String, CaseIterable, Identifiable {
    case strict = "Strict"
    case m15 = "15m"
    case m30 = "30m"
    case h1 = "1h"
    case untilSleep = "Sleep"
    
    public var id: String { rawValue }
    
    public var durationSeconds: Int? {
        switch self {
        case .strict:
            return 0
        case .m15:
            return 15 * 60
        case .m30:
            return 30 * 60
        case .h1:
            return 60 * 60
        case .untilSleep:
            return nil
        }
    }
    
    public var iconName: String {
        switch self {
        case .strict:
            return "hand.raised.fill"
        case .m15, .m30, .h1:
            return "timer"
        case .untilSleep:
            return "moon.zzz.fill"
        }
    }
}

// MARK: - Navigation Tabs for Standalone Mac App
public enum NavigationTab: String, CaseIterable, Identifiable {
    case allVaults = "All Vaults"
    case shieldedDecoys = "Active Decoys"
    case inRAM = "In Memory"
    case backups = "Backups & Trash"
    case scanner = "Scanner"
    case radar = "Activity Log"
    case settings = "Settings"
    case runner = "Runner Studio" // Hidden from default navigation
    
    public var id: String { rawValue }
    
    public static var allCases: [NavigationTab] {
        return [.allVaults, .shieldedDecoys, .inRAM, .backups, .scanner, .radar, .settings]
    }
    
    public var iconName: String {
        switch self {
        case .allVaults:
            return "folder.badge.gearshape"
        case .shieldedDecoys:
            return "shield.checkered"
        case .inRAM:
            return "memorychip"
        case .backups:
            return "clock.arrow.circlepath"
        case .scanner:
            return "magnifyingglass.circle"
        case .radar:
            return "dot.radiowaves.left.and.right"
        case .settings:
            return "gearshape"
        case .runner:
            return "play.rectangle.on.rectangle"
        }
    }
    
    public var tooltip: String {
        switch self {
        case .allVaults:
            return "View all protected and encrypted project vaults"
        case .shieldedDecoys:
            return "Filter vaults with active masked decoy files on disk"
        case .inRAM:
            return "Filter vaults currently decrypted and active in RAM"
        case .backups:
            return "View version snapshots, restore previous versions, and manage trashed vaults"
        case .scanner:
            return "Scan directories to find unencrypted plaintext secret files"
        case .radar:
            return "View audit log of agent file accesses and runtime injections"
        case .settings:
            return "Configure security preferences, auto-lock grace periods, and integrations"
        case .runner:
            return "Execute commands with secrets injected into RAM"
        }
    }
}

// MARK: - Secret Key-Value Entry for In-App Inspector & Editor
public struct SecretEntry: Identifiable, Equatable {
    public let id: UUID
    public var key: String
    public var value: String
    public var isRevealed: Bool
    
    public init(id: UUID = UUID(), key: String, value: String, isRevealed: Bool = false) {
        self.id = id
        self.key = key
        self.value = value
        self.isRevealed = isRevealed
    }
}

// MARK: - Discovery Scanner Discovered File
public struct DiscoveredSecretFile: Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let path: String
    public let filename: String
    public let isLocked: Bool
    public let hasDecoy: Bool
    public let sizeBytes: Int64
    public let modifiedDate: Date
    
    public init(
        id: UUID = UUID(),
        url: URL,
        path: String,
        filename: String,
        isLocked: Bool,
        hasDecoy: Bool,
        sizeBytes: Int64,
        modifiedDate: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.path = path
        self.filename = filename
        self.isLocked = isLocked
        self.hasDecoy = hasDecoy
        self.sizeBytes = sizeBytes
        self.modifiedDate = modifiedDate
    }
    
    public var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Runner Terminal Log Entry
public struct RunnerLogEntry: Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let isError: Bool
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), text: String, isError: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.isError = isError
    }
}

// MARK: - Deleted Secret Undo Buffer Entry
public struct DeletedSecretUndo: Identifiable, Equatable {
    public let id: UUID
    public let originalIndex: Int
    public let secret: SecretEntry
    public let expiresAt: Date
    
    public init(originalIndex: Int, secret: SecretEntry, durationSeconds: Double = 5.0) {
        self.id = UUID()
        self.originalIndex = originalIndex
        self.secret = secret
        self.expiresAt = Date().addingTimeInterval(durationSeconds)
    }
    
    public var isExpired: Bool {
        return Date() >= expiresAt
    }
}

