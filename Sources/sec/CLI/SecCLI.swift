import Foundation
import SecCore

public struct SecCLI {
    public static func run(args: [String]) async {
        let arguments = Array(args.dropFirst()) // drop executable path
        
        guard let firstArg = arguments.first else {
            printHelp()
            return
        }
        
        switch firstArg {
        case "lock":
            var target = ".env"
            var force = false
            for arg in arguments.dropFirst() {
                if arg == "--force" || arg == "-f" {
                    force = true
                } else if !arg.hasPrefix("-") {
                    target = arg
                }
            }
            await handleLock(target: target, force: force)
            
        case "run":
            let cmd = Array(arguments.dropFirst())
            await handleRun(command: cmd)
            
        case "edit":
            let target = arguments.count > 1 ? arguments[1] : ".env"
            await handleEdit(target: target)
            
        case "view", "show":
            var target = ".env"
            var forceStdout = false
            for arg in arguments.dropFirst() {
                if arg == "--force-stdout" {
                    forceStdout = true
                } else if !arg.hasPrefix("-") {
                    target = arg
                }
            }
            await handleView(target: target, forceStdout: forceStdout)
            
        case "unlock":
            var target = ".env"
            var force = false
            for arg in arguments.dropFirst() {
                if arg == "--yes" || arg == "-y" || arg == "--force" || arg == "-f" {
                    force = true
                } else if !arg.hasPrefix("-") {
                    target = arg
                }
            }
            await handleUnlock(target: target, force: force)
            
        case "status":
            handleStatus()
            
        case "list", "ls":
            await handleList(arguments: Array(arguments.dropFirst()))
            
        case "scan", "find":
            await handleScan(arguments: Array(arguments.dropFirst()))
            
        case "session":
            let sub = arguments.count > 1 ? arguments[1] : "status"
            handleSession(subcommand: sub)
            
        case "logout":
            SessionManager.shared.clearSession()
            print("🔒 Session cleared. Touch ID will be required on next operation.")
            
        case "install-finder":
            handleInstallFinder()
            
        case "export-key", "backup-key":
            await handleExportKey()
            
        case "import-key", "restore-key":
            let keyArg = arguments.count > 1 ? arguments[1] : ""
            await handleImportKey(key: keyArg)
            
        case "backup":
            await handleBackup(arguments: Array(arguments.dropFirst()))
            
        case "restore":
            await handleRestore(arguments: Array(arguments.dropFirst()))
            
        case "trash":
            await handleTrash(arguments: Array(arguments.dropFirst()))
            
        case "--help", "-h", "help":
            printHelp()
            
        case "--version", "-v", "version":
            print("sec version 1.0.0 (macOS Touch ID Secrets Vault)")
            
        default:
            // Treat unknown first command as shorthand for `sec run <command...>`
            await handleRun(command: arguments)
        }
    }
    
    // MARK: - Handlers
    
    private static func resolveURL(for pathOrName: String) -> URL {
        if pathOrName.hasPrefix("/") {
            return URL(fileURLWithPath: pathOrName).standardizedFileURL
        } else if pathOrName.hasPrefix("~") {
            let expanded = NSString(string: pathOrName).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        } else {
            let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            return currentDir.appendingPathComponent(pathOrName).standardizedFileURL
        }
    }
    
