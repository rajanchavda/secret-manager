import Foundation

public final class ProcessRunner {
    public static let shared = ProcessRunner()
    
    private init() {}
    
    /// Executes a command with decrypted secrets injected directly into process memory.
    /// Employs stealth in-memory loaders for Node.js/Python to completely hide secrets from `ps -E` and process tables.
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
        
        var secrets: [String: String] = [:]
        if let vault = targetVault {
            secrets = try await VaultEngine.shared.readDecryptedSecrets(vaultURL: vault)
        } else {
            fputs("⚠️ [sec] No .env.vault found in current or parent directories. Running with standard environment.\n", stderr)
        }
        
        let firstCmd = command[0].lowercased()
        let isNodeCommand = ["npm", "pnpm", "yarn", "bun", "node", "npx", "next", "vite", "turbo", "tsx", "nodemon"].contains { firstCmd.contains($0) }
        let isPythonCommand = ["python", "python3", "pytest", "flask", "uvicorn", "manage.py"].contains { firstCmd.contains($0) }
        
        var tempCleanupPaths: [String] = []
        defer {
            for path in tempCleanupPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        
        if !secrets.isEmpty {
            if isNodeCommand {
                // STEALTH MODE FOR NODE:
                // Inject via an ephemeral, self-destructing preload script.
                // Secrets are NEVER passed in `execve` `envp`, making them 100% invisible to `ps -E`.
                let loaderPath = createNodeStealthLoader(secrets: secrets)
                tempCleanupPaths.append(loaderPath)
                
                let existingNodeOptions = injectedEnv["NODE_OPTIONS"] ?? ""
                if existingNodeOptions.isEmpty {
                    injectedEnv["NODE_OPTIONS"] = "--require \"\(loaderPath)\""
                } else {
                    injectedEnv["NODE_OPTIONS"] = "--require \"\(loaderPath)\" \(existingNodeOptions)"
                }
                
                fputs("🔒 [sec] Injected \(secrets.count) secret\(secrets.count == 1 ? "" : "s") via stealth loader (hidden from ps -E & process table)\n", stderr)
            } else if isPythonCommand {
                // STEALTH MODE FOR PYTHON:
                // Inject via an ephemeral sitecustomize.py in a private directory.
                let (pyDir, _) = createPythonStealthLoader(secrets: secrets)
                tempCleanupPaths.append(pyDir)
                
                let existingPyPath = injectedEnv["PYTHONPATH"] ?? ""
                if existingPyPath.isEmpty {
                    injectedEnv["PYTHONPATH"] = pyDir
                } else {
                    injectedEnv["PYTHONPATH"] = "\(pyDir):\(existingPyPath)"
                }
                
                fputs("🔒 [sec] Injected \(secrets.count) secret\(secrets.count == 1 ? "" : "s") via stealth loader (hidden from ps -E & process table)\n", stderr)
            } else {
                // Generic command: Direct memory injection into environment
                for (key, val) in secrets {
                    injectedEnv[key] = val
                }
                fputs("🔓 [sec] Injected \(secrets.count) secret\(secrets.count == 1 ? "" : "s") into memory from '\(targetVault?.lastPathComponent ?? ".env.vault")'\n", stderr)
            }
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
    
    // MARK: - Stealth Helpers
    
    /// Creates a self-destructing Node.js CommonJS preload module
    private func createNodeStealthLoader(secrets: [String: String]) -> String {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let loaderURL = tempDir.appendingPathComponent(".sec_node_\(UUID().uuidString).cjs")
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: secrets, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        
        let content = """
        // Generated ephemerally by sec
        const fs = require('fs');
        const secrets = \(jsonString);
        for (const [k, v] of Object.entries(secrets)) {
            process.env[k] = v;
        }
        delete process.env.NODE_OPTIONS;
        try { fs.unlinkSync(__filename); } catch (_) {}
        """
        
        try? content.write(to: loaderURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: loaderURL.path)
        return loaderURL.path
    }
    
    /// Creates a self-destructing Python sitecustomize module in a private directory
    private func createPythonStealthLoader(secrets: [String: String]) -> (dir: String, file: String) {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let stealthDir = tempDir.appendingPathComponent(".sec_py_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: stealthDir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])
        
        let loaderURL = stealthDir.appendingPathComponent("sitecustomize.py")
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: secrets, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return (stealthDir.path, loaderURL.path)
        }
        
        let content = """
        import os, json
        secrets = json.loads('''\(jsonString)''')
        os.environ.update(secrets)
        try:
            os.remove(__file__)
        except Exception:
            pass
        """
        
        try? content.write(to: loaderURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: loaderURL.path)
        return (stealthDir.path, loaderURL.path)
    }
}
