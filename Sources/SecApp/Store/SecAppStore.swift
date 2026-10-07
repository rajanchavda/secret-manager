import Foundation
import SwiftUI
import Combine
import SecCore
import AppKit

@MainActor
public final class SecAppStore: ObservableObject {
    public static let shared = SecAppStore()
    
    // MARK: - Navigation State
    @Published public var selectedTab: NavigationTab = .allVaults
    @Published public var selectedVault: VaultItem? = nil
    
    // MARK: - Vaults & Filtering
    @Published public var vaults: [VaultItem] = []
    @Published public var searchQuery: String = ""
    @Published public var statusMessage: String? = nil
    
    // MARK: - Secret Inspector & Editor State
    @Published public var isAppSessionAuthenticated: Bool = false
    @Published public var isVaultUnlockedInUI: Bool = false
    @Published public var isAuthenticating: Bool = false
    @Published public var currentSecrets: [SecretEntry] = []
    @Published public var currentRawEnv: String = ""
    @Published public var originalRawEnv: String = ""
    
    public var isRawEnvDirty: Bool {
        return isVaultUnlockedInUI && currentRawEnv != originalRawEnv
    }
    public var inRAMVaultPaths: Set<String> = []
    @Published public var isAllSecretsRevealed: Bool = false
    @Published public var secretEditorTab: Int = 0 // 0 = Table, 1 = Raw .env, 2 = Security Audit
    
    // MARK: - Runner Studio State
    @Published public var runnerSelectedVault: VaultItem? = nil
    @Published public var runnerCommand: String = "npm run dev"
    @Published public var isProcessRunning: Bool = false
    @Published public var runningPID: Int32? = nil
    @Published public var runnerLogs: [RunnerLogEntry] = []
    private var activeProcess: Process? = nil
    private var processOutPipe: Pipe? = nil
    private var processErrPipe: Pipe? = nil
    
    // MARK: - Discovery Scanner State
    @Published public var scanDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @Published public var isScanning: Bool = false
    @Published public var discoveredFiles: [DiscoveredSecretFile] = []
    
    // MARK: - AI Agent Radar Feed
    @Published public var radarEvents: [RadarEvent] = []
    
    // MARK: - System Security & Settings
    @Published public var selectedGraceOption: GracePeriodOption = .m15
    @Published public var remainingGraceSeconds: Int = 0
    @Published public var isGraceActive: Bool = false
    @Published public var showSettings: Bool = false
    @Published public var isFinderActionsInstalled: Bool = false
    @Published public var showProtectFileModal: Bool = false
    @Published public var pendingEncryptionURL: URL? = nil
    @Published public var showEncryptConfirmation: Bool = false
    
    // MARK: - Backups, Version History & Trash
    @Published public var snapshots: [SnapshotRecord] = []
    @Published public var trashRecords: [TrashRecord] = []
    @Published public var activeUndoEntry: DeletedSecretUndo? = nil
    @Published public var isBackingUpAll: Bool = false
    @Published public var previewSnapshotSecrets: [SecretEntry] = []
    @Published public var previewSnapshotRawText: String = ""
    @Published public var isPreviewingSnapshot: Bool = false
    @Published public var activePreviewSnapshot: SnapshotRecord? = nil
    private var undoTimerCancellable: AnyCancellable?
    
    // MARK: - Process Memory & RAM Vault Status
    @Published public var currentMemoryInfo: ProcessMemoryInfo = MemoryMonitor.currentProcessMemory()
    
    // MARK: - Dynamic Font Scaling & Zoom
    public static let minFontScale: CGFloat = 0.8
    public static let maxFontScale: CGFloat = 1.6
    public static let defaultFontScale: CGFloat = 1.0
    public static let fontScaleStep: CGFloat = 0.1
    
    @Published public var fontScale: CGFloat = 1.0 {
        didSet {
            UserDefaults.standard.set(Double(fontScale), forKey: "sec_app_font_scale")
        }
    }
    
    private var timerCancellable: AnyCancellable?
    private var sleepObserver: NSObjectProtocol?
    private var lockObservers: [NSObjectProtocol] = []
    
    public init() {
        // Configure SessionManager default duration for the App
        let defaultDuration: Double
        if let sec = selectedGraceOption.durationSeconds, sec > 0 {
            defaultDuration = Double(sec)
        } else if selectedGraceOption == .untilSleep {
            defaultDuration = 24 * 3600
        } else {
            defaultDuration = 0
        }
        SessionManager.shared.setSessionDuration(seconds: defaultDuration)
        
        // Restore session if still active in this process
        if SessionManager.shared.isSessionActive(),
           let remaining = SessionManager.shared.remainingTimeSeconds(), remaining > 0 {
            self.isGraceActive = true
            self.isAppSessionAuthenticated = true
            self.isVaultUnlockedInUI = true
            self.remainingGraceSeconds = Int(remaining)
        } else {
            self.isGraceActive = false
            self.isAppSessionAuthenticated = false
            self.isVaultUnlockedInUI = false
            self.remainingGraceSeconds = 0
        }
        
        // Restore font scale preference
        let savedScale = UserDefaults.standard.double(forKey: "sec_app_font_scale")
        if savedScale >= Double(Self.minFontScale) && savedScale <= Double(Self.maxFontScale) {
            self.fontScale = CGFloat(savedScale)
        } else {
            self.fontScale = Self.defaultFontScale
        }
        
        loadVaultsFromRegistry()
        loadBackupsAndTrash()
        startGraceCountdownTimer()
        checkFinderStatus()
        setupSleepObserver()
        setupFileWatcher()
        
        if let first = vaults.first {
            self.selectedVault = first
            self.runnerSelectedVault = first
            if self.isAppSessionAuthenticated {
                Task {
                    await self.unlockVaultSecrets(for: first)
                }
            }
        }
    }
    
