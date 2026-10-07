import XCTest
import CryptoKit
import LocalAuthentication
@testable import SecCore
@testable import sec

final class SecTests: XCTestCase {
    
    /// Stand-in for `~/.sec`. Named `.sec` because the registry recognises its own files by that path component.
    private static let testDataDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("sec-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(".sec", isDirectory: true)
    
    override class func setUp() {
        super.setUp()
        // Never touch the developer's real ~/.sec (registry, backups, trash, master key) from tests.
        // Set before any SecCore singleton is created, since they create their directories on init.
        try? FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        SecPaths.overrideForTesting = testDataDirectory
        BiometricAuth.shared.bypassForTesting = true
        KeychainManager.shared.testMasterKey = Data(repeating: 7, count: 32)
    }
    
    override class func tearDown() {
        try? FileManager.default.removeItem(at: testDataDirectory.deletingLastPathComponent())
        super.tearDown()
    }
    
    func testSuiteNeverUsesTheRealDataDirectory() {
        let realDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sec").standardizedFileURL.path
        XCTAssertNotEqual(SecPaths.dataDirectory.standardizedFileURL.path, realDirectory)
        XCTAssertFalse(BackupEngine.shared.backupsDirectory.path.hasPrefix(realDirectory + "/"))
        XCTAssertFalse(BackupEngine.shared.trashDirectory.path.hasPrefix(realDirectory + "/"))
    }
    
    func testSealedMasterKeyRefusesUnauthenticatedUse() throws {
        try XCTSkipUnless(SecureEnclave.isAvailable, "Requires a Secure Enclave")
        let wrapped = try KeychainManager.seal(Data(repeating: 1, count: 32))
        // An agent has the file but cannot satisfy Touch ID / password.
        let context = LAContext()
        context.interactionNotAllowed = true
        XCTAssertThrowsError(try KeychainManager.open(wrapped, context: context))
    }
    
    func testSessionRequiresAuthenticationAndIsNotPersisted() {
        let session = SessionManager.shared
        defer {
            session.configuredSessionDuration = nil
            session.clearSession()
        }
        session.setSessionDuration(minutes: 15)
        session.clearSession()
        session.startSession()
        XCTAssertFalse(session.isSessionActive(), "Starting a session without Touch ID must not grant access")
        let sessionFile = SecPaths.dataDirectory.appendingPathComponent("session.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionFile.path))
    }
    
    func testCryptoEngineRoundTrip() throws {
        var keyBytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { keyBytes[i] = UInt8(i) }
        let keyData = Data(keyBytes)
        
        let originalSecret = "DATABASE_URL=postgres://user:pass@localhost:5432/db\nAPI_KEY=sk_test_12345"
        let secretData = originalSecret.data(using: .utf8)!
        
        let encryptedVault = try CryptoEngine.shared.encrypt(plaintext: secretData, keyData: keyData)
        XCTAssertFalse(encryptedVault.isEmpty)
        
        let decryptedData = try CryptoEngine.shared.decrypt(vaultData: encryptedVault, keyData: keyData)
        let decryptedString = String(data: decryptedData, encoding: .utf8)
        
        XCTAssertEqual(decryptedString, originalSecret)
    }
    
    /// Backward compatibility: a v1 vault written by an already-released build must keep
    /// decrypting. If this fails, the vault format changed and existing users are locked out.
    func testDecryptsVaultFromReleasedV1Format() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let releasedVault = """
        {
          "cipher" : "aes-256-gcm",
          "ciphertext" : "p0g1cg6OW4IRDtinYgm0gUGeaiSnvQYuoX5J9QvMB2ShTGjQ2hgjfTPzZ6llEuyKMzQiKg==",
          "createdAt" : "2026-01-01T00:00:00Z",
          "nonce" : "oKGio6Slpqeoqaqr",
          "tag" : "Qggm6iMPclGqccua+qOTwg==",
          "version" : 1
        }
        """.data(using: .utf8)!

        let decrypted = try CryptoEngine.shared.decrypt(vaultData: releasedVault, keyData: keyData)
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), "API_KEY=sk_test_12345\nDB=postgres://u:p@localhost/db")
    }

    func testEnvParser() {
        let envContent = """
        # Database config
        DB_HOST=127.0.0.1
        DB_PORT=5432
        
        # Secret keys
        API_SECRET="super-secret-value"
        export JWT_TOKEN='ey12345'
        """
        
        let parsed = EnvParser.shared.parse(envContent)
        XCTAssertEqual(parsed["DB_HOST"], "127.0.0.1")
        XCTAssertEqual(parsed["DB_PORT"], "5432")
        XCTAssertEqual(parsed["API_SECRET"], "super-secret-value")
        XCTAssertEqual(parsed["JWT_TOKEN"], "ey12345")
        
        let dummy = EnvParser.shared.generateDummyTemplate(from: envContent, fileName: ".env")
        XCTAssertTrue(dummy.contains("API_SECRET=locked_by_sec"))
        XCTAssertTrue(dummy.contains("JWT_TOKEN=locked_by_sec"))
        XCTAssertFalse(dummy.contains("super-secret-value"))
        XCTAssertFalse(dummy.contains("ey12345"))
    }
    
    func testArbitraryFileMasking() {
        // Test arbitrary file without KEY=VALUE (e.g. private key / raw token)
        let rawContent = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA0...\n-----END RSA PRIVATE KEY-----"
        let dummy = EnvParser.shared.generateDummyTemplate(from: rawContent, fileName: "id_rsa")
        XCTAssertTrue(dummy.contains("PROTECTED BY sec"))
        XCTAssertTrue(dummy.contains("id_rsa.vault"))
        XCTAssertFalse(dummy.contains("MIIEowIBAAKCAQEA0"))
    }
    
    func testJSONMasking() {
        // Test JSON file masking
        let jsonContent = """
        {
            "client_secret": "xyz123_secret_token",
            "project_id": "my-firebase-app",
            "nested": {
                "private_key": "secret_key_abc"
            }
        }
        """
        let dummy = EnvParser.shared.generateDummyTemplate(from: jsonContent, fileName: "credentials.json")
        XCTAssertTrue(dummy.contains("\"client_secret\" : \"locked_by_sec\""))
        XCTAssertTrue(dummy.contains("\"private_key\" : \"locked_by_sec\""))
        XCTAssertFalse(dummy.contains("xyz123_secret_token"))
        XCTAssertFalse(dummy.contains("secret_key_abc"))
    }
    
    func testVaultURLDerivation() {
        let plain = URL(fileURLWithPath: "/path/to/.env")
        let vault = VaultEngine.shared.vaultURL(for: plain)
        XCTAssertEqual(vault.lastPathComponent, ".env.vault")
        
        let restored = VaultEngine.shared.plainFileURL(for: vault)
        XCTAssertEqual(restored.lastPathComponent, ".env")
    }
    
    func testStealthNodeLoaderExecution() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let loaderURL = tempDir.appendingPathComponent(".test_loader_\(UUID().uuidString).cjs")
        
        let content = """
        const fs = require('fs');
        process.env.TEST_STEALTH_SECRET = "INJECTED_SAFELY_INTO_MEMORY";
        delete process.env.NODE_OPTIONS;
        try { fs.unlinkSync(__filename); } catch (_) {}
        """
        try content.write(to: loaderURL, atomically: true, encoding: .utf8)
        
        // Execute node to verify it reads secret and unlinks loader
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "-e", "console.log(process.env.TEST_STEALTH_SECRET)"]
        
        var env = ProcessInfo.processInfo.environment
        env["NODE_OPTIONS"] = "--require \"\(loaderURL.path)\""
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let outputStr = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(outputStr, "INJECTED_SAFELY_INTO_MEMORY")
        // Verify loader unlinked itself
        XCTAssertFalse(FileManager.default.fileExists(atPath: loaderURL.path))
    }
    
    /// Runs a generated loader in the real interpreter and returns the values it placed in the environment
    private func runLoader(source: String, fileName: String, interpreter: String, script: String, envKey: String, envValue: (URL) -> String) throws -> [String: String] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(".sec_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let loaderURL = dir.appendingPathComponent(fileName)
        try source.write(to: loaderURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [interpreter, "-c", script]
        if interpreter == "node" { process.arguments = [interpreter, "-e", script] }
        var env = ProcessInfo.processInfo.environment
        env[envKey] = envValue(loaderURL)
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw XCTSkip("\(interpreter) is not available")
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 127 { throw XCTSkip("\(interpreter) is not available") }
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: loaderURL.path), "loader must delete itself")
        return (try JSONSerialization.jsonObject(with: output) as? [String: String]) ?? [:]
    }

    private let hostileSecrets = [
        "SEC_T_QUOTES": "a'''+str(1336+1)+'''b \"\"\" `${1+1}`",
        "SEC_T_PEM": "-----BEGIN KEY-----\nline1\nline2\n-----END KEY-----",
        "SEC_T_BACKSLASH": "C:\\new\\table \\u0041 \\",
        "SEC_T_UNICODE": "pässwörd 🔐 </script>"
    ]

    func testPythonLoaderRoundTripsHostileValues() throws {
        let source = try XCTUnwrap(ProcessRunner.shared.pythonLoaderSource(secrets: hostileSecrets))
        let script = "import os, json, sys; sys.stdout.write(json.dumps({k: v for k, v in os.environ.items() if k.startswith('SEC_T_')}))"
        let seen = try runLoader(source: source, fileName: "sitecustomize.py", interpreter: "python3", script: script,
                                 envKey: "PYTHONPATH", envValue: { $0.deletingLastPathComponent().path })
        XCTAssertEqual(seen, hostileSecrets)
    }

    func testNodeLoaderRoundTripsHostileValues() throws {
        let source = try XCTUnwrap(ProcessRunner.shared.nodeLoaderSource(secrets: hostileSecrets))
        let script = "process.stdout.write(JSON.stringify(Object.fromEntries(Object.entries(process.env).filter(([k]) => k.startsWith('SEC_T_')))))"
        let seen = try runLoader(source: source, fileName: "loader.cjs", interpreter: "node", script: script,
                                 envKey: "NODE_OPTIONS", envValue: { "--require \"\($0.path)\"" })
        XCTAssertEqual(seen, hostileSecrets)
    }

    func testPromptShowsCommandAndRequester() {
        // The command is flattened to one bounded line so it cannot fake extra prompt text
        let shown = CallerInfo.displayCommand(["npm", "run", "dev\n(started by: Terminal)\u{1B}[2K"])
        XCTAssertFalse(shown.contains("\n"))
        XCTAssertFalse(shown.contains("\u{1B}"))
        XCTAssertTrue(shown.hasPrefix("npm run dev "))
        
        let long = CallerInfo.displayCommand([String(repeating: "x", count: 500)])
        XCTAssertEqual(long.count, 81)
        XCTAssertTrue(long.hasSuffix("…"))
        
        // The test runner always has a parent process, and it must end the reason
        let names = CallerInfo.ancestorNames()
        XCTAssertFalse(names.isEmpty)
        XCTAssertLessThanOrEqual(names.count, 4)
        let reason = CallerInfo.annotate(reason: "sec requires Touch ID to view '.env.vault'")
        XCTAssertTrue(reason.hasPrefix("sec requires Touch ID to view '.env.vault' (started by: \(names[0])"))
        XCTAssertTrue(reason.hasSuffix(")"))
    }
    
    func testNotifierNeverSplicesTextIntoScript() {
        let hostile = "x\\\" & (do shell script \"touch /tmp/pwned\") & \";.env"
        let args = Notifier.shared.notificationArguments(title: hostile, message: hostile)
        let separator = try! XCTUnwrap(args.firstIndex(of: "--"))
        // Script source is constant; the text only appears after `--` as plain argv items
        XCTAssertFalse(args[..<separator].contains(where: { $0.contains("pwned") }))
        XCTAssertEqual(Array(args[(separator + 1)...]), [hostile, hostile])
    }
    
    func testUnlockedPlaintextIsOwnerOnly() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(".sec_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        // Replaces an existing world-readable decoy and ends up 0600 with no stray temp file
        let target = dir.appendingPathComponent(".env")
        try "API_KEY=locked_by_sec".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        
        try VaultEngine.shared.writeOwnerOnly(Data("API_KEY=real".utf8), to: target)
        
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "API_KEY=real")
        let perms = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(perms.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [".env"])
    }
    
    func testAlreadyLockedDetection() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let testDir = tempDir.appendingPathComponent(".sec_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let envFile = testDir.appendingPathComponent(".env")
        let vaultFile = testDir.appendingPathComponent(".env.vault")
        
        // 1. When vault already exists, isAlreadyLocked should return true
        try "FOO=BAR\nSECRET=123".write(to: envFile, atomically: true, encoding: .utf8)
        try "dummy_encrypted".write(to: vaultFile, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(VaultEngine.shared.isAlreadyLocked(fileURL: envFile))
        
        // 2. When file is already a .vault file, isAlreadyLocked should return true
        XCTAssertTrue(VaultEngine.shared.isAlreadyLocked(fileURL: vaultFile))
        
        // 3. When file content has dummy template signature, isAlreadyLocked should return true
        let dummyContent = EnvParser.shared.generateDummyTemplate(from: "FOO=BAR\nSECRET=123", fileName: ".env")
        try dummyContent.write(to: envFile, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: vaultFile)
        
        XCTAssertTrue(VaultEngine.shared.isDummyContent(dummyContent))
        XCTAssertTrue(VaultEngine.shared.isAlreadyLocked(fileURL: envFile))
        
        // 4. When file is normal and vault does not exist, isAlreadyLocked should return false
        try "NEW_SECRET=456".write(to: envFile, atomically: true, encoding: .utf8)
        XCTAssertFalse(VaultEngine.shared.isAlreadyLocked(fileURL: envFile))
    }
    
    func testJSONParsingForEnvironmentInjection() {
        let jsonContent = """
        {
            "DATABASE_URL": "postgres://user:pass@localhost:5432/mydb",
            "PORT": 8080,
            "DEBUG_ENABLED": true,
            "SERVICE_CONFIG": {
                "projectId": "my-cloud-project",
                "privateKeyId": "key123"
            }
        }
        """
        let parsed = EnvParser.shared.parse(jsonContent)
        XCTAssertEqual(parsed["DATABASE_URL"], "postgres://user:pass@localhost:5432/mydb")
        XCTAssertEqual(parsed["PORT"], "8080")
        XCTAssertEqual(parsed["DEBUG_ENABLED"], "true")
        XCTAssertNotNil(parsed["SERVICE_CONFIG"])
        XCTAssertTrue(parsed["SERVICE_CONFIG"]!.contains("my-cloud-project"))
    }
    
    func testVaultVariantsDiscovery() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let testDir = tempDir.appendingPathComponent(".sec_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let localVault = testDir.appendingPathComponent(".env.local.vault")
        try "mock_vault_content".write(to: localVault, atomically: true, encoding: .utf8)
        
        let found = VaultEngine.shared.findNearestVault(startingAt: testDir)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.lastPathComponent, ".env.local.vault")
    }
    
    func testMultilineEnvParsing() {
        let multilineEnv = """
        SERVER_PORT=8000
        RSA_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA0ABC123XYZ
        -----END RSA PRIVATE KEY-----"
        API_TOKEN=secret_xyz
        """
        let parsed = EnvParser.shared.parse(multilineEnv)
        XCTAssertEqual(parsed["SERVER_PORT"], "8000")
        XCTAssertEqual(parsed["API_TOKEN"], "secret_xyz")
        XCTAssertNotNil(parsed["RSA_PRIVATE_KEY"])
        XCTAssertTrue(parsed["RSA_PRIVATE_KEY"]!.contains("MIIEowIBAAKCAQEA0ABC123XYZ"))
        XCTAssertTrue(parsed["RSA_PRIVATE_KEY"]!.contains("\n"))
    }
    
    func testInlineCommentsAndBOM() {
        let envWithBOM = "\u{FEFF}PORT=3000 # Default listening port\nDB_PASS=\"password#with#hash\" # Inline comment"
        let parsed = EnvParser.shared.parse(envWithBOM)
        XCTAssertEqual(parsed["PORT"], "3000")
        XCTAssertEqual(parsed["DB_PASS"], "password#with#hash")
    }
    
    func testYAMLSupport() {
        let yamlContent = """
        database_url: "postgres://localhost:5432/app"
        api_key: "sk_live_123"
        services:
          port: 4000
        """
        let parsed = EnvParser.shared.parse(yamlContent)
        XCTAssertEqual(parsed["database_url"], "postgres://localhost:5432/app")
        XCTAssertEqual(parsed["api_key"], "sk_live_123")
        
        let dummy = EnvParser.shared.generateDummyTemplate(from: yamlContent, fileName: "config.yaml")
        XCTAssertTrue(dummy.contains("database_url: \"locked_by_sec\""))
        XCTAssertTrue(dummy.contains("api_key: \"locked_by_sec\""))
        XCTAssertFalse(dummy.contains("sk_live_123"))
    }
    
    func testDecoyNeverContainsFixtureSecrets() {
        let secrets = [
            "sk_live_COMMENTED_OUT", "hunter2_in_comment", "pg_pass_inline", "MIIEowIBAAKCAQEA0PEMBODY",
            "c2VjcmV0VG9rZW5QYWRkZWQ", "it's_a_quote_trap", "tail_after_quote", "yaml_block_line_one",
            "Proc-Type-Secret", "yaml_list_secret", "yaml_nested_item_secret", "yaml_plain_continuation",
            "yaml_comment_secret", "yaml_quoted_continuation", "json_fragment_secret"
        ]

        let envContent = """
        # prod key: sk_live_COMMENTED_OUT
        #OLD_PASSWORD=hunter2_in_comment
        DATABASE_URL=postgres://u:pg_pass_inline@localhost/db # pg_pass_inline
        export RSA_KEY="-----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA0PEMBODY
        it's_a_quote_trap
        tail_after_quote==
        -----END RSA PRIVATE KEY-----"
        c2VjcmV0VG9rZW5QYWRkZWQ=
        EMPTY_VALUE=
        "client_secret": "json_fragment_secret=",
        """
        let envDummy = EnvParser.shared.generateDummyTemplate(from: envContent, fileName: ".env")
        for secret in secrets {
            XCTAssertFalse(envDummy.contains(secret), "decoy .env leaked \(secret)")
        }
        XCTAssertTrue(envDummy.contains("DATABASE_URL=locked_by_sec"))
        XCTAssertTrue(envDummy.contains("export RSA_KEY=locked_by_sec"))
        XCTAssertTrue(envDummy.contains("EMPTY_VALUE=locked_by_sec"))
        XCTAssertTrue(VaultEngine.shared.isDummyContent(envDummy))

        let yamlContent = """
        # rotate me: yaml_comment_secret
        api_key: live_value # yaml_comment_secret
        private_key: |
          yaml_block_line_one
          Proc-Type-Secret: 4,ENCRYPTED

          yaml_block_line_one
        description: start of value
          yaml_plain_continuation
        quoted: "first line
        yaml_quoted_continuation: still inside"
        tokens:
          - yaml_list_secret
          - name: yaml_nested_item_secret
            port: 8080
        defaults: &defaults
          host: localhost
        production:
          <<: *defaults
        """
        let yamlDummy = EnvParser.shared.generateDummyTemplate(from: yamlContent, fileName: "config.yaml")
        for secret in secrets {
            XCTAssertFalse(yamlDummy.contains(secret), "decoy YAML leaked \(secret)")
        }
        XCTAssertTrue(yamlDummy.contains("api_key: \"locked_by_sec\""))
        XCTAssertTrue(yamlDummy.contains("private_key: \"locked_by_sec\""))
        XCTAssertTrue(yamlDummy.contains("tokens:\n  - \"locked_by_sec\"\n  - name: \"locked_by_sec\"\n    port: \"locked_by_sec\""))
        XCTAssertTrue(yamlDummy.contains("defaults: &defaults\n  host: \"locked_by_sec\""))
        XCTAssertTrue(yamlDummy.contains("production:\n  <<: *defaults"))
        XCTAssertTrue(VaultEngine.shared.isDummyContent(yamlDummy))
    }

    func testDummyDetectionRequiresRealPlaceholder() {
        // A real file that only mentions the placeholder must still be lockable
        XCTAssertFalse(VaultEngine.shared.isDummyContent("NOTE=see locked_by_sec docs\nAPI_KEY=real_value"))
        XCTAssertFalse(VaultEngine.shared.isDummyContent("API_KEY=real_value # was locked_by_sec"))
        XCTAssertFalse(VaultEngine.shared.isDummyContent("{\"note\": \"PROTECTED BY sec, locked_by_sec\", \"key\": \"real\"}"))

        // Every decoy shape sec has written is still recognised
        XCTAssertTrue(VaultEngine.shared.isDummyContent("API_KEY=locked_by_sec"))
        XCTAssertTrue(VaultEngine.shared.isDummyContent("API_KEY=locked_by_sec\nNEW_KEY=added_by_hand"))
        XCTAssertTrue(VaultEngine.shared.isDummyContent("# 🔒 PROTECTED BY sec (Touch ID Secret Vault)\n# View or edit: sec edit id_rsa"))
        XCTAssertTrue(VaultEngine.shared.isDummyContent("api_key: \"locked_by_sec\""))
        XCTAssertTrue(VaultEngine.shared.isDummyContent("{\"a\": {\"b\": [\"locked_by_sec\"]}, \"flag\": false}"))
    }

    func testRegistryManagerRegistrationAndPrune() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sec-test-reg-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let plainFile = tempDir.appendingPathComponent(".env")
        let vaultFile = tempDir.appendingPathComponent(".env.vault")
        
        try? "API_KEY=locked_by_sec\n# PROTECTED BY sec".write(to: plainFile, atomically: true, encoding: .utf8)
        try? "encrypted-payload".write(to: vaultFile, atomically: true, encoding: .utf8)
        
        RegistryManager.shared.register(vaultURL: vaultFile, plainURL: plainFile)
        
        let loaded = RegistryManager.shared.loadRegistry()
        XCTAssertTrue(loaded.records.contains(where: { $0.vaultPath == vaultFile.standardizedFileURL.path }))
        
        let record = loaded.records.first(where: { $0.vaultPath == vaultFile.standardizedFileURL.path })!
        let status = RegistryManager.shared.inspectVault(record: record)
        XCTAssertEqual(status.statusCode, "protected")
        XCTAssertTrue(status.statusDescription.contains("Protected"))
        
        // Remove vault file and test prune
        try? FileManager.default.removeItem(at: vaultFile)
        let (removed, _) = RegistryManager.shared.prune()
        XCTAssertGreaterThanOrEqual(removed, 1)
        
        let reloaded = RegistryManager.shared.loadRegistry()
        XCTAssertFalse(reloaded.records.contains(where: { $0.vaultPath == vaultFile.standardizedFileURL.path }))
    }
    
    func testRegistryScannerSkipsCacheFolders() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sec-test-scan-\(UUID().uuidString)")
        let projA = tempDir.appendingPathComponent("projectA")
        let projB = tempDir.appendingPathComponent("projectB")
        let nodeModules = projA.appendingPathComponent("node_modules")
        let gitDir = projB.appendingPathComponent(".git")
        
        try? FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let validVault1 = projA.appendingPathComponent(".env.vault")
        let validVault2 = projB.appendingPathComponent("secrets.json.vault")
        let ignoredVault1 = nodeModules.appendingPathComponent("dep.vault")
        let ignoredVault2 = gitDir.appendingPathComponent("git.vault")
        
        try? "v1".write(to: validVault1, atomically: true, encoding: .utf8)
        try? "v2".write(to: validVault2, atomically: true, encoding: .utf8)
        try? "i1".write(to: ignoredVault1, atomically: true, encoding: .utf8)
        try? "i2".write(to: ignoredVault2, atomically: true, encoding: .utf8)
        
        let discovered = RegistryManager.shared.scan(directory: tempDir)
        let discoveredPaths = Set(discovered.map { $0.vaultPath })
        let expectedPath1 = validVault1.standardizedFileURL.resolvingSymlinksInPath().path
        let expectedPath2 = validVault2.standardizedFileURL.resolvingSymlinksInPath().path
        
        XCTAssertTrue(discoveredPaths.contains(expectedPath1))
        XCTAssertTrue(discoveredPaths.contains(expectedPath2))
        XCTAssertFalse(discoveredPaths.contains(ignoredVault1.path))
        XCTAssertFalse(discoveredPaths.contains(ignoredVault2.path))
        
        // Clean up test records
        RegistryManager.shared.unregister(vaultURL: validVault1)
        RegistryManager.shared.unregister(vaultURL: validVault2)
    }
    
    func testSessionManagerConfigurableDurationAndLifecycle() {
        let session = SessionManager.shared
        defer {
            session.configuredSessionDuration = nil
            session.clearSession()
        }
        
        // 1. Set 15 minutes (900 seconds)
        session.setSessionDuration(minutes: 15)
        XCTAssertEqual(session.sessionDurationSeconds, 900)
        XCTAssertFalse(session.isZeroCacheMode)
        
        // 2. Start session (after a successful authentication)
        session.authContext = LAContext()
        session.startSession()
        XCTAssertTrue(session.isSessionActive())
        
        if let remaining = session.remainingTimeSeconds() {
            XCTAssertTrue(remaining > 890 && remaining <= 900)
        } else {
            XCTFail("Expected remaining time")
        }
        
        // 3. Extend session by 5 minutes (300 seconds)
        session.extendSession(additionalSeconds: 300)
        if let extended = session.remainingTimeSeconds() {
            XCTAssertTrue(extended > 1180 && extended <= 1200)
        } else {
            XCTFail("Expected extended remaining time")
        }
        
        // 4. Clear session
        session.clearSession()
        XCTAssertFalse(session.isSessionActive())
        XCTAssertNil(session.remainingTimeSeconds())
    }
    
    func testSessionManagerZeroCacheWhenDurationZero() {
        let session = SessionManager.shared
        defer {
            session.configuredSessionDuration = nil
            session.clearSession()
        }
        
        session.setSessionDuration(seconds: 0)
        XCTAssertEqual(session.sessionDurationSeconds, 0)
        XCTAssertTrue(session.isZeroCacheMode)
        
        session.startSession()
        XCTAssertFalse(session.isSessionActive())
        XCTAssertNil(session.remainingTimeSeconds())
    }
    
    func testVaultFreshnessAndStaleDetection() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sec-test-freshness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let envFile = tempDir.appendingPathComponent(".env")
        let vaultFile = tempDir.appendingPathComponent(".env.vault")
        
        // 1. Initial vault creation
        try "FOO=BAR".write(to: envFile, atomically: true, encoding: .utf8)
        try "encrypted-vault".write(to: vaultFile, atomically: true, encoding: .utf8)
        
        // When decoy has dummy content, it is fresh
        let dummy = EnvParser.shared.generateDummyTemplate(from: "FOO=BAR", fileName: ".env")
        try dummy.write(to: envFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(VaultEngine.shared.checkVaultFreshness(vaultURL: vaultFile), .fresh)
        
        // 2. When .env is deleted, vault is orphan
        try FileManager.default.removeItem(at: envFile)
        XCTAssertEqual(VaultEngine.shared.checkVaultFreshness(vaultURL: vaultFile), .orphan(vaultURL: vaultFile))
        
        // 3. When new plaintext .env is written after vault date, vault is stale
        Thread.sleep(forTimeInterval: 0.1)
        try "NEW_SECRET=UPDATED_VAL".write(to: envFile, atomically: true, encoding: .utf8)
        let freshness = VaultEngine.shared.checkVaultFreshness(vaultURL: vaultFile)
        switch freshness {
        case .stale(let plainURL, _, _):
            XCTAssertEqual(plainURL.lastPathComponent, ".env")
        default:
            XCTFail("Expected stale vault status, got \(freshness)")
        }
    }
    
    func testAutoPrunePreservesVaultWhenDecoyRemoved() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sec-test-autoprune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let envFile = tempDir.appendingPathComponent(".env")
        let vaultFile = tempDir.appendingPathComponent(".env.vault")
        
        try "API_KEY=locked_by_sec".write(to: envFile, atomically: true, encoding: .utf8)
        try "encrypted-payload".write(to: vaultFile, atomically: true, encoding: .utf8)
        
        _ = RegistryManager.shared.autoPrune()
        RegistryManager.shared.register(vaultURL: vaultFile, plainURL: envFile)
        
        // Simulate user dragging .env to Trash or git branch switch removing .env
        try FileManager.default.removeItem(at: envFile)
        
        // autoPrune should NEVER delete the encrypted .vault file
        let (removed, _) = RegistryManager.shared.autoPrune(cleanOrphans: true)
        XCTAssertEqual(removed, 0)
        
        // Critical: Encrypted vault MUST be preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultFile.path))
        
        // When the vault file itself is deleted, autoPrune should prune the registry record
        try FileManager.default.removeItem(at: vaultFile)
        let (removedAfterVaultDeleted, _) = RegistryManager.shared.autoPrune()
        XCTAssertGreaterThanOrEqual(removedAfterVaultDeleted, 1)
        
        let loaded = RegistryManager.shared.loadRegistry()
        XCTAssertFalse(loaded.records.contains(where: { $0.vaultPath == vaultFile.standardizedFileURL.path }))
    }
    
    func testRegistryOnlyContainsValidVaultPaths() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sec-test-validity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let validEnv = tempDir.appendingPathComponent("valid.env")
        let validVault = tempDir.appendingPathComponent("valid.env.vault")
        let missingVault = tempDir.appendingPathComponent("missing.env.vault")
        let missingEnv = tempDir.appendingPathComponent("missing.env")
        
        try "VALID_SECRET=locked_by_sec".write(to: validEnv, atomically: true, encoding: .utf8)
        try "valid_vault_bytes".write(to: validVault, atomically: true, encoding: .utf8)
        
        RegistryManager.shared.register(vaultURL: validVault, plainURL: validEnv)
        RegistryManager.shared.register(vaultURL: missingVault, plainURL: missingEnv)
        
        let records = RegistryManager.shared.loadRegistry().records
        // Filter like SecAppStore does: only keep records where .vault file actually exists
        let existingOnly = records.filter { FileManager.default.fileExists(atPath: $0.vaultPath) }
        
        XCTAssertTrue(existingOnly.contains(where: { $0.vaultPath == validVault.standardizedFileURL.path }))
        XCTAssertFalse(existingOnly.contains(where: { $0.vaultPath == missingVault.standardizedFileURL.path }))
        
        // Clean up registry
        RegistryManager.shared.unregister(vaultURL: validVault)
        RegistryManager.shared.unregister(vaultURL: missingVault)
    }
    
    func testFontScalingBoundsAndStepping() {
        let minScale: CGFloat = 0.8
        let maxScale: CGFloat = 1.6
        let step: CGFloat = 0.1
        let defaultScale: CGFloat = 1.0
        
        var currentScale: CGFloat = defaultScale
        
        // Step up
        currentScale = min(maxScale, ((currentScale + step) * 10).rounded() / 10)
        XCTAssertEqual(currentScale, 1.1)
        
        // Step up to max bound
        for _ in 0..<10 {
            currentScale = min(maxScale, ((currentScale + step) * 10).rounded() / 10)
        }
        XCTAssertEqual(currentScale, maxScale)
        
        // Cannot exceed max bound
        let overMax = min(maxScale, ((currentScale + step) * 10).rounded() / 10)
        XCTAssertEqual(overMax, maxScale)
        
        // Step down to min bound
        for _ in 0..<15 {
            currentScale = max(minScale, ((currentScale - step) * 10).rounded() / 10)
        }
        XCTAssertEqual(currentScale, minScale)
        
        // Cannot go below min bound
        let underMin = max(minScale, ((currentScale - step) * 10).rounded() / 10)
        XCTAssertEqual(underMin, minScale)
        
        // Reset to default
        currentScale = defaultScale
        XCTAssertEqual(currentScale, 1.0)
        
        // Test UserDefaults persistence roundtrip
        let testKey = "sec_app_font_scale_test"
        UserDefaults.standard.set(1.3, forKey: testKey)
        let loaded = UserDefaults.standard.double(forKey: testKey)
        XCTAssertEqual(loaded, 1.3, accuracy: 0.001)
        UserDefaults.standard.removeObject(forKey: testKey)
    }
    
    func testCannotLockDecoyPlaceholder() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sec-test-nodecoy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let dummyEnv = tempDir.appendingPathComponent(".env")
        try "# PROTECTED BY sec\nAPI_KEY=locked_by_sec\n".write(to: dummyEnv, atomically: true, encoding: .utf8)
        
        do {
            _ = try await VaultEngine.shared.lock(fileURL: dummyEnv, force: true)
            XCTFail("Should have thrown cannotLockDecoyFile error")
        } catch VaultError.cannotLockDecoyFile {
            // Expected: safeguard prevents overwriting secrets with decoy dummy
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testRecoveryKeyImportNeverReplacesWorkingKey() throws {
        // Runs against the in-memory test key; must not write anything to ~/.sec.
        let exported = try KeychainManager.shared.exportRecoveryKey()
        XCTAssertFalse(exported.isEmpty)
        try KeychainManager.shared.importRecoveryKey(base64String: exported) // same key: no-op
        XCTAssertEqual(try KeychainManager.shared.exportRecoveryKey(), exported)
        
        let otherKey = Data(repeating: 9, count: 32).base64EncodedString()
        XCTAssertThrowsError(try KeychainManager.shared.importRecoveryKey(base64String: otherKey))
        XCTAssertThrowsError(try KeychainManager.shared.importRecoveryKey(base64String: "not-a-key"))
    }
    
    func testNoPlaintextMasterKeyWithoutSecureEnclave() throws {
        let manager = KeychainManager.shared
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(".sec_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let savedKey = manager.testMasterKey
        let savedContext = SessionManager.shared.authContext
        let savedDataDirectory = SecPaths.overrideForTesting
        manager.testMasterKey = nil
        SecPaths.overrideForTesting = dir
        manager.enclaveAvailableOverride = false
        SessionManager.shared.authContext = LAContext()
        defer {
            manager.testMasterKey = savedKey
            SecPaths.overrideForTesting = savedDataDirectory
            manager.enclaveAvailableOverride = nil
            SessionManager.shared.authContext = savedContext
            try? FileManager.default.removeItem(at: dir)
        }
        
        func assertEnclaveRequired(_ body: @autoclosure () throws -> Void, line: UInt = #line) {
            XCTAssertThrowsError(try body(), line: line) { error in
                guard case KeychainError.hardwareEnclaveUnavailable = error else {
                    return XCTFail("expected hardwareEnclaveUnavailable, got \(error)", line: line)
                }
            }
        }
        
        // Neither creating nor importing a key may leave any key material on disk
        assertEnclaveRequired(_ = try manager.getOrCreateMasterKey())
        assertEnclaveRequired(try manager.importRecoveryKey(base64String: Data(repeating: 7, count: 32).base64EncodedString()))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
        
        // A plaintext key left by an older version is still readable, so existing vaults keep working
        let legacyKey = Data(repeating: 3, count: 32)
        try legacyKey.write(to: dir.appendingPathComponent("master.key"))
        XCTAssertEqual(try manager.getOrCreateMasterKey(), legacyKey)
        XCTAssertEqual(try manager.getMasterKey(), legacyKey)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["master.key"])
    }
    
    func testDetectsFilePreviouslyCommittedToGit() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(".sec_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        func git(_ args: String...) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", dir.path, "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false"] + args
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        
        let committed = dir.appendingPathComponent(".env")
        let neverCommitted = dir.appendingPathComponent(".env.local")
        try "API_KEY=leaked".write(to: committed, atomically: true, encoding: .utf8)
        try "API_KEY=local".write(to: neverCommitted, atomically: true, encoding: .utf8)
        
        // Not a repository yet: nothing to report
        XCTAssertFalse(GitIgnoreManager.shared.wasEverCommitted(committed))
        
        guard try git("init", "-q") == 0, try git("add", ".env") == 0, try git("commit", "-q", "-m", "add env") == 0 else {
            throw XCTSkip("git is not usable in this environment")
        }
        XCTAssertTrue(GitIgnoreManager.shared.wasEverCommitted(committed))
        XCTAssertFalse(GitIgnoreManager.shared.wasEverCommitted(neverCommitted))
        
        // Still reported after the file is removed from the tree in a later commit
        _ = try git("rm", "-q", "--cached", ".env")
        _ = try git("commit", "-q", "-m", "untrack env")
        XCTAssertTrue(GitIgnoreManager.shared.wasEverCommitted(committed))
    }
    
    func testUnlockToDiskCreatesLocalBackup() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sec-test-unlock-bak-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let envFile = tempDir.appendingPathComponent(".env")
        let vaultFile = tempDir.appendingPathComponent(".env.vault")
        let bakFile = tempDir.appendingPathComponent(".env.vault.bak")
        
        try "DB_PASSWORD=supersecret".write(to: envFile, atomically: true, encoding: .utf8)
        
        // Lock file
        _ = try await VaultEngine.shared.lock(fileURL: envFile, force: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultFile.path))
        
        // Unlock to disk
        try await VaultEngine.shared.unlockToDisk(vaultURL: vaultFile)
        
        // Check that plain file was restored
        let plainContent = try String(contentsOf: envFile, encoding: .utf8)
        XCTAssertEqual(plainContent, "DB_PASSWORD=supersecret")
        
        // Check that backup file (.vault.bak) was preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakFile.path))
    }
    
    func testMemoryMonitorStats() {
        let memInfo = MemoryMonitor.currentProcessMemory()
        // The running test process must consume resident memory > 0
        XCTAssertGreaterThan(memInfo.residentBytes, 0)
        XCTAssertGreaterThan(memInfo.virtualBytes, 0)
        XCTAssertFalse(memInfo.formattedResident.isEmpty)
        XCTAssertFalse(memInfo.formattedVirtual.isEmpty)
    }
    
    func testProcessMemoryFormatting() {
        let sampleMB = ProcessMemoryInfo(residentBytes: 25 * 1024 * 1024, virtualBytes: 100 * 1024 * 1024)
        XCTAssertTrue(sampleMB.formattedResident.contains("25") || sampleMB.formattedResident.contains("MB"))
        
        let sampleZero = ProcessMemoryInfo(residentBytes: 0, virtualBytes: 0)
        XCTAssertTrue(sampleZero.formattedResident.localizedCaseInsensitiveContains("zero") || sampleZero.formattedResident.contains("0"))
    }
    
    func testDeterministicProjectHashing() {
        let dir1 = URL(fileURLWithPath: "/Users/test/projects/my-api")
        let dir2 = URL(fileURLWithPath: "/Users/test/projects/my-api")
        let dir3 = URL(fileURLWithPath: "/Users/test/projects/other-api")
        
        let hash1 = BackupEngine.deterministicProjectHash(for: dir1)
        let hash2 = BackupEngine.deterministicProjectHash(for: dir2)
        let hash3 = BackupEngine.deterministicProjectHash(for: dir3)
        
        XCTAssertEqual(hash1, hash2, "Identical project paths must produce identical hashes")
        XCTAssertNotEqual(hash1, hash3, "Different project paths must produce different hashes")
        XCTAssertFalse(hash1.isEmpty)
    }
    
    func testMultiVersionSnapshotCreationAndRollback() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let envFile = tempDir.appendingPathComponent(".env")
        try "API_KEY=v1_initial_secret".write(to: envFile, atomically: true, encoding: .utf8)
        
        // Lock to create initial vault
        _ = try await VaultEngine.shared.lock(fileURL: envFile)
        let vaultFile = tempDir.appendingPathComponent(".env.vault")
        
        // Create manual snapshot v1
        let snap1 = try await BackupEngine.shared.createSnapshot(for: vaultFile, trigger: .manual, note: "Initial snapshot")
        XCTAssertEqual(snap1.version, 1)
        XCTAssertEqual(snap1.targetFileName, ".env")
        
        // Update vault with v2 secret
        let v2Plain = "API_KEY=v2_modified_secret".data(using: .utf8)!
        try await VaultEngine.shared.updateVault(vaultURL: vaultFile, plaintextData: v2Plain)
        
        // Create snapshot v2
        let snap2 = try await BackupEngine.shared.createSnapshot(for: vaultFile, trigger: .manual, note: "Updated secret")
        XCTAssertGreaterThan(snap2.version, snap1.version)
        
        // Verify current decrypted secret is v2
        let currentSecrets = try await VaultEngine.shared.readDecryptedSecrets(vaultURL: vaultFile)
        XCTAssertEqual(currentSecrets["API_KEY"], "v2_modified_secret")
        
        // Rollback to v1
        try await BackupEngine.shared.restoreSnapshot(snapshotId: snap1.id)
        
        // Verify decrypted secret was rolled back to v1
        let rolledBackSecrets = try await VaultEngine.shared.readDecryptedSecrets(vaultURL: vaultFile)
        XCTAssertEqual(rolledBackSecrets["API_KEY"], "v1_initial_secret")
        
        // Cleanup snapshot files created in ~/.sec/backups
        try? BackupEngine.shared.deleteSnapshot(snapshotId: snap1.id)
        try? BackupEngine.shared.deleteSnapshot(snapshotId: snap2.id)
    }
    
    func testTamperedBackupIndexRecordsAreRejected() {
        let uuidName = "\(UUID().uuidString).vault"
        XCTAssertTrue(BackupEngine.isValidStoredFileName(uuidName))
        for name in ["../../x.vault", "sub/\(uuidName)", "..", "x.vault", uuidName + "/..", ""] {
            XCTAssertFalse(BackupEngine.isValidStoredFileName(name), name)
        }
        
        XCTAssertTrue(BackupEngine.isValidProjectHash(BackupEngine.deterministicProjectHash(for: URL(fileURLWithPath: "/tmp/project"))))
        for hash in ["../../../etc", "ABCDEF0123456789", "abc", "0123456789abcde/"] {
            XCTAssertFalse(BackupEngine.isValidProjectHash(hash), hash)
        }
        
        XCTAssertTrue(BackupEngine.isValidVaultPath("/Users/me/app/.env.vault"))
        for path in ["/Users/me/.zshrc", "relative/.env.vault", "/Users/me/app/../../.ssh/x.vault"] {
            XCTAssertFalse(BackupEngine.isValidVaultPath(path), path)
        }
        
        func trash(_ vaultPath: String, _ plainPath: String, _ file: String) -> TrashRecord {
            TrashRecord(vaultPath: vaultPath, plainPath: plainPath, projectName: "app", projectPath: "/Users/me/app", targetFileName: ".env", trashFileName: file)
        }
        XCTAssertTrue(BackupEngine.isValid(trash("/Users/me/app/.env.vault", "/Users/me/app/.env", uuidName)))
        // Decoy target redirected away from the vault, or payload name escaping the trash directory
        XCTAssertFalse(BackupEngine.isValid(trash("/Users/me/app/.env.vault", "/Users/me/.zshrc", uuidName)))
        XCTAssertFalse(BackupEngine.isValid(trash("/Users/me/app/.env.vault", "/Users/me/app/.env", "../vaults.json")))
    }
    
    func testEditorSelectionAvoidsAIEditorsByDefault() {
        // No $EDITOR in a terminal: a terminal editor, never an IDE picked implicitly
        let terminalDefault = EditorEngine.shared.resolveEditor(environment: [:], hasTerminal: true)
        XCTAssertTrue(["nano", "vim"].contains(terminalDefault))
        XCTAssertFalse(EditorEngine.isAIEnabledEditor(terminalDefault))
        
        // An explicit choice is honoured, gets a wait flag when needed, and is flagged as AI-enabled
        XCTAssertEqual(EditorEngine.shared.resolveEditor(environment: ["EDITOR": "cursor"], hasTerminal: true), "cursor --wait")
        XCTAssertEqual(EditorEngine.shared.resolveEditor(environment: ["EDITOR": "/opt/homebrew/bin/code -w"], hasTerminal: true), "/opt/homebrew/bin/code -w")
        XCTAssertEqual(EditorEngine.shared.resolveEditor(environment: ["VISUAL": "vim"], hasTerminal: false), "vim")
        XCTAssertTrue(EditorEngine.isAIEnabledEditor("cursor --wait"))
        XCTAssertTrue(EditorEngine.isAIEnabledEditor("/opt/homebrew/bin/code -w"))
        XCTAssertFalse(EditorEngine.isAIEnabledEditor("vim"))
        XCTAssertFalse(EditorEngine.isAIEnabledEditor("/usr/bin/nano"))
    }
    
    func testEditBufferIsPrivateAndRemoved() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(".sec_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let envFile = dir.appendingPathComponent("config.env")
        try "API_KEY=before_edit".write(to: envFile, atomically: true, encoding: .utf8)
        _ = try await VaultEngine.shared.lock(fileURL: envFile)
        let vaultFile = dir.appendingPathComponent("config.env.vault")
        
        // A scripted "editor" that records what it was given, then appends a secret
        let report = dir.appendingPathComponent("report.txt")
        let editor = dir.appendingPathComponent("fake-editor.sh")
        try """
        #!/bin/sh
        { stat -f '%Lp' "$1"; stat -f '%Lp' "$(dirname "$1")"; echo "$1"; } > '\(report.path)'
        printf '\\nADDED=by_editor\\n' >> "$1"
        """.write(to: editor, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: editor.path)
        
        let previousEditor = ProcessInfo.processInfo.environment["EDITOR"]
        setenv("EDITOR", editor.path, 1)
        defer {
            if let previous = previousEditor { setenv("EDITOR", previous, 1) } else { unsetenv("EDITOR") }
        }
        
        try await EditorEngine.shared.edit(vaultURL: vaultFile)
        
        let lines = try String(contentsOf: report, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "600", "buffer must be owner-only")
        XCTAssertEqual(lines[1], "700", "buffer directory must be owner-only")
        XCTAssertTrue(lines[2].hasSuffix("/config.env"), "buffer keeps the real file name")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lines[2]), "buffer must be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: lines[2]).deletingLastPathComponent().path))
        
        let secrets = try await VaultEngine.shared.readDecryptedSecrets(vaultURL: vaultFile)
        XCTAssertEqual(secrets["API_KEY"], "before_edit")
        XCTAssertEqual(secrets["ADDED"], "by_editor")
        XCTAssertFalse(try String(contentsOf: envFile, encoding: .utf8).contains("by_editor"))
    }
    
    func testVaultDiscoveryStaysInsideTheProject() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(".sec_test_\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        func mkdir(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func touch(_ url: URL) throws { try "x".write(to: url, atomically: true, encoding: .utf8) }
        
        // workspace/ holds a lone odd-named vault; repo/ is a separate git repository below it
        let workspace = try mkdir("workspace")
        try touch(workspace.appendingPathComponent("other-project.yaml.vault"))
        let repo = try mkdir("workspace/repo")
        _ = try mkdir("workspace/repo/.git")
        let package = try mkdir("workspace/repo/packages/backend")
        
        // From the repo root or below it, the unrelated vault above the repository is never picked up
        XCTAssertNil(VaultEngine.shared.findNearestVault(startingAt: repo))
        XCTAssertNil(VaultEngine.shared.findNearestVault(startingAt: package))
        
        // Monorepo traversal still finds the repository's own vault, standard or lone
        try touch(repo.appendingPathComponent("secrets.json.vault"))
        XCTAssertEqual(VaultEngine.shared.findNearestVault(startingAt: package)?.lastPathComponent, "secrets.json.vault")
        try touch(repo.appendingPathComponent(".env.vault"))
        XCTAssertEqual(VaultEngine.shared.findNearestVault(startingAt: package)?.path, repo.appendingPathComponent(".env.vault").path)
        
        // Outside any repository, a lone odd-named vault further up is ignored, a standard one is found
        let loose = try mkdir("workspace/notes/drafts")
        XCTAssertNil(VaultEngine.shared.findNearestVault(startingAt: loose))
        try touch(workspace.appendingPathComponent(".env.vault"))
        XCTAssertEqual(VaultEngine.shared.findNearestVault(startingAt: loose)?.path, workspace.appendingPathComponent(".env.vault").path)
    }
    
    func testRunnerPassesArgumentsVerbatimAndClassifiesByName() throws {
        // Arguments that the old quoting re-interpreted (expansion, command separators, quotes, globs)
        let hostile = ["a b", "say \"hi\"", "$HOME", "`id`", "$(id)", "x; echo pwned", "*", "back\\slash", "it's"]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ProcessRunner.shellArguments(for: ["/usr/bin/printf", "%s\\n"] + hostile, viaShell: false)
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        XCTAssertEqual(output, hostile.joined(separator: "\n") + "\n")
        
        XCTAssertEqual(ProcessRunner.shellArguments(for: ["npm run build && npm start"], viaShell: true), ["-c", "npm run build && npm start"])
        
        // "$@" is POSIX syntax: a fish or nushell login shell must not be handed it
        XCTAssertEqual(ProcessRunner.shellPath(userShell: "/opt/homebrew/bin/fish", viaShell: false), "/bin/zsh")
        XCTAssertEqual(ProcessRunner.shellPath(userShell: "/opt/homebrew/bin/fish", viaShell: true), "/opt/homebrew/bin/fish")
        XCTAssertEqual(ProcessRunner.shellPath(userShell: "/bin/bash", viaShell: false), "/bin/bash")
        XCTAssertEqual(ProcessRunner.shellPath(userShell: nil, viaShell: false), "/bin/zsh")
        
        XCTAssertEqual(ProcessRunner.runtime(for: ["npm", "run", "dev"]), .node)
        XCTAssertEqual(ProcessRunner.runtime(for: ["/opt/homebrew/bin/node", "server.js"]), .node)
        XCTAssertEqual(ProcessRunner.runtime(for: ["python3.12", "app.py"]), .python)
        XCTAssertEqual(ProcessRunner.runtime(for: ["./manage.py", "runserver"]), .python)
        // Substring matches that used to get the wrong loader
        XCTAssertEqual(ProcessRunner.runtime(for: ["nodeenv"]), .other)
        XCTAssertEqual(ProcessRunner.runtime(for: ["/Users/me/node_modules/.bin/eslint"]), .other)
        XCTAssertEqual(ProcessRunner.runtime(for: ["cargo", "run"]), .other)
    }
    
    func testTrashSoftDeleteAndRestoration() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let envFile = tempDir.appendingPathComponent(".env")
        try "PAYLOAD=trash_test_secret".write(to: envFile, atomically: true, encoding: .utf8)
        
        _ = try await VaultEngine.shared.lock(fileURL: envFile)
        let vaultFile = tempDir.appendingPathComponent(".env.vault")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultFile.path))
        
        // Move to trash
        let trashRecord = try await BackupEngine.shared.moveToTrash(vaultURL: vaultFile, reason: "Test soft delete")
        XCTAssertEqual(trashRecord.targetFileName, ".env")
        XCTAssertTrue(FileManager.default.fileExists(atPath: BackupEngine.shared.trashFileURL(for: trashRecord).path))
        
        // Simulate removing original vault
        try? FileManager.default.removeItem(at: vaultFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultFile.path))
        
        // Restore from trash
        let restoredURL = try await BackupEngine.shared.restoreFromTrash(trashId: trashRecord.id)
        XCTAssertEqual(restoredURL.path, vaultFile.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultFile.path))
        
        // Verify secrets are intact
        let secrets = try await VaultEngine.shared.readDecryptedSecrets(vaultURL: vaultFile)
        XCTAssertEqual(secrets["PAYLOAD"], "trash_test_secret")
    }
    
    func testSnapshotPruningRetentionLimit() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let envFile = tempDir.appendingPathComponent(".env")
        try "COUNTER=0".write(to: envFile, atomically: true, encoding: .utf8)
        _ = try await VaultEngine.shared.lock(fileURL: envFile)
        let vaultFile = tempDir.appendingPathComponent(".env.vault")
        
        // Create 1 manual snapshot
        let manualSnap = try await BackupEngine.shared.createSnapshot(for: vaultFile, trigger: .manual, note: "Manual backup")
        
        // Create 27 automatic snapshots (limit is 25)
        var autoIds: [UUID] = []
        for i in 1...27 {
            let snap = try await BackupEngine.shared.createSnapshot(for: vaultFile, trigger: .autoSnapshot, note: "Auto \(i)")
            autoIds.append(snap.id)
        }
        
        let projectSnapshots = BackupEngine.shared.listSnapshots(for: tempDir)
        // Manual snapshot must still exist
        XCTAssertTrue(projectSnapshots.contains(where: { $0.id == manualSnap.id }))
        
        // Total auto snapshots should be capped at maxAutomaticSnapshotsPerFile (25)
        let autoCount = projectSnapshots.filter { $0.trigger != .manual }.count
        XCTAssertLessThanOrEqual(autoCount, BackupEngine.maxAutomaticSnapshotsPerFile)
        
        // Clean up test snapshots
        for s in projectSnapshots {
            try? BackupEngine.shared.deleteSnapshot(snapshotId: s.id)
        }
    }
    
    func testRegistryExcludesBackupAndTrashVaults() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 1. Real project vault
        let projectDir = tempDir.appendingPathComponent("my_project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectVault = projectDir.appendingPathComponent(".env.vault")
        try "dummy-vault-data".write(to: projectVault, atomically: true, encoding: .utf8)
        
        // 2. Backup vault in ~/.sec/backups simulation
        let backupDir = tempDir.appendingPathComponent(".sec").appendingPathComponent("backups").appendingPathComponent("abc123hash")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backupVault = backupDir.appendingPathComponent("snapshot-uuid.vault")
        try "backup-vault-data".write(to: backupVault, atomically: true, encoding: .utf8)
        
        // 3. Trash vault
        let trashDir = tempDir.appendingPathComponent(".sec").appendingPathComponent("trash")
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trashVault = trashDir.appendingPathComponent("trashed-uuid.vault")
        try "trash-vault-data".write(to: trashVault, atomically: true, encoding: .utf8)
        
        // 4. Temporary backup file .vault.bak
        let bakVault = projectDir.appendingPathComponent(".env.vault.bak")
        try "bak-data".write(to: bakVault, atomically: true, encoding: .utf8)
        
        // Scan the entire temp root
        let discovered = RegistryManager.shared.scan(directory: tempDir)
        
        // Verify only the real project vault was discovered
        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered.first?.vaultPath, projectVault.resolvingSymlinksInPath().path)
        
        // Verify register() strictly rejects any .sec or .bak files
        RegistryManager.shared.register(vaultURL: backupVault, plainURL: backupVault)
        RegistryManager.shared.register(vaultURL: trashVault, plainURL: trashVault)
        RegistryManager.shared.register(vaultURL: bakVault, plainURL: bakVault)
        
        let registry = RegistryManager.shared.loadRegistry()
        XCTAssertFalse(registry.records.contains(where: { $0.vaultPath.contains("/.sec/") }))
        XCTAssertFalse(registry.records.contains(where: { $0.vaultPath.hasSuffix(".vault.bak") }))
    }
}


