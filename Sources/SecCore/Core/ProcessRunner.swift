import Foundation

public final class ProcessRunner {
    public static let shared = ProcessRunner()
    
    private init() {}
    
    /// Executes a command with decrypted secrets injected directly into process memory.
    /// Node.js/Python commands receive them through a self-deleting preload loader, which keeps secrets out of
    /// the launching shell's environment. Processes the app spawns still inherit them as ordinary environment
    /// variables, so this is not a defence against a same-user `ps -E`.
    @discardableResult
    public func run(command: [String], vaultURL: URL?) async throws -> Int32 {
        guard !command.isEmpty else {
            print("Error: No command specified to run.")
            return 1
        }
        
        // Auto-prune missing vaults and deleted decoys from registry
        RegistryManager.shared.autoPrune()
        
        var injectedEnv = ProcessInfo.processInfo.environment
        
        // Find vault if not provided explicitly
        var targetVault: URL?
        if let vaultURL = vaultURL {
            targetVault = vaultURL
        } else {
            targetVault = VaultEngine.shared.findNearestVault()
        }
        
        var secrets: [String: String] = [:]
        var sourceDescription: String = ".env.vault"
        
        if let vault = targetVault {
            sourceDescription = vault.lastPathComponent
            let freshness = VaultEngine.shared.checkVaultFreshness(vaultURL: vault)
            
            switch freshness {
            case .orphan(let orphanURL):
                // Decoy plaintext file was removed or git-cleaned, but the encrypted vault is safe!
                // Read decrypted secrets directly from the vault rather than destroying it.
                secrets = try await VaultEngine.shared.readDecryptedSecrets(vaultURL: orphanURL, command: command)
                sourceDescription = "\(orphanURL.lastPathComponent) (decoy missing)"
                
            case .stale(let plainURL, _, _):
                fputs("⚠️ [sec] Stale vault detected: '\(plainURL.lastPathComponent)' was modified after '\(vault.lastPathComponent)' was created.\n", stderr)
                fputs("   Using updated plaintext secrets from '\(plainURL.lastPathComponent)' (run 'sec lock --force \(plainURL.lastPathComponent)' to re-lock).\n", stderr)
                if let content = try? String(contentsOf: plainURL, encoding: .utf8) {
                    secrets = EnvParser.shared.parse(content)
                    sourceDescription = "\(plainURL.lastPathComponent) (unlocked plaintext)"
                }
                
            case .fresh:
                secrets = try await VaultEngine.shared.readDecryptedSecrets(vaultURL: vault, command: command)
                sourceDescription = vault.lastPathComponent
                
            case .missing:
                targetVault = nil
            }
        }
        
        // If no vault or orphan was cleaned up, check if a local plaintext .env exists
        if targetVault == nil && secrets.isEmpty {
            let localPlain = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: localPlain.path),
               let content = try? String(contentsOf: localPlain, encoding: .utf8),
               !VaultEngine.shared.isDummyContent(content) {
                fputs("ℹ️ [sec] No .env.vault found, but unlocked '.env' detected. Loading environment (run 'sec lock' to protect).\n", stderr)
                secrets = EnvParser.shared.parse(content)
                sourceDescription = ".env (unlocked)"
            } else {
                fputs("⚠️ [sec] No .env.vault found in current or parent directories. Running with standard environment.\n", stderr)
            }
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
            if isNodeCommand, let loaderPath = createNodeStealthLoader(secrets: secrets) {
                // PRELOAD MODE FOR NODE:
                // Inject via an ephemeral, self-deleting preload script, so secrets are not in the `envp`
                // of the shell or the first Node process. Node's own children inherit them via `envp`.
                tempCleanupPaths.append(loaderPath)
                
                let existingNodeOptions = injectedEnv["NODE_OPTIONS"] ?? ""
                if existingNodeOptions.isEmpty {
                    injectedEnv["NODE_OPTIONS"] = "--require \"\(loaderPath)\""
                } else {
                    injectedEnv["NODE_OPTIONS"] = "--require \"\(loaderPath)\" \(existingNodeOptions)"
                }
                
                fputs("🔒 [sec] Injected \(secrets.count) secret\(secrets.count == 1 ? "" : "s") from '\(sourceDescription)' via preload loader\n", stderr)
            } else if isPythonCommand, let pyDir = createPythonStealthLoader(secrets: secrets) {
                // PRELOAD MODE FOR PYTHON:
                // Inject via an ephemeral sitecustomize.py in a private directory.
                tempCleanupPaths.append(pyDir)
                
                let existingPyPath = injectedEnv["PYTHONPATH"] ?? ""
                if existingPyPath.isEmpty {
                    injectedEnv["PYTHONPATH"] = pyDir
                } else {
                    injectedEnv["PYTHONPATH"] = "\(pyDir):\(existingPyPath)"
                }
                
                fputs("🔒 [sec] Injected \(secrets.count) secret\(secrets.count == 1 ? "" : "s") from '\(sourceDescription)' via preload loader\n", stderr)
            } else {
                // Generic command (or the loader could not be written): inject into the child environment
                for (key, val) in secrets {
                    injectedEnv[key] = val
                }
                fputs("🔓 [sec] Injected \(secrets.count) secret\(secrets.count == 1 ? "" : "s") into memory from '\(sourceDescription)'\n", stderr)
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
        
        // Trap SIGINT and SIGTERM and forward to child process
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            if process.isRunning {
                kill(process.processIdentifier, SIGINT)
            }
        }
        signal(SIGINT, SIG_IGN)
        sigintSource.resume()
        
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler {
            if process.isRunning {
                kill(process.processIdentifier, SIGTERM)
            }
        }
        signal(SIGTERM, SIG_IGN)
        sigtermSource.resume()
        
        do {
            try process.run()
            process.waitUntilExit()
            sigintSource.cancel()
            sigtermSource.cancel()
            return process.terminationStatus
        } catch {
            sigintSource.cancel()
            sigtermSource.cancel()
            fputs("Error executing command: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
    
    // MARK: - Preload Loader Helpers
    
    /// Base64 of the secrets as JSON. Embedding base64 means no secret value (quotes, newlines,
    /// backslashes) can alter or break out of the generated loader source.
    private func encodedSecrets(_ secrets: [String: String]) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: secrets, options: []) else {
            return nil
        }
        return jsonData.base64EncodedString()
    }
    
    /// Source of the self-deleting Node.js CommonJS preload module
    func nodeLoaderSource(secrets: [String: String]) -> String? {
        guard let encoded = encodedSecrets(secrets) else { return nil }
        return """
        // Generated ephemerally by sec
        const fs = require('fs');
        const secrets = JSON.parse(Buffer.from("\(encoded)", "base64").toString("utf8"));
        for (const [k, v] of Object.entries(secrets)) {
            process.env[k] = v;
        }
        delete process.env.NODE_OPTIONS;
        try { fs.unlinkSync(__filename); } catch (_) {}
        """
    }
    
    /// Source of the self-deleting Python sitecustomize module
    func pythonLoaderSource(secrets: [String: String]) -> String? {
        guard let encoded = encodedSecrets(secrets) else { return nil }
        return """
        import os, json, base64
        secrets = json.loads(base64.b64decode("\(encoded)").decode("utf-8"))
        os.environ.update(secrets)
        try:
            os.remove(__file__)
        except Exception:
            pass
        """
    }
    
    /// Creates the file already restricted to the owner (0600), so the content is never readable
    /// by others, and refuses to follow or reuse an existing path.
    private func writePrivateFile(_ content: String, to url: URL) -> Bool {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(content.utf8))
            try handle.close()
            return true
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }
    
