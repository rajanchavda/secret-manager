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
}

