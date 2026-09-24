import Foundation

public final class ProcessRunner {
    public static let shared = ProcessRunner()
    
    private init() {}
    
    /// Executes a command with decrypted secrets injected directly into process memory
    @discardableResult
    public func run(command: [String], vaultURL: URL?) async throws -> Int32 {
        guard !command.isEmpty else {
            print("Error: No command specified to run.")
            return 1
        }
        
        var injectedEnv = ProcessInfo.processInfo.environment
        
        // Find vault if not provided explicitly
        let targetVault: URL?
        if let vaultURL = vaultURL {
            targetVault = vaultURL
        } else {
            targetVault = VaultEngine.shared.findNearestVault()
        }
        
        if let vault = targetVault {
            let secrets = try await VaultEngine.shared.readDecryptedSecrets(vaultURL: vault)
            for (key, val) in secrets {
                injectedEnv[key] = val
            }
            let keyCount = secrets.count
            // Print brief status indicator to stderr so stdout is clean for piping
            fputs("🔓 [sec] Injected \(keyCount) secret\(keyCount == 1 ? "" : "s") into memory from '\(vault.lastPathComponent)'\n", stderr)
        } else {
            fputs("⚠️ [sec] No .env.vault found in current or parent directories. Running with standard environment.\n", stderr)
        }
        
        let process = Process()
        process.environment = injectedEnv
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        
        // Execute through user's default shell (zsh) to ensure full PATH, aliases, and nvm/fnm resolution
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shell)
        
        // Join command safely for shell execution
        let joinedCommand = command.map { arg in
            if arg.contains(" ") || arg.contains("\"") || arg.contains("$") || arg.contains("*") || arg.contains(";") {
                return "\"\(arg.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return arg
        }.joined(separator: " ")
        
        process.arguments = ["-c", joinedCommand]
        
        // Trap SIGINT and forward to child process
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            if process.isRunning {
                kill(process.processIdentifier, SIGINT)
            }
        }
        signal(SIGINT, SIG_IGN) // Ignore in parent so handler controls forwarding
        sigintSource.resume()
        
        do {
            try process.run()
            process.waitUntilExit()
            sigintSource.cancel()
            return process.terminationStatus
        } catch {
            sigintSource.cancel()
            fputs("Error executing command: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