    // MARK: - Filtered Vaults
    public var filteredVaults: [VaultItem] {
        let baseList: [VaultItem]
        switch selectedTab {
        case .allVaults:
            baseList = vaults
        case .shieldedDecoys:
            baseList = vaults.filter { $0.status == .protectedWithDecoy }
        case .inRAM:
            baseList = vaults.filter { $0.status == .inRAM }
        default:
            baseList = vaults
        }
        
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return baseList
        }
        return baseList.filter {
            $0.projectName.localizedCaseInsensitiveContains(query) ||
            $0.directoryPath.localizedCaseInsensitiveContains(query) ||
            $0.targetFiles.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
    
    // MARK: - Global Shield Status
    public var globalShieldActive: Bool {
        return !vaults.contains { $0.status == .unprotected }
    }
    
    public var unlockedVaultsCount: Int {
        vaults.filter { $0.status == .inRAM }.count
    }
    
    // MARK: - Process Memory & RAM Vault Computed Helpers
    public var inRAMVaultsCount: Int {
        vaults.filter { $0.status == .inRAM }.count
    }
    
    public var inRAMSecretsCount: Int {
        var count = 0
        if isVaultUnlockedInUI && !currentSecrets.isEmpty {
            count += currentSecrets.count
        }
        for vault in vaults where vault.status == .inRAM {
            if !(isVaultUnlockedInUI && selectedVault?.directoryPath == vault.directoryPath) {
                count += vault.keyCount
            }
        }
        return count
    }
    
    public var formattedMemoryUsage: String {
        return currentMemoryInfo.formattedResident
    }
    
    public var inRAMSecretsSummary: String {
        if inRAMSecretsCount > 0 {
            return "\(inRAMSecretsCount) secret\(inRAMSecretsCount == 1 ? "" : "s") in RAM"
        } else {
            return "RAM Cleared (0 secrets)"
        }
    }
    
    public func refreshMemoryUsage() {
        self.currentMemoryInfo = MemoryMonitor.currentProcessMemory()
    }
    
    public var statusBadgeText: String {
        let protectedCount = vaults.filter { $0.status == .protectedWithDecoy || $0.status == .inRAM }.count
        if protectedCount == 0 {
            return "No Vaults"
        }
        return "\(protectedCount) Protected"
    }
    
    public var menuBarIcon: String {
        if !globalShieldActive {
            return "lock.open.trianglebadge.exclamationmark"
        }
        if isGraceActive {
            return "lock.shield.fill"
        }
        return "lock.fill"
    }
    
    public var formattedRemainingTime: String {
        guard isGraceActive, remainingGraceSeconds > 0 else {
            if selectedGraceOption == .strict {
                return "Strict"
            }
            return isAppSessionAuthenticated ? "Strict" : "Locked"
        }
        let mins = remainingGraceSeconds / 60
        let secs = remainingGraceSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    // MARK: - Vault Registry Management
    public func loadVaultsFromRegistry() {
        let records = RegistryManager.shared.loadRegistry().records
        
        // Group records by normalized directory path, only keeping records where the .vault file actually exists on disk
        // Strictly exclude internal ~/.sec backups, trash, or metadata files from the project vaults list
        var grouped: [String: [VaultRecord]] = [:]
        for record in records {
            if record.vaultPath.contains("/.sec/") || record.vaultPath.hasSuffix(".vault.bak") {
                continue
            }
            let vaultURL = URL(fileURLWithPath: record.vaultPath)
            guard FileManager.default.fileExists(atPath: vaultURL.path) else {
                continue
            }
            let plainURL = URL(fileURLWithPath: record.plainPath)
            let projectDir = plainURL.deletingLastPathComponent().path
            if projectDir.contains("/.sec/") {
                continue
            }
            grouped[projectDir, default: []].append(record)
        }
        
        self.vaults = grouped.compactMap { (projectDir, folderRecords) -> VaultItem? in
            let projectName = URL(fileURLWithPath: projectDir).lastPathComponent
            let isVaultActiveInRAM = self.inRAMVaultPaths.contains(projectDir) || (self.isVaultUnlockedInUI && self.selectedVault?.directoryPath == projectDir)
            let existingVault = self.vaults.first(where: { $0.directoryPath == projectDir })
            let stableId = existingVault?.id ?? UUID()
            let preservedActiveFile = existingVault?.activeFile
            
            var targetFiles: [String] = []
            var files: [VaultFileInfo] = []
            var totalKeyCount = 0
            var maxDate = Date.distantPast
            var hasUnprotected = false
            var hasInRAM = false
            
            for record in folderRecords {
                let vaultURL = URL(fileURLWithPath: record.vaultPath)
                guard FileManager.default.fileExists(atPath: vaultURL.path) else {
                    continue
                }
                let plainURL = URL(fileURLWithPath: record.plainPath)
                let fileName = plainURL.lastPathComponent
                targetFiles.append(fileName)
                
                var status: VaultProtectionStatus = .protectedWithDecoy
                if FileManager.default.fileExists(atPath: plainURL.path) {
                    if let content = try? String(contentsOf: plainURL, encoding: .utf8), VaultEngine.shared.isDummyContent(content) {
                        if isVaultActiveInRAM {
                            status = .inRAM
                            hasInRAM = true
                        } else {
                            status = .protectedWithDecoy
                        }
                    } else {
                        status = .unprotected
                        hasUnprotected = true
                    }
                }
                if status == .inRAM {
                    hasInRAM = true
                }
                
                var keyCount = 0
                if let data = try? Data(contentsOf: vaultURL) {
                    keyCount = max(1, data.count / 40)
                }
                totalKeyCount += keyCount
                
                let date = record.lastLockedAt ?? Date()
                if date > maxDate { maxDate = date }
                
                files.append(VaultFileInfo(
                    filename: fileName,
                    status: status,
                    keyCount: keyCount,
                    lastModified: date
                ))
            }
            
            // Only show folders that actually have existing encrypted files
            guard !files.isEmpty else { return nil }
            
            let folderStatus: VaultProtectionStatus
            if hasUnprotected {
                folderStatus = .unprotected
            } else if hasInRAM || isVaultActiveInRAM {
                folderStatus = .inRAM
            } else {
                folderStatus = .protectedWithDecoy
            }
            
            let chosenActiveFile: String?
            if let active = preservedActiveFile, targetFiles.contains(active) {
                chosenActiveFile = active
            } else {
                chosenActiveFile = targetFiles.first
            }
            
            return VaultItem(
                id: stableId,
                directoryPath: projectDir,
                projectName: projectName.isEmpty ? "Vault" : projectName,
                targetFiles: targetFiles,
                files: files,
                activeFile: chosenActiveFile,
                status: folderStatus,
                lastModified: maxDate == Date.distantPast ? Date() : maxDate,
                keyCount: totalKeyCount
            )
        }.sorted { $0.projectName < $1.projectName }
        
        if let current = selectedVault, let matching = vaults.first(where: { $0.directoryPath == current.directoryPath }) {
            selectedVault = matching
        } else {
            selectedVault = vaults.first
            if vaults.isEmpty {
                currentSecrets = []
                currentRawEnv = ""
                originalRawEnv = ""
                isVaultUnlockedInUI = false
            }
        }
        updateWatchedDirectories()
    }
    
    // MARK: - Real-time Finder File System Monitoring
    private func setupFileWatcher() {
        FileWatcher.shared.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.pruneRegistry()
            }
        }
        updateWatchedDirectories()
    }
    