    private static func handleLock(target: String, force: Bool) async {
        let fileURL = resolveURL(for: target)
        let fileName = fileURL.lastPathComponent
        
        // If not forcing, check if file is already locked beforehand to avoid redundant Touch ID prompts
        if !force {
            let vault = VaultEngine.shared.vaultURL(for: fileURL)
            let isVault = fileURL.pathExtension == "vault"
            let vaultExists = FileManager.default.fileExists(atPath: vault.path)
            let isDummy = (try? String(contentsOf: fileURL, encoding: .utf8)).map { VaultEngine.shared.isDummyContent($0) } ?? false
            
            if isVault || vaultExists || isDummy {
                let actualVaultName = isVault ? fileName : vault.lastPathComponent
                let plainName = isVault ? VaultEngine.shared.plainFileURL(for: fileURL).lastPathComponent : fileName
                print("ℹ️ '\(fileName)' is already locked and protected by sec.")
                print("   📁 Vault: \(actualVaultName)")
                print("   💡 Edit secrets:   sec edit \(plainName)")
                print("   💡 Unlock to disk: sec unlock \(plainName)")
                print("   (To force re-lock with current file contents, run: sec lock --force \(fileName))")
                
                Notifier.shared.notify(
                    title: "sec: Already Locked",
                    message: "'\(fileName)' is already protected. Use 'Edit Secrets' to make changes."
                )
                return
            }
        }
        
        do {
            print("🔒 Locking '\(fileName)' with Touch ID...")
            let keys = try await VaultEngine.shared.lock(fileURL: fileURL, force: force)
            print("✅ Successfully locked '\(fileName)'!")
            print("   📁 Encrypted vault: \(fileName).vault (AES-256-GCM)")
            print("   🎭 Masked placeholder: \(fileName) (dummy values for AI agents)")
            if keys.count == 1 && keys.first == fileName {
                print("   🛡️  Shielded all secret content in '\(fileName)' from AI agents")
                Notifier.shared.notify(title: "sec: File Locked", message: "Shielded '\(fileName)' from AI agents.")
            } else {
                print("   🛡️  Shielded \(keys.count) key\(keys.count == 1 ? "" : "s"): \(keys.joined(separator: ", "))")
                Notifier.shared.notify(title: "sec: File Locked", message: "Shielded \(keys.count) secrets in '\(fileName)' from AI agents.")
            }
        } catch VaultError.alreadyLocked(let name) {
            print("ℹ️ '\(name)' is already locked and protected by sec.")
            print("   (To force re-lock with current file contents, run: sec lock --force \(name))")
            Notifier.shared.notify(title: "sec: Already Locked", message: "'\(name)' is already protected.")
        } catch VaultError.cannotLockDecoyFile(let name) {
            print("❌ Cannot lock '\(name)': The file contains dummy decoy placeholder text.")
            print("   Re-locking this file would destroy your real encrypted secrets.")
            print("   💡 Edit secrets:   sec edit \(name)")
            print("   💡 Unlock to disk: sec unlock \(name)")
            Notifier.shared.notify(title: "sec: Lock Aborted", message: "'\(name)' contains decoy content. Real secrets preserved.")
            exit(1)
        } catch {
            print("❌ Error locking file: \(error.localizedDescription)")
            Notifier.shared.notify(title: "sec: Lock Failed", message: error.localizedDescription)
            exit(1)
        }
    }
    
