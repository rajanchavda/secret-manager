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
        
        let dummy = EnvParser.shared.generateDummyTemplate(from: envContent)
        XCTAssertTrue(dummy.contains("API_SECRET=locked_by_sec"))
        XCTAssertTrue(dummy.contains("JWT_TOKEN=locked_by_sec"))
        XCTAssertFalse(dummy.contains("super-secret-value"))
        XCTAssertFalse(dummy.contains("ey12345"))
    }
    
    func testVaultURLDerivation() {
        let plain = URL(fileURLWithPath: "/path/to/.env")
        let vault = VaultEngine.shared.vaultURL(for: plain)
        XCTAssertEqual(vault.lastPathComponent, ".env.vault")
        
        let restored = VaultEngine.shared.plainFileURL(for: vault)
        XCTAssertEqual(restored.lastPathComponent, ".env")
    }
}