    private func updateWatchedDirectories() {
        let dirs = vaults.map { URL(fileURLWithPath: $0.directoryPath) }
        FileWatcher.shared.watchDirectories(dirs)
    }
    
    // MARK: - Secret Inspector & Editor Operations
    public func selectVault(_ vault: VaultItem) {
        selectedVault = vault
        isAllSecretsRevealed = false
        
        if isAppSessionAuthenticated && SessionManager.shared.isSessionActive() {
            // Already authenticated in this session: load secrets seamlessly without prompting Touch ID
            isVaultUnlockedInUI = true
            Task {
                await unlockVaultSecrets(for: vault)
            }
        } else {
            // Locked: require user to tap Unlock with Touch ID
            isVaultUnlockedInUI = false
            currentSecrets = []
            currentRawEnv = ""
        }
    }
    
    public func selectActiveFile(_ filename: String, for vault: VaultItem) async {
        guard let idx = vaults.firstIndex(where: { $0.id == vault.id }) else { return }
        vaults[idx].activeFile = filename
        selectedVault = vaults[idx]
        
        if isAppSessionAuthenticated && SessionManager.shared.isSessionActive() {
            isVaultUnlockedInUI = true
            await unlockVaultSecrets(for: vaults[idx], specificFile: filename)
        } else {
            isVaultUnlockedInUI = false
            currentSecrets = []
            currentRawEnv = ""
        }
    }
    
    /// Extending the unlocked window is itself a privileged action, so it needs a fresh Touch ID
    public func extendGracePeriod(minutes: Int) {
        Task {
            do {
                try await BiometricAuth.shared.authenticate(reason: "Authenticate with Touch ID to extend the Secret Manager session by \(minutes) minutes")
            } catch {
                showTemporaryStatus("Session not extended: \(error.localizedDescription)")
                return
            }
            let additional = minutes * 60
            SessionManager.shared.extendSession(additionalSeconds: Double(additional))
            remainingGraceSeconds += additional
            isGraceActive = true
            playHapticFeedback()
            showTemporaryStatus("Added +\(minutes)m to session timer")
        }
    }
    
    public func unlockVaultSecrets(for vault: VaultItem, specificFile: String? = nil) async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        let targetFile = specificFile ?? vault.activeFile
        let vaultURL = URL(fileURLWithPath: vault.directoryPath).appendingPathComponent(targetFile).appendingPathExtension("vault")
        
        let targetDuration: Double
        if let sec = selectedGraceOption.durationSeconds, sec > 0 {
            targetDuration = Double(sec)
        } else if selectedGraceOption == .untilSleep {
            targetDuration = 24 * 3600
        } else {
            targetDuration = 0
        }
        SessionManager.shared.setSessionDuration(seconds: targetDuration)
        
        let isFirstAuth = !SessionManager.shared.isSessionActive()
        