    private static func handleRun(command: [String]) async {
        var remainingArgs = command
        var targetVault: URL? = nil
        
        // Check for -f <file>, --file <file>, or --vault <file> flags
        if remainingArgs.count >= 2 && (remainingArgs[0] == "-f" || remainingArgs[0] == "--file" || remainingArgs[0] == "--vault") {
            let targetFile = remainingArgs[1]
            remainingArgs = Array(remainingArgs.dropFirst(2))
            
            var resolved = resolveURL(for: targetFile)
            if !resolved.pathExtension.isEmpty && resolved.pathExtension != "vault" {
                resolved = VaultEngine.shared.vaultURL(for: resolved)
            } else if resolved.pathExtension.isEmpty {
                resolved = resolved.appendingPathExtension("vault")
            }
            targetVault = resolved
        }
        
        guard !remainingArgs.isEmpty else {
            print("Error: No command specified to run.")
            print("Usage: sec [-f <file>] <command...> (e.g. sec npm run dev, sec -f .env.local npm start)")
            exit(1)
        }
        
        do {
            let exitCode = try await ProcessRunner.shared.run(command: remainingArgs, vaultURL: targetVault)
            exit(exitCode)
        } catch {
            print("❌ Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    private static func handleEdit(target: String) async {
        var vaultURL = resolveURL(for: target)
        if !vaultURL.pathExtension.isEmpty && vaultURL.pathExtension != "vault" {
            vaultURL = VaultEngine.shared.vaultURL(for: vaultURL)
        } else if vaultURL.pathExtension.isEmpty {
            vaultURL = vaultURL.appendingPathExtension("vault")
        }
        
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            print("❌ Vault not found: '\(vaultURL.lastPathComponent)'")
            print("   Did you lock the file first with 'sec lock \(target)'?")
            Notifier.shared.notify(title: "sec: Edit Failed", message: "Vault not found: '\(vaultURL.lastPathComponent)'")
            exit(1)
        }
        
        do {
            try await EditorEngine.shared.edit(vaultURL: vaultURL)
        } catch {
            print("❌ Error editing vault: \(error.localizedDescription)")
            Notifier.shared.notify(title: "sec: Edit Failed", message: error.localizedDescription)
            exit(1)
        }
    }
    
    private static func handleView(target: String, forceStdout: Bool = false) async {
        // Refuse when stdout is piped or captured (e.g. by an AI agent's shell tool), so plaintext
        // only reaches a human-visible terminal unless the caller explicitly opts in.
        guard forceStdout || isatty(STDOUT_FILENO) != 0 else {
            FileHandle.standardError.write("❌ Refusing to print secrets: stdout is not a terminal. Pass --force-stdout to override.\n".data(using: .utf8)!)
            exit(1)
        }
        
        var vaultURL = resolveURL(for: target)
        if !vaultURL.pathExtension.isEmpty && vaultURL.pathExtension != "vault" {
            vaultURL = VaultEngine.shared.vaultURL(for: vaultURL)
        } else if vaultURL.pathExtension.isEmpty {
            vaultURL = vaultURL.appendingPathExtension("vault")
        }
        
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            print("❌ Vault not found: '\(vaultURL.lastPathComponent)'")
            exit(1)
        }
        
        do {
            let plaintextData = try await VaultEngine.shared.readDecryptedData(vaultURL: vaultURL, promptReason: "sec requires Touch ID to view '\(vaultURL.lastPathComponent)'")
            guard let plaintextString = String(data: plaintextData, encoding: .utf8) else {
                throw VaultError.invalidFileEncoding
            }
            
            let plainFile = VaultEngine.shared.plainFileURL(for: vaultURL)
            let trimmed = plaintextString.trimmingCharacters(in: .whitespacesAndNewlines)
            let isJSON = plainFile.pathExtension.lowercased() == "json" ||
                         ((trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
                          (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")))
            
            print("🔓 Decrypted content of '\(vaultURL.lastPathComponent)':")
            print("--------------------------------------------------")
            if isJSON,
               let data = trimmed.data(using: .utf8),
               let jsonObj = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print(prettyString)
            } else {
                print(trimmed)
            }
            print("--------------------------------------------------")
        } catch {
            print("❌ Error viewing vault: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    private static func handleUnlock(target: String, force: Bool = false) async {
        var vaultURL = resolveURL(for: target)
        if !vaultURL.pathExtension.isEmpty && vaultURL.pathExtension != "vault" {
            vaultURL = VaultEngine.shared.vaultURL(for: vaultURL)
        } else if vaultURL.pathExtension.isEmpty {
            vaultURL = vaultURL.appendingPathExtension("vault")
        }
        
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            print("❌ Vault not found: '\(vaultURL.lastPathComponent)'")
            Notifier.shared.notify(title: "sec: Unlock Failed", message: "Vault not found: '\(vaultURL.lastPathComponent)'")
            exit(1)
        }
        
        let plainFile = VaultEngine.shared.plainFileURL(for: vaultURL)
        if !force {
            print("⚠️  WARNING: Unlocking will restore plaintext secrets to disk at '\(plainFile.lastPathComponent)'.")
            print("   AI agents and background tools will be able to read them.")
            print("Are you sure? (y/N): ", terminator: "")
            
            guard let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  answer == "y" || answer == "yes" else {
                print("Cancelled.")
                return
            }
        }
        
        do {
            try await VaultEngine.shared.unlockToDisk(vaultURL: vaultURL)
            print("🔓 Plaintext restored to '\(plainFile.lastPathComponent)'. Vault removed.")
            Notifier.shared.notify(
                title: "sec: File Unlocked",
                message: "Plaintext restored to '\(plainFile.lastPathComponent)'. Vault removed."
            )
        } catch {
            print("❌ Error unlocking file: \(error.localizedDescription)")
            Notifier.shared.notify(title: "sec: Unlock Failed", message: error.localizedDescription)
            exit(1)
        }
    }
    
    private static func handleStatus() {
        print("=== sec Status ===")
        let hasKey = KeychainManager.shared.hasMasterKey()
        print("🔑 Hardware Master Key: \(hasKey ? "✅ Configured (Apple Silicon Secure Enclave)" : "⏳ Not yet created (will initialize on first lock)")")
        
        if SessionManager.shared.isZeroCacheMode {
            print("🛡️  Access Policy:       🔒 Strict Zero-Cache (Single-Use)")
            print("                       (Every command requires Touch ID; no lingering cache for AI agents)")
        } else if SessionManager.shared.isSessionActive(), let remaining = SessionManager.shared.remainingTimeDescription() {
            print("⏱️  Session Cache:       ✅ Active (\(remaining) remaining)")
        } else {
            print("⏱️  Session Cache:       🔒 Locked (Touch ID required)")
        }
        
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let vaultFound = VaultEngine.shared.findNearestVault(startingAt: currentDir)
        if let v = vaultFound {
            print("📁 Current Vault:       Found '\(v.lastPathComponent)' at \(v.deletingLastPathComponent().path)")
        } else {
            print("📁 Current Vault:       None detected in current or parent directories")
        }
        
        let registry = RegistryManager.shared.loadRegistry()
        print("📋 Global Vaults:       \(registry.records.count) registered across Mac (run 'sec list' to view)")
    }
    
    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private static func handleScan(arguments: [String]) async {
        var args = arguments
        args.insert("--scan", at: 0)
        await handleList(arguments: args)
    }
    
    private static func handleList(arguments: [String]) async {
        var shouldScan = false
        var shouldPrune = false
        var isJSON = false
        var scanDir: URL? = nil
        
        var iter = arguments.makeIterator()
        while let arg = iter.next() {
            if arg == "--scan" || arg == "-s" {
                shouldScan = true
                if let next = iter.next() {
                    if !next.hasPrefix("-") {
                        scanDir = resolveURL(for: next)
                    }
                }
            } else if arg == "--prune" || arg == "-p" {
                shouldPrune = true
            } else if arg == "--json" {
                isJSON = true
            } else if !arg.hasPrefix("-") && scanDir == nil {
                scanDir = resolveURL(for: arg)
                shouldScan = true
            }
        }
        
        if shouldPrune {
            let (removed, _) = RegistryManager.shared.prune()
            if !isJSON && removed > 0 {
                print("🧹 Pruned \(removed) missing vault\(removed == 1 ? "" : "s") from registry.")
            }
        }
        
        if shouldScan {
            let targetDir = scanDir ?? FileManager.default.homeDirectoryForCurrentUser
            if !isJSON {
                let displayPath = targetDir.path == FileManager.default.homeDirectoryForCurrentUser.path ? "~" : targetDir.path
                print("🔍 Scanning for vaults in \(displayPath)...")
            }
            let discovered = RegistryManager.shared.scan(directory: targetDir)
            if !isJSON {
                print("✨ Discovered \(discovered.count) vault\(discovered.count == 1 ? "" : "s").\n")
            }
        }
        
        let registry = RegistryManager.shared.loadRegistry()
        let records = registry.records
        
        if isJSON {
            let statusList = records.map { RegistryManager.shared.inspectVault(record: $0) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(statusList), let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            return
        }
        
        print("=== 🔒 Protected Vaults Across Your Mac ===")
        if records.isEmpty {
            print("No vaults currently registered.")
            print("")
            print("💡 Tip: To search and index all vaults across your Mac, run:")
            print("   sec list --scan")
            return
        }
        
        var byDirectory: [String: [VaultRecord]] = [:]
        for r in records {
            let dir = URL(fileURLWithPath: r.vaultPath).deletingLastPathComponent().path
            byDirectory[dir, default: []].append(r)
        }
        
        let sortedDirs = byDirectory.keys.sorted()
        for dir in sortedDirs {
            let shortDir: String
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            if dir.hasPrefix(homePath) {
                shortDir = "~" + dir.dropFirst(homePath.count)
            } else {
                shortDir = dir
            }
            
            print("\n📁 \(shortDir)")
            let items = byDirectory[dir]!.sorted(by: { $0.vaultPath < $1.vaultPath })
            for item in items {
                let info = RegistryManager.shared.inspectVault(record: item)
                print("   • Target:    \(info.plainName)")
                let sizeStr = info.vaultSizeBytes != nil ? " (\(formatBytes(info.vaultSizeBytes!)))" : ""
                print("   • Vault:     \(info.vaultName)\(sizeStr)")
                print("   • Status:    \(info.statusDescription)")
                if let mod = info.lastModified {
                    print("   • Modified:  \(mod)")
                }
            }
        }
        
        print("\n--------------------------------------------------")
        print("Total: \(records.count) vault\(records.count == 1 ? "" : "s") registered across your Mac.")
        print("💡 Tips:")
        print("   • Discover unindexed vaults:  sec list --scan [directory]")
        print("   • Clean up removed vaults:    sec list --prune")
    }
    
    private static func handleSession(subcommand: String) {
        if SessionManager.shared.isZeroCacheMode {
            print("🛡️  Zero-Cache Mode is ACTIVE (Default).")
            print("   Every command requires a fresh Touch ID tap to prevent AI agents from accessing secrets.")
            print("   No session tokens or decrypted keys are cached on disk.")
            return
        }
        
        switch subcommand {
        case "clear", "kill", "rm":
            SessionManager.shared.clearSession()
            print("🔒 Session cache cleared. Touch ID will be required on next command.")
        case "status":
            if SessionManager.shared.isSessionActive(), let remaining = SessionManager.shared.remainingTimeDescription() {
                print("⏱️  Session is active: \(remaining) remaining before re-lock.")
            } else {
                print("🔒 Session is inactive. Touch ID required.")
            }
        default:
            print("Usage: sec session [status|clear]")
        }
    }
    
    private static func handleInstallFinder() {
        print("⚙️  Installing macOS Finder Quick Actions...")
        do {
            try FinderInstaller.shared.install()
            print("✅ Finder Quick Actions successfully installed!")
            print("   Right-click any file in Finder -> Quick Actions / Services:")
            print("     • 'Lock Secrets with Touch ID (sec)'")
            print("     • 'Unlock Secrets with Touch ID (sec)'")
            print("     • 'Edit Secrets with Touch ID (sec)'")
            print("     • 'View Secrets with Touch ID (sec)'")
        } catch {
            print("❌ Failed to install Finder Quick Actions: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    private static func handleExportKey() async {
        // Refuse when stdout is piped or captured (e.g. by an AI agent's shell tool),
        // so the key only ever reaches a human-visible terminal.
        guard isatty(STDOUT_FILENO) != 0 else {
            FileHandle.standardError.write("❌ Refusing to print the master key: stdout is not a terminal.\n".data(using: .utf8)!)
            exit(1)
        }
        do {
            // Always prompt, even if a grace-period session is active.
            try await BiometricAuth.shared.authenticate(reason: "export the sec master recovery key (grants access to ALL vaults)")
            let keyString = try KeychainManager.shared.exportRecoveryKey()
            print("🔑 === sec Master Recovery Key ===")
            print("Keep this key private and secure! You can use it to restore your vaults")
            print("if you migrate to a new Mac or reinstall macOS:\n")
            print(keyString)
            print("\nTo restore on another Mac, run:")
            print("   sec import-key <key>")
        } catch {
            print("❌ Failed to export recovery key: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    private static func handleImportKey(key: String) async {
        var keyToImport = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyToImport.isEmpty {
            print("Enter master recovery key: ", terminator: "")
            guard let entered = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !entered.isEmpty else {
                print("❌ No key entered. Aborting.")
                exit(1)
            }
            keyToImport = entered
        }
        
        do {
            // Always prompt: the imported key encrypts every future vault, so a background
            // process must not be able to install one. Cancelling aborts with nothing changed.
            try await BiometricAuth.shared.authenticate(reason: "import a sec master recovery key (used to encrypt ALL vaults)")
            try KeychainManager.shared.importRecoveryKey(base64String: keyToImport)
            print("✅ Master recovery key successfully imported!")
            print("   Your existing vaults can now be decrypted on this Mac.")
        } catch {
            print("❌ Failed to import recovery key: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func handleBackup(arguments: [String]) async {
        if arguments.contains("--all") {
            print("📦 Creating backup snapshots for all registered vaults...")
            do {
                let snaps = try await BackupEngine.shared.backupAllRegisteredVaults()
                print("✅ Successfully backed up \(snaps.count) vault\(snaps.count == 1 ? "" : "s"):")
                for s in snaps {
                    print("   • \(s.projectName)/\(s.targetFileName) -> v\(s.version) (\(s.keyCount) keys)")
                }
            } catch {
                print("❌ Backup failed: \(error.localizedDescription)")
                exit(1)
            }
            return
        }
        
        if arguments.contains("--list") {
            let snapshots = BackupEngine.shared.listAllSnapshots()
            if snapshots.isEmpty {
                print("No backup snapshots found.")
                return
            }
            print("=== sec Backup Snapshots (\(snapshots.count)) ===")
            print(String(format: "%-10@ %-16@ %-16@ %-12@ %-8@ %@", "ID", "PROJECT", "FILE", "VERSION", "KEYS", "DATE"))
            print(String(repeating: "-", count: 74))
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            for s in snapshots {
                let idPrefix = String(s.id.uuidString.prefix(8))
                let dateStr = df.string(from: s.timestamp)
                print(String(format: "%-10@ %-16@ %-16@ v%-11d %-8d %@", idPrefix, s.projectName, s.targetFileName, s.version, s.keyCount, dateStr))
            }
            return
        }
        
        let target = arguments.first { !$0.hasPrefix("-") } ?? ".env"
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let vaultURL = VaultEngine.shared.findNearestVault(startingAt: currentDir, targetName: "\(target).vault") ??
                             VaultEngine.shared.findNearestVault(startingAt: currentDir, targetName: target) else {
            print("❌ Vault file not found for '\(target)'")
            exit(1)
        }
        
        do {
            let record = try await BackupEngine.shared.createSnapshot(for: vaultURL, trigger: .manual, note: "CLI manual backup")
            print("✅ Snapshot v\(record.version) created for '\(record.targetFileName)' (Snapshot ID: \(record.id.uuidString.prefix(8)))")
            print("   Location: ~/.sec/backups/\(record.projectHash)/\(record.snapshotFileName)")
        } catch {
            print("❌ Backup failed: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    private static func handleRestore(arguments: [String]) async {
        if arguments.contains("--list") {
            await handleBackup(arguments: ["--list"])
            return
        }
        
        let snapshots = BackupEngine.shared.listAllSnapshots()
        if snapshots.isEmpty {
            print("❌ No backup snapshots available to restore.")
            exit(1)
        }
        
        // Check for specific version ID or prefix
        var snapshotIdMatch: SnapshotRecord? = nil
        if let versionIdx = arguments.firstIndex(of: "--version") ?? arguments.firstIndex(of: "-v"),
           versionIdx + 1 < arguments.count {
            let query = arguments[versionIdx + 1]
            snapshotIdMatch = snapshots.first {
                $0.id.uuidString.lowercased().hasPrefix(query.lowercased()) ||
                "v\($0.version)".lowercased() == query.lowercased() ||
                String($0.version) == query
            }
        }
        
        let targetArg = arguments.first { !$0.hasPrefix("-") }
        
        let chosen: SnapshotRecord
        if let m = snapshotIdMatch {
            chosen = m
        } else if let t = targetArg {
            // Find most recent snapshot matching filename
            let clean = t.replacingOccurrences(of: ".vault", with: "")
            if let match = snapshots.first(where: { $0.targetFileName == clean || $0.targetFileName == t }) {
                chosen = match
            } else {
                print("❌ No snapshot found matching '\(t)'. Run 'sec backup --list' to view available versions.")
                exit(1)
            }
        } else {
            // Default: restore most recent snapshot in current project directory
            let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.resolvingSymlinksInPath().path
            if let match = snapshots.first(where: { $0.projectPath == currentDir }) {
                chosen = match
            } else if let first = snapshots.first {
                chosen = first
            } else {
                print("❌ No snapshots available.")
                exit(1)
            }
        }
        
        print("Restoring '\(chosen.targetFileName)' to snapshot v\(chosen.version) from \(chosen.relativeTime)...")
        do {
            try await BackupEngine.shared.restoreSnapshot(snapshotId: chosen.id)
            print("✅ Successfully rolled back '\(chosen.targetFileName)' to v\(chosen.version)!")
            print("   Masked decoy and active vault updated on disk.")
        } catch {
            print("❌ Restore failed: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    private static func handleTrash(arguments: [String]) async {
        if arguments.contains("--empty") || arguments.contains("--purge-all") {
            do {
                try BackupEngine.shared.purgeAllTrash()
                print("✅ Emptied all soft-deleted vaults from trash.")
            } catch {
                print("❌ Failed to empty trash: \(error.localizedDescription)")
            }
            return
        }
        
        if let restoreIdx = arguments.firstIndex(of: "--restore") ?? arguments.firstIndex(of: "-r"),
           restoreIdx + 1 < arguments.count {
            let idQuery = arguments[restoreIdx + 1]
            let trash = BackupEngine.shared.loadTrash()
            guard let match = trash.first(where: { $0.id.uuidString.lowercased().hasPrefix(idQuery.lowercased()) || $0.targetFileName == idQuery }) else {
                print("❌ Trash item not found matching '\(idQuery)'. Run 'sec trash' to list trashed vaults.")
                exit(1)
            }
            do {
                let restoredURL = try await BackupEngine.shared.restoreFromTrash(trashId: match.id)
                print("✅ Successfully restored '\(match.targetFileName)' to '\(restoredURL.path)'!")
            } catch {
                print("❌ Failed to restore from trash: \(error.localizedDescription)")
                exit(1)
            }
            return
        }
        
        if let purgeIdx = arguments.firstIndex(of: "--purge") ?? arguments.firstIndex(of: "-p"),
           purgeIdx + 1 < arguments.count {
            let idQuery = arguments[purgeIdx + 1]
            let trash = BackupEngine.shared.loadTrash()
            guard let match = trash.first(where: { $0.id.uuidString.lowercased().hasPrefix(idQuery.lowercased()) || $0.targetFileName == idQuery }) else {
                print("❌ Trash item not found matching '\(idQuery)'.")
                exit(1)
            }
            do {
                try BackupEngine.shared.purgeTrashItem(trashId: match.id)
                print("✅ Purged '\(match.targetFileName)' from trash.")
            } catch {
                print("❌ Failed to purge: \(error.localizedDescription)")
                exit(1)
            }
            return
        }
        
        let trash = BackupEngine.shared.loadTrash()
        if trash.isEmpty {
            print("🗑️  Trash is empty. Unlocked or removed vaults are automatically archived here.")
            return
        }
        
        print("=== sec Vault Trash (\(trash.count)) ===")
        print(String(format: "%-10@ %-16@ %-16@ %-8@ %@", "ID", "PROJECT", "FILE", "KEYS", "REMOVED"))
        print(String(repeating: "-", count: 68))
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        for t in trash {
            let idPrefix = String(t.id.uuidString.prefix(8))
            let dateStr = df.string(from: t.removedAt)
            print(String(format: "%-10@ %-16@ %-16@ %-8d %@", idPrefix, t.projectName, t.targetFileName, t.originalKeyCount, dateStr))
        }
        print("\nCommands:")
        print("   • Restore a vault:   sec trash --restore <id>")
        print("   • Purge from trash:  sec trash --purge <id>")
        print("   • Empty all trash:   sec trash --empty")
    }

    private static func printHelp() {
        let help = """
        sec - Touch ID Secret Vault for macOS
        Shields .env secrets from AI agents with in-memory injection & Finder right-click
        Enforces Strict Zero-Cache: Physical Touch ID hardware gate on every command!

        USAGE:
            sec [-f <file>] <cmd...>    Run command with secrets injected into memory (Single-Use)
            sec lock [--force] [file]   Lock file & replace with dummy (skips if already locked)
            sec edit [file]             Safely edit secrets in temporary buffer and re-encrypt
            sec view [file]             Print decrypted secrets to terminal (prompts Touch ID; --force-stdout to pipe)
            sec unlock [--yes] [file]   Restore plaintext to disk and move vault to trash
            sec backup [--all] [--list] Create or list versioned snapshots of encrypted vaults
            sec restore [file] [-v <#>] Rollback vault to a previous version snapshot
            sec trash [--restore <id>]  View or restore soft-deleted and unlocked vaults
            sec list [--scan] [--prune] List all locked secret vaults across your Mac
            sec scan [dir]              Discover and register existing vaults across folders
            sec export-key              Export master key for disaster recovery or Mac migration
            sec import-key [key]        Import master recovery key on a new or wiped Mac
            sec status                  Show keychain, zero-cache policy, and project vault status
            sec session                 Inspect access policy (Zero-Cache by default)
            sec install-finder          Install macOS Finder right-click Quick Actions
            sec help                    Show this help message

        EXAMPLES:
            # 1. Lock your .env, JSON, or secret file
            sec lock .env
            sec lock credentials.json

            # 2. View version snapshots and take manual backups
            sec backup .env
            sec backup --all
            sec backup --list
            sec restore .env --version 1

            # 3. Soft-delete trash recovery
            sec trash
            sec trash --restore 8f2a1b4c

            # 4. View all locked vaults across your Mac
            sec list
            sec list --scan ~/Developer
            sec list --prune

            # 5. Export / Import master recovery key
            sec export-key
            sec import-key <key>

            # 6. Run your app with secrets injected in memory (never written to disk)
            sec npm run dev
            sec -f .env.local npm run dev
            sec -f credentials.json python app.py
            sec cargo run

            # 7. Edit secrets safely
            sec edit .env
        """
        print(help)
    }
}
