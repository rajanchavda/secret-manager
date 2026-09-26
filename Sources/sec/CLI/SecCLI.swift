import Foundation

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
            let target = arguments.count > 1 ? arguments[1] : ".env"
            await handleView(target: target)
            
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
    
    private static func handleView(target: String) async {
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
    
    private static func printHelp() {
        let help = """
        sec - Touch ID Secret Vault for macOS
        Shields .env secrets from AI agents with in-memory injection & Finder right-click
        Enforces Strict Zero-Cache: Physical Touch ID hardware gate on every command!

        USAGE:
            sec [-f <file>] <cmd...>    Run command with secrets injected into memory (Single-Use)
            sec lock [--force] [file]   Lock file & replace with dummy (skips if already locked)
            sec edit [file]             Safely edit secrets in temporary buffer and re-encrypt
            sec view [file]             Print decrypted secrets to terminal (prompts Touch ID)
            sec unlock [--yes] [file]   Restore plaintext to disk and remove vault
            sec list [--scan] [--prune] List all locked secret vaults across your Mac
            sec scan [dir]              Discover and register existing vaults across folders
            sec status                  Show keychain, zero-cache policy, and project vault status
            sec session                 Inspect access policy (Zero-Cache by default)
            sec install-finder          Install macOS Finder right-click Quick Actions
            sec help                    Show this help message

        EXAMPLES:
            # 1. Lock your .env, JSON, or secret file
            sec lock .env
            sec lock credentials.json

            # 2. View all locked vaults across your Mac
            sec list
            sec list --scan ~/Developer
            sec list --prune

            # 3. Run your app with secrets injected in memory (never written to disk)
            sec npm run dev
            sec -f .env.local npm run dev
            sec -f credentials.json python app.py
            sec cargo run

            # 4. Edit secrets safely
            sec edit .env

            # 5. Right-click integration in Finder
            sec install-finder
        """
        print(help)
    }
}