    /// Creates a self-deleting Node.js CommonJS preload module. Returns nil if it could not be written.
    private func createNodeStealthLoader(secrets: [String: String]) -> String? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let loaderURL = tempDir.appendingPathComponent(".sec_node_\(UUID().uuidString).cjs")
        
        guard let content = nodeLoaderSource(secrets: secrets),
              writePrivateFile(content, to: loaderURL) else {
            return nil
        }
        return loaderURL.path
    }
    
    /// Creates a self-deleting Python sitecustomize module in a private directory.
    /// Returns the directory to put on PYTHONPATH, or nil if it could not be written.
    private func createPythonStealthLoader(secrets: [String: String]) -> String? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let stealthDir = tempDir.appendingPathComponent(".sec_py_\(UUID().uuidString)", isDirectory: true)
        let loaderURL = stealthDir.appendingPathComponent("sitecustomize.py")
        
        guard let content = pythonLoaderSource(secrets: secrets),
              (try? FileManager.default.createDirectory(at: stealthDir, withIntermediateDirectories: false, attributes: [
                  .posixPermissions: 0o700
              ])) != nil else {
            return nil
        }
        guard writePrivateFile(content, to: loaderURL) else {
            try? FileManager.default.removeItem(at: stealthDir)
            return nil
        }
        return stealthDir.path
    }
}
