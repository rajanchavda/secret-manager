import XCTest
@testable import sec

final class SecTests: XCTestCase {
    
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
}


