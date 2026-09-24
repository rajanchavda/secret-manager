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
            let target = arguments.count > 1 ? arguments[1] : ".env"
            await handleUnlock(target: target)
            
        case "status":
            handleStatus()
            
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
        guard !command.isEmpty else {
            print("Error: No command specified to run.")
            print("Usage: sec <command...> (e.g. sec npm run dev)")
            exit(1)
        }
        
        do {
            let exitCode = try await ProcessRunner.shared.run(command: command, vaultURL: nil)
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
            
            let parsed = EnvParser.shared.parse(plaintextString)
            print("🔓 Decrypted content of '\(vaultURL.lastPathComponent)':")
            print("--------------------------------------------------")
            if !parsed.isEmpty {
                for (key, val) in parsed.sorted(by: { $0.key < $1.key }) {
                    print("\(key)=\(val)")
                }
            } else {
                print(plaintextString)
            }
            print("--------------------------------------------------")
        } catch {
            print("❌ Error viewing vault: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    private static func handleUnlock(target: String) async {
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
        
        let plainFile = VaultEngine.shared.plainFileURL(for: vaultURL)
        print("⚠️  WARNING: Unlocking will restore plaintext secrets to disk at '\(plainFile.lastPathComponent)'.")
        print("   AI agents and background tools will be able to read them.")
        print("Are you sure? (y/N): ", terminator: "")
        
        guard let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              answer == "y" || answer == "yes" else {
            print("Cancelled.")
            return
        }
        
        do {
            try await VaultEngine.shared.unlockToDisk(vaultURL: vaultURL)
            print("🔓 Plaintext restored to '\(plainFile.lastPathComponent)'. Vault removed.")
        } catch {
            print("❌ Error unlocking file: \(error.localizedDescription)")
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
            print("   Right-click any file in Finder -> Quick Actions -> 'Lock Secrets with Touch ID (sec)'")
            print("   Right-click any vault file -> Quick Actions -> 'Edit Secrets with Touch ID (sec)'")
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
            sec <command...>            Run command with secrets injected into memory (Single-Use)
            sec lock [--force] [file]   Lock file & replace with dummy (skips if already locked)
            sec edit [file]             Safely edit secrets in temporary buffer and re-encrypt
            sec view [file]             Print decrypted secrets to terminal (prompts Touch ID)
            sec unlock [file]           Restore plaintext to disk and remove vault
            sec status                  Show keychain, zero-cache policy, and project vault status
            sec session                 Inspect access policy (Zero-Cache by default)
            sec install-finder          Install macOS Finder right-click Quick Actions
            sec help                    Show this help message

        EXAMPLES:
            # 1. Lock your .env file
            sec lock .env

            # 2. Run your app with secrets injected in memory (never written to disk)
            sec npm run dev
            sec pnpm dev
            sec cargo run
            sec python app.py

            # 3. Edit secrets safely
            sec edit .env

            # 4. Right-click integration in Finder
            sec install-finder
        """
        print(help)
    }
}