        do {
            let data = try await VaultEngine.shared.readDecryptedData(
                vaultURL: vaultURL,
                promptReason: "Authenticate with Touch ID to unlock Secret Manager secrets"
            )
            
            self.isAppSessionAuthenticated = true
            self.isVaultUnlockedInUI = true
            
            if targetDuration > 0 {
                self.isGraceActive = true
                if isFirstAuth || self.remainingGraceSeconds <= 0 {
                    self.remainingGraceSeconds = Int(targetDuration)
                }
            } else {
                self.isGraceActive = false
                self.remainingGraceSeconds = 0
            }
            
            if let str = String(data: data, encoding: .utf8) {
                self.currentRawEnv = str
                self.originalRawEnv = str
                let parsed = EnvParser.shared.parse(str)
                self.currentSecrets = parsed.keys.sorted().map { k in
                    SecretEntry(key: k, value: parsed[k] ?? "", isRevealed: false)
                }
            } else {
                self.currentRawEnv = "[Binary file or non-UTF8 encrypted data]"
                self.originalRawEnv = self.currentRawEnv
                self.currentSecrets = [SecretEntry(key: "BINARY_DATA", value: "\(data.count) bytes", isRevealed: true)]
            }
            
            // Mark vault as inRAM
            inRAMVaultPaths.insert(vault.directoryPath)
            if let idx = vaults.firstIndex(where: { $0.directoryPath == vault.directoryPath }) {
                vaults[idx].status = .inRAM
                if let fIdx = vaults[idx].files.firstIndex(where: { $0.filename == targetFile }) {
                    vaults[idx].files[fIdx].status = .inRAM
                }
                selectedVault = vaults[idx]
            }
            
            showTemporaryStatus("Vault unlocked in memory")
            playHapticFeedback()
            
            addRadarEvent(
                agent: "Secret Manager Inspector",
                action: isFirstAuth ? "Unlocked Secret Manager with Touch ID" : "Inspected secrets (Active Session)",
                detail: "Decrypted \(currentSecrets.count) keys into secure RAM",
                severity: .shielded
            )
        } catch {
            showTemporaryStatus("Authentication cancelled or failed")
            addRadarEvent(
                agent: "Secret Manager Inspector",
                action: "Touch ID inspection failed",
                detail: error.localizedDescription,
                severity: .alert
            )
        }
    }
    
    public func toggleSecretVisibility(id: UUID) {
        if let idx = currentSecrets.firstIndex(where: { $0.id == id }) {
            currentSecrets[idx].isRevealed.toggle()
        }
    }
    
    public func toggleAllSecretsVisibility() {
        isAllSecretsRevealed.toggle()
        for i in 0..<currentSecrets.count {
            currentSecrets[i].isRevealed = isAllSecretsRevealed
        }
    }
    
    public func addSecretEntry(key: String, value: String) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        let entry = SecretEntry(key: trimmedKey, value: value, isRevealed: true)
        currentSecrets.append(entry)
        regenerateRawFromTable()
        showTemporaryStatus("Added '\(trimmedKey)' (unsaved)")
    }
    
    public func deleteSecretEntry(id: UUID) {
        if let idx = currentSecrets.firstIndex(where: { $0.id == id }) {
            let secret = currentSecrets[idx]
            currentSecrets.remove(at: idx)
            regenerateRawFromTable()
            
            // Set 5-second undo toast buffer
            activeUndoEntry = DeletedSecretUndo(originalIndex: idx, secret: secret, durationSeconds: 5.0)
            undoTimerCancellable?.cancel()
            undoTimerCancellable = Timer.publish(every: 5.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.activeUndoEntry = nil
                    self?.undoTimerCancellable?.cancel()
                }
            
            showTemporaryStatus("Removed '\(secret.key)' (5s to Undo)")
        }
    }
    
    public func undoDeleteSecretEntry() {
        guard let undo = activeUndoEntry else { return }
        let insertIndex = min(undo.originalIndex, currentSecrets.count)
        currentSecrets.insert(undo.secret, at: insertIndex)
        regenerateRawFromTable()
        activeUndoEntry = nil
        undoTimerCancellable?.cancel()
        showTemporaryStatus("Restored '\(undo.secret.key)'")
        playHapticFeedback()
    }
    
    private func regenerateRawFromTable() {
        var lines: [String] = []
        lines.append("# Managed by Secret Manager")
        for secret in currentSecrets {
            lines.append("\(secret.key)=\(secret.value)")
        }
        currentRawEnv = lines.joined(separator: "\n")
    }
    
    public func saveSecretsToVault(for vault: VaultItem) async {
        let trimmed = currentRawEnv.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !currentSecrets.isEmpty {
            showTemporaryStatus("Save aborted: Buffer is empty. Deleting all secrets is blocked to prevent data loss.")
            playHapticFeedback()
            return
        }
        
        guard let data = currentRawEnv.data(using: .utf8) else { return }
        let targetFile = vault.activeFile
        let vaultURL = URL(fileURLWithPath: vault.directoryPath).appendingPathComponent(targetFile).appendingPathExtension("vault")
        
        do {
            // Never overwrite a vault on an expired session
            if !SessionManager.shared.isSessionActive() {
                try await BiometricAuth.shared.authenticate(reason: "sec requires Touch ID to save and re-encrypt '\(targetFile)'")
                SessionManager.shared.startSession()
            }
            try await VaultEngine.shared.updateVault(vaultURL: vaultURL, plaintextData: data)
            self.originalRawEnv = currentRawEnv
            self.inRAMVaultPaths.insert(vault.directoryPath)
            showTemporaryStatus("Saved & Re-encrypted with Touch ID")
            playHapticFeedback()
            
            // Refresh table
            let parsed = EnvParser.shared.parse(currentRawEnv)
            self.currentSecrets = parsed.keys.sorted().map { k in
                SecretEntry(key: k, value: parsed[k] ?? "", isRevealed: false)
            }
            
            addRadarEvent(
                agent: "Secret Manager Editor",
                action: "Updated vault with AES-256-GCM (Cmd+S)",
                detail: "Updated \(targetFile).vault & refreshed decoy on disk",
                severity: .success
            )
            loadVaultsFromRegistry()
            loadBackupsAndTrash()
        } catch {
            showTemporaryStatus("Save failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Lock & Unlock Workflows
    public func lockFile(at fileURL: URL, force: Bool = false) async {
        let fileName = fileURL.lastPathComponent
        do {
            _ = try await VaultEngine.shared.lock(fileURL: fileURL, force: force)
            showTemporaryStatus("Shielded '\(fileName)' with Touch ID")
            playHapticFeedback()
            
            addRadarEvent(
                agent: "Secret Manager",
                action: "Locked '\(fileName)' with Touch ID",
                detail: "Generated masked decoy on disk & AES-256 vault",
                severity: .success
            )
            loadVaultsFromRegistry()
            loadBackupsAndTrash()
        } catch {
            showTemporaryStatus("Lock failed: \(error.localizedDescription)")
        }
    }
    
    public func relockVault(vault: VaultItem) async {
        inRAMVaultPaths.remove(vault.directoryPath)
        if selectedVault?.directoryPath == vault.directoryPath {
            isVaultUnlockedInUI = false
            currentSecrets = []
            currentRawEnv = ""
            originalRawEnv = ""
        }
        
        var hasUnshielded = false
        for targetFile in vault.targetFiles {
            let fileURL = URL(fileURLWithPath: vault.directoryPath).appendingPathComponent(targetFile)
            if let content = try? String(contentsOf: fileURL, encoding: .utf8),
               VaultEngine.shared.isDummyContent(content) {
                continue
            }
            hasUnshielded = true
            await lockFile(at: fileURL, force: true)
        }
        
        // Revoke active session credentials when vault is relocked
        SessionManager.shared.clearSession()
        isGraceActive = false
        remainingGraceSeconds = 0
        isAppSessionAuthenticated = false
        
        if !hasUnshielded {
            showTemporaryStatus("Vault locked & memory purged")
            playHapticFeedback()
            loadVaultsFromRegistry()
        }
    }
    
    public func restoreToDisk(vault: VaultItem) async {
        let targetFile = vault.activeFile
        let vaultURL = URL(fileURLWithPath: vault.directoryPath).appendingPathComponent(targetFile).appendingPathExtension("vault")
        
        do {
            try await VaultEngine.shared.unlockToDisk(vaultURL: vaultURL)
            showTemporaryStatus("Permanently unlocked '\(targetFile)' to disk")
            playHapticFeedback()
            
            addRadarEvent(
                agent: "Secret Manager",
                action: "Restored plaintext to disk",
                detail: "Plaintext written to '\(targetFile)' • Vault removed",
                severity: .warning
            )
            
            isVaultUnlockedInUI = false
            currentSecrets = []
            loadVaultsFromRegistry()
            loadBackupsAndTrash()
        } catch {
            showTemporaryStatus("Unlock failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Backups, Snapshots & Trash Operations
    public func loadBackupsAndTrash() {
        self.snapshots = BackupEngine.shared.listAllSnapshots()
        self.trashRecords = BackupEngine.shared.loadTrash()
    }
    
    public func createManualBackup(for vault: VaultItem) async {
        let targetFile = vault.activeFile
        let vaultURL = URL(fileURLWithPath: vault.directoryPath).appendingPathComponent(targetFile).appendingPathExtension("vault")
        do {
            let record = try await BackupEngine.shared.createSnapshot(
                for: vaultURL,
                trigger: .manual,
                note: "User manual backup in Secret Manager"
            )
            loadBackupsAndTrash()
            showTemporaryStatus("Snapshot v\(record.version) created for '\(targetFile)'")
            playHapticFeedback()
            addRadarEvent(
                agent: "Secret Manager",
                action: "Created snapshot v\(record.version)",
                detail: "Stored snapshot in ~/.sec/backups for \(targetFile)",
                severity: .success
            )
        } catch {
            showTemporaryStatus("Backup failed: \(error.localizedDescription)")
        }
    }
    
    public func backupAllVaults() async {
        isBackingUpAll = true
        defer { isBackingUpAll = false }
        do {
            let created = try await BackupEngine.shared.backupAllRegisteredVaults()
            loadBackupsAndTrash()
            showTemporaryStatus("Created snapshots for \(created.count) vault\(created.count == 1 ? "" : "s")")
            playHapticFeedback()
            addRadarEvent(
                agent: "Secret Manager",
                action: "Batch backup completed",
                detail: "Created snapshots for \(created.count) registered vaults",
                severity: .success
            )
        } catch {
            showTemporaryStatus("Batch backup failed: \(error.localizedDescription)")
        }
    }
    
    public func restoreSnapshot(_ snapshot: SnapshotRecord) async {
        do {
            let isCurrentVaultUnlocked = isVaultUnlockedInUI && (selectedVault?.directoryPath == snapshot.projectPath)
            if !isCurrentVaultUnlocked || !SessionManager.shared.isSessionActive() {
                try await BiometricAuth.shared.authenticate(
                    reason: "sec requires Touch ID to rollback to snapshot v\(snapshot.version)"
                )
                SessionManager.shared.startSession()
                self.isAppSessionAuthenticated = true
            }
            
            try await BackupEngine.shared.restoreSnapshot(snapshotId: snapshot.id)
            loadBackupsAndTrash()
            loadVaultsFromRegistry()
            
            // If currently viewing this vault, refresh unlocked secrets in memory
            if let selected = selectedVault, selected.directoryPath == snapshot.projectPath {
                await unlockVaultSecrets(for: selected)
            }
            
            showTemporaryStatus("Restored '\(snapshot.targetFileName)' to v\(snapshot.version)")
            playHapticFeedback()
            addRadarEvent(
                agent: "Secret Manager",
                action: "Rolled back to v\(snapshot.version)",
                detail: "Restored \(snapshot.targetFileName) to version from \(snapshot.relativeTime)",
                severity: .warning
            )
        } catch {
            showTemporaryStatus("Rollback cancelled or failed")
        }
    }
    
    public func deleteSnapshot(_ snapshot: SnapshotRecord) {
        do {
            try BackupEngine.shared.deleteSnapshot(snapshotId: snapshot.id)
            loadBackupsAndTrash()
            showTemporaryStatus("Deleted snapshot v\(snapshot.version)")
        } catch {
            showTemporaryStatus("Delete failed: \(error.localizedDescription)")
        }
    }
    
    public func previewSnapshot(_ snapshot: SnapshotRecord) async {
        let snapshotFile = BackupEngine.shared.snapshotFileURL(for: snapshot)
        do {
            // Security Gate: Enforce physical Touch ID if the vault is locked in UI or session expired
            let isCurrentVaultUnlocked = isVaultUnlockedInUI && (selectedVault?.directoryPath == snapshot.projectPath)
            if !isCurrentVaultUnlocked || !SessionManager.shared.isSessionActive() {
                try await BiometricAuth.shared.authenticate(
                    reason: "sec requires Touch ID to preview snapshot v\(snapshot.version)"
                )
                SessionManager.shared.startSession()
                self.isAppSessionAuthenticated = true
            }
            
            let plaintextData = try await VaultEngine.shared.readDecryptedData(
                vaultURL: snapshotFile,
                promptReason: "sec requires Touch ID to preview snapshot v\(snapshot.version)"
            )
            let plaintextString = String(data: plaintextData, encoding: .utf8) ?? ""
            self.previewSnapshotRawText = plaintextString
            let parsed = EnvParser.shared.parse(plaintextString)
            self.previewSnapshotSecrets = parsed.keys.sorted().map { k in
                SecretEntry(key: k, value: parsed[k] ?? "", isRevealed: true)
            }
            self.activePreviewSnapshot = snapshot
            self.isPreviewingSnapshot = true
        } catch {
            showTemporaryStatus("Touch ID required to preview snapshot")
        }
    }
    
    public func restoreTrashItem(_ item: TrashRecord) async {
        do {
            let isCurrentVaultUnlocked = isVaultUnlockedInUI && (selectedVault?.directoryPath == item.projectPath)
            if !isCurrentVaultUnlocked || !SessionManager.shared.isSessionActive() {
                try await BiometricAuth.shared.authenticate(
                    reason: "sec requires Touch ID to restore '\(item.targetFileName)' from Trash"
                )
                SessionManager.shared.startSession()
                self.isAppSessionAuthenticated = true
            }
            
            let restoredURL = try await BackupEngine.shared.restoreFromTrash(trashId: item.id)
            loadBackupsAndTrash()
            loadVaultsFromRegistry()
            showTemporaryStatus("Restored '\(item.targetFileName)' from Trash")
            playHapticFeedback()
            addRadarEvent(
                agent: "Secret Manager",
                action: "Restored from Trash",
                detail: "Restored vault '\(restoredURL.lastPathComponent)'",
                severity: .success
            )
        } catch {
            showTemporaryStatus("Restore cancelled or failed")
        }
    }
    
    public func purgeTrashItem(_ item: TrashRecord) {
        do {
            try BackupEngine.shared.purgeTrashItem(trashId: item.id)
            loadBackupsAndTrash()
            showTemporaryStatus("Purged '\(item.targetFileName)' from Trash")
        } catch {
            showTemporaryStatus("Purge failed: \(error.localizedDescription)")
        }
    }
    
    public func purgeAllTrash() {
        do {
            try BackupEngine.shared.purgeAllTrash()
            loadBackupsAndTrash()
            showTemporaryStatus("Emptied Trash")
        } catch {
            showTemporaryStatus("Failed to empty trash: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Runner Studio Operations
    public func startRunnerProcess() {
        guard let vault = runnerSelectedVault ?? selectedVault else {
            showTemporaryStatus("Please select a project vault first")
            return
        }
        guard !runnerCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showTemporaryStatus("Command cannot be empty")
            return
        }
        
        isProcessRunning = true
        runnerLogs.removeAll()
        
        let targetFile = vault.targetFiles.first ?? ".env"
        let vaultURL = URL(fileURLWithPath: vault.directoryPath).appendingPathComponent(targetFile).appendingPathExtension("vault")
        
        appendLog("[sec] Initializing runner for '\(vault.projectName)'...", isError: false)
        appendLog("[sec] Target Vault: \(vaultURL.lastPathComponent)", isError: false)
        
        Task {
            do {
                let secrets = try await VaultEngine.shared.readDecryptedSecrets(vaultURL: vaultURL)
                appendLog("[sec] Touch ID verified. Decrypted \(secrets.count) secrets directly into memory.", isError: false)
                appendLog("[sec] Secrets injected into the child process environment (no plaintext .env on disk).", isError: false)
                appendLog("────────────────────────────────────────────────────────", isError: false)
                
                await self.launchChildProcess(commandString: self.runnerCommand, workingDir: vault.directoryPath, secrets: secrets)
            } catch {
                appendLog("[sec] Error: \(error.localizedDescription)", isError: true)
                self.isProcessRunning = false
                self.runningPID = nil
            }
        }
    }
    
    private func launchChildProcess(commandString: String, workingDir: String, secrets: [String: String]) async {
        let process = Process()
        var env = ProcessInfo.processInfo.environment
        for (k, v) in secrets {
            env[k] = v
        }
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", commandString]
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        self.processOutPipe = outPipe
        self.processErrPipe = errPipe
        self.activeProcess = process
        
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.appendLog(text.trimmingCharacters(in: .newlines), isError: false)
            }
        }
        
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.appendLog(text.trimmingCharacters(in: .newlines), isError: true)
            }
        }
        
        do {
            try process.run()
            self.runningPID = process.processIdentifier
            appendLog("[sec] Process launched with PID: \(process.processIdentifier)", isError: false)
            
            // Mark vault as inRAM
            if let idx = vaults.firstIndex(where: { $0.directoryPath == workingDir }) {
                vaults[idx].status = .inRAM
            }
            
            addRadarEvent(
                agent: "Runner Studio",
                action: "Running '\(commandString)'",
                detail: "PID \(process.processIdentifier) • Direct memory injection",
                severity: .success
            )
            
            process.terminationHandler = { [weak self] proc in
                DispatchQueue.main.async { [weak self] in
                    self?.isProcessRunning = false
                    self?.runningPID = nil
                    self?.appendLog("────────────────────────────────────────────────────────", isError: false)
                    self?.appendLog("[sec] Process terminated with exit code \(proc.terminationStatus)", isError: proc.terminationStatus != 0)
                    
                    if let idx = self?.vaults.firstIndex(where: { $0.directoryPath == workingDir }) {
                        self?.vaults[idx].status = .protectedWithDecoy
                    }
                }
            }
        } catch {
            appendLog("[sec] Failed to launch process: \(error.localizedDescription)", isError: true)
            isProcessRunning = false
            runningPID = nil
        }
    }
    
    public func stopRunnerProcess() {
        guard let proc = activeProcess, proc.isRunning else { return }
        appendLog("[sec] Sending termination signal to PID \(proc.processIdentifier)...", isError: true)
        proc.terminate()
        isProcessRunning = false
        runningPID = nil
        showTemporaryStatus("Process stopped")
    }
    
    public func clearRunnerLogs() {
        runnerLogs.removeAll()
    }
    
    private func appendLog(_ text: String, isError: Bool) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let entry = RunnerLogEntry(text: String(line), isError: isError)
            runnerLogs.append(entry)
        }
        if runnerLogs.count > 1000 {
            runnerLogs.removeFirst(runnerLogs.count - 1000)
        }
    }
    
    // MARK: - Deep Scanner & Pruning
    public func runDeepScanner() async {
        isScanning = true
        discoveredFiles.removeAll()
        defer { isScanning = false }
        
        let rootURL = URL(fileURLWithPath: scanDirectoryPath)
        let fm = FileManager.default
        
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            showTemporaryStatus("Could not open directory")
            return
        }
        
        let skipDirs: Set<String> = [
            ".sec", "backups", "trash", "Library", ".Trash", ".cache", "node_modules", ".git", ".build",
            "DerivedData", "Pods", ".npm", ".yarn", ".cargo", ".rustup",
            ".gradle", "venv", ".venv", "env", "dist", ".next"
        ]
        
        var results: [DiscoveredSecretFile] = []
        var count = 0
        
        while let url = enumerator.nextObject() as? URL {
            count += 1
            if count > 8000 { break } // safety limit for responsiveness
            
            let name = url.lastPathComponent
            if let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory, isDir {
                if skipDirs.contains(name) || name == ".sec" {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            // Check if secret target or vault
            let isSecretTarget = name == ".env" || name.hasPrefix(".env.") || name == "secrets.json"
            let isVault = name.hasSuffix(".vault") && !name.hasSuffix(".vault.bak")
            
            if isSecretTarget || isVault {
                let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
                if resolvedURL.path.contains("/.sec/") {
                    continue
                }
                let vaultURL = isVault ? resolvedURL : VaultEngine.shared.vaultURL(for: resolvedURL)
                let plainURL = isVault ? VaultEngine.shared.plainFileURL(for: resolvedURL) : resolvedURL
                
                let vaultExists = fm.fileExists(atPath: vaultURL.path)
                let plainExists = fm.fileExists(atPath: plainURL.path)
                
                var hasDecoy = false
                if plainExists, let content = try? String(contentsOf: plainURL, encoding: .utf8) {
                    hasDecoy = VaultEngine.shared.isDummyContent(content)
                }
                
                let isLocked = vaultExists && hasDecoy
                let size = (try? plainURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let mod = (try? plainURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                
                let item = DiscoveredSecretFile(
                    url: plainURL,
                    path: plainURL.path,
                    filename: plainURL.lastPathComponent,
                    isLocked: isLocked,
                    hasDecoy: hasDecoy,
                    sizeBytes: Int64(size),
                    modifiedDate: mod
                )
                
                if !results.contains(where: { $0.path == item.path }) {
                    results.append(item)
                }
            }
        }
        
        self.discoveredFiles = results
        showTemporaryStatus("Scan found \(results.count) secret files")
        playHapticFeedback()
    }
    
    public func lockDiscoveredFile(_ item: DiscoveredSecretFile) async {
        await lockFile(at: item.url, force: false)
        await runDeepScanner()
    }
    
    public func pruneRegistry() {
        let (removed, _) = RegistryManager.shared.prune()
        loadVaultsFromRegistry()
        if removed > 0 {
            if let sel = selectedVault, !FileManager.default.fileExists(atPath: sel.directoryPath) || !vaults.contains(where: { $0.id == sel.id }) {
                selectedVault = vaults.first
                currentSecrets = []
                currentRawEnv = ""
                isVaultUnlockedInUI = false
            }
            showTemporaryStatus("Pruned \(removed) deleted/moved vault\(removed == 1 ? "" : "s")")
            playHapticFeedback()
            addRadarEvent(
                agent: "Finder Sync",
                action: "Synced Finder deletion",
                detail: "Cleaned up \(removed) deleted vault\(removed == 1 ? "" : "s") & refreshed cache",
                severity: .shielded
            )
        }
    }
    
    // MARK: - Finder Quick Actions
    public func checkFinderStatus() {
        self.isFinderActionsInstalled = FinderInstaller.shared.isInstalled()
    }
    
    public func toggleFinderActions() {
        do {
            if isFinderActionsInstalled {
                try FinderInstaller.shared.uninstall()
                isFinderActionsInstalled = false
                showTemporaryStatus("Removed Finder Quick Actions")
            } else {
                try FinderInstaller.shared.install()
                isFinderActionsInstalled = true
                showTemporaryStatus("Installed Finder Quick Actions")
            }
            playHapticFeedback()
        } catch {
            showTemporaryStatus("Action failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Actions & Helpers
    /// `stopRunner: false` keeps an already-running dev server alive (it holds its own copy of the
    /// secrets), while still dropping the session and every decrypted value held by the app.
    public func lockAll(stopRunner: Bool = true) {
        isGraceActive = false
        remainingGraceSeconds = 0
        isAppSessionAuthenticated = false
        isVaultUnlockedInUI = false
        currentSecrets = []
        currentRawEnv = ""
        originalRawEnv = ""
        inRAMVaultPaths.removeAll()
        
        SessionManager.shared.clearSession()
        
        // Stop any running child process
        if stopRunner {
            stopRunnerProcess()
        }
        
        // Mark all active RAM items back to protectedWithDecoy
        for i in 0..<vaults.count {
            if vaults[i].status == .inRAM {
                vaults[i].status = .protectedWithDecoy
            }
        }
        
        addRadarEvent(
            agent: "sec Master Lock",
            action: "All sessions revoked & caches wiped",
            detail: "Touch ID required for all commands",
            severity: .warning
        )
        
        playHapticFeedback()
        refreshMemoryUsage()
        showTemporaryStatus("All vaults locked")
    }
    
    public func selectGracePeriod(_ option: GracePeriodOption) {
        selectedGraceOption = option
        let duration: Double
        if let sec = option.durationSeconds, sec > 0 {
            duration = Double(sec)
        } else if option == .untilSleep {
            duration = 24 * 3600
        } else {
            duration = 0
        }
        SessionManager.shared.setSessionDuration(seconds: duration)
        
        if duration > 0 {
            if isAppSessionAuthenticated {
                SessionManager.shared.startSession(duration: duration)
                remainingGraceSeconds = Int(duration)
                isGraceActive = true
                showTemporaryStatus("Session timer updated to \(option.rawValue)")
            } else {
                showTemporaryStatus("Auto-lock set to \(option.rawValue) (starts upon unlock)")
            }
        } else {
            lockAll()
            showTemporaryStatus("Strict mode: Touch ID required per action")
        }
        playHapticFeedback()
    }
    
    // MARK: - Dynamic Font Scaling Actions
    public func increaseFontSize() {
        let target = min(Self.maxFontScale, fontScale + Self.fontScaleStep)
        let rounded = (target * 10).rounded() / 10
        guard rounded != fontScale else { return }
        fontScale = rounded
        let percentage = Int(round(fontScale * 100))
        showTemporaryStatus("Font Size: \(percentage)%")
        playHapticFeedback()
    }
    
    public func decreaseFontSize() {
        let target = max(Self.minFontScale, fontScale - Self.fontScaleStep)
        let rounded = (target * 10).rounded() / 10
        guard rounded != fontScale else { return }
        fontScale = rounded
        let percentage = Int(round(fontScale * 100))
        showTemporaryStatus("Font Size: \(percentage)%")
        playHapticFeedback()
    }
    
    public func resetFontSize() {
        guard fontScale != Self.defaultFontScale else {
            showTemporaryStatus("Font Size: 100% (Default)")
            return
        }
        fontScale = Self.defaultFontScale
        showTemporaryStatus("Font Size: 100% (Default)")
        playHapticFeedback()
    }
    
    public func revealInFinder(vault: VaultItem) {
        let url = URL(fileURLWithPath: vault.directoryPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
    
    public func openInTerminal(vault: VaultItem) {
        let url = URL(fileURLWithPath: vault.directoryPath)
        let config = NSWorkspace.OpenConfiguration()
        if let termURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.open([url], withApplicationAt: termURL, configuration: config, completionHandler: nil)
        }
    }
    
    public func editWithExternalEditor(vault: VaultItem) {
        addRadarEvent(
            agent: "External Editor",
            action: "Opened temporary edit buffer",
            detail: "Target: \(vault.targetFiles.joined(separator: ", ")) in \(vault.projectName)",
            severity: .shielded
        )
        showTemporaryStatus("Opening secure buffer in $EDITOR...")
        
        let targetFile = vault.activeFile
        let vaultURL = URL(fileURLWithPath: vault.directoryPath).appendingPathComponent(targetFile).appendingPathExtension("vault")
        Task {
            try? await EditorEngine.shared.edit(vaultURL: vaultURL)
            await self.unlockVaultSecrets(for: vault)
        }
    }
    
    // MARK: - Incoming Drag-and-Drop File Handling
    public func handleIncomingFile(url: URL) {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDir) else {
            showTemporaryStatus("File does not exist")
            return
        }
        
        if isDir.boolValue {
            // Check for secret files inside the dropped folder
            let commonFiles = [".env", ".env.local", ".env.production", ".env.development", "secrets.json", "credentials.env"]
            var candidateFile: URL? = nil
            for name in commonFiles {
                let candidate = standardized.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    candidateFile = candidate
                    break
                }
            }
            
            if let target = candidateFile {
                if VaultEngine.shared.isAlreadyLocked(fileURL: target) {
                    showTemporaryStatus("'\(target.lastPathComponent)' in folder is already encrypted")
                    loadVaultsFromRegistry()
                    if let matched = vaults.first(where: { $0.directoryPath == standardized.path }) {
                        selectedVault = matched
                        selectedTab = .allVaults
                    }
                    return
                }
                self.pendingEncryptionURL = target
                self.showEncryptConfirmation = true
            } else {
                showTemporaryStatus("No secret file (.env) found in dropped folder")
            }
        } else {
            // Single file dropped
            if standardized.pathExtension == "vault" {
                let plainURL = VaultEngine.shared.plainFileURL(for: standardized)
                RegistryManager.shared.register(vaultURL: standardized, plainURL: plainURL)
                loadVaultsFromRegistry()
                let dir = standardized.deletingLastPathComponent().path
                if let matched = vaults.first(where: { $0.directoryPath == dir }) {
                    selectedVault = matched
                    selectedTab = .allVaults
                }
                showTemporaryStatus("Registered vault '\(standardized.lastPathComponent)'")
                return
            }
            
            if VaultEngine.shared.isAlreadyLocked(fileURL: standardized) {
                showTemporaryStatus("'\(standardized.lastPathComponent)' is already encrypted and protected")
                loadVaultsFromRegistry()
                let dir = standardized.deletingLastPathComponent().path
                if let matched = vaults.first(where: { $0.directoryPath == dir }) {
                    selectedVault = matched
                    selectedTab = .allVaults
                }
                return
            }
            
            self.pendingEncryptionURL = standardized
            self.showEncryptConfirmation = true
        }
    }
    
    public func confirmAndEncrypt(fileURL: URL) async {
        let fileName = fileURL.lastPathComponent
        let projectDir = fileURL.deletingLastPathComponent().path
        
        await lockFile(at: fileURL, force: false)
        
        // Switch to All Vaults and select the newly encrypted project
        selectedTab = .allVaults
        loadVaultsFromRegistry()
        
        if let newlyAdded = vaults.first(where: { $0.directoryPath == projectDir }) {
            selectedVault = newlyAdded
            await selectActiveFile(fileName, for: newlyAdded)
        }
        
        pendingEncryptionURL = nil
        showEncryptConfirmation = false
        showTemporaryStatus("Encrypted & added '\(fileName)' to All Vaults")
    }
    
    public func addDirectory(at url: URL) {
        handleIncomingFile(url: url)
    }
    
    public func clearRadarEvents() {
        radarEvents.removeAll()
        showTemporaryStatus("Activity log cleared")
    }
    
    public func addRadarEvent(agent: String, action: String, detail: String, severity: EventSeverity) {
        let event = RadarEvent(
            agentName: agent,
            action: action,
            detail: detail,
            timestamp: Date(),
            severity: severity
        )
        radarEvents.insert(event, at: 0)
        if radarEvents.count > 40 {
            radarEvents.removeLast()
        }
    }
    
    private var memoryTimerCounter: Int = 0
    
    private func startGraceCountdownTimer() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.memoryTimerCounter += 1
                if self.memoryTimerCounter % 3 == 0 {
                    self.refreshMemoryUsage()
                }
                if self.isGraceActive && self.remainingGraceSeconds > 0 {
                    self.remainingGraceSeconds -= 1
                    if self.remainingGraceSeconds == 0 {
                        self.lockAll()
                        self.showTemporaryStatus("Session expired. All vaults locked.")
                    }
                }
            }
    }
    
    private func setupSleepObserver() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.lockAll()
            }
        }
        
        // Also lock when the screen locks or another user takes over the session:
        // an unlocked vault must not outlive the user's presence at the Mac.
        // A running dev server is left alone so locking the screen does not kill it.
        let lockHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lockAll(stopRunner: false)
            }
        }
        lockObservers = [
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: lockHandler
            ),
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: lockHandler
            )
        ]
    }
    
    private func playHapticFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
    
    public func showTemporaryStatus(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.statusMessage == message {
                self?.statusMessage = nil
            }
        }
    }
}
