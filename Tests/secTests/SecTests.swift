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
}
