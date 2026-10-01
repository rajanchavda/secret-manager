import Foundation
import CryptoKit

public enum CryptoError: LocalizedError {
    case invalidKeySize
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidEnvelopeFormat
    
    public var errorDescription: String? {
        switch self {
        case .invalidKeySize:
            return "Encryption key must be 32 bytes (256 bits)."
        case .encryptionFailed(let msg):
            return "Encryption error: \(msg)"
        case .decryptionFailed(let msg):
            return "Decryption error (authentication failed or corrupted data): \(msg)"
        case .invalidEnvelopeFormat:
            return "The vault file format is invalid or corrupted."
        }
    }
}

public struct VaultEnvelope: Codable {
    public let version: Int
    public let cipher: String
    public let nonce: String
    public let tag: String
    public let ciphertext: String
    public let createdAt: String
    
    public init(nonce: Data, tag: Data, ciphertext: Data) {
        self.version = 1
        self.cipher = "aes-256-gcm"
        self.nonce = nonce.base64EncodedString()
        self.tag = tag.base64EncodedString()
        self.ciphertext = ciphertext.base64EncodedString()
        let formatter = ISO8601DateFormatter()
        self.createdAt = formatter.string(from: Date())
    }
}

public final class CryptoEngine {
    public static let shared = CryptoEngine()
    
    private init() {}
    
    /// Encrypts plaintext data with AES-256-GCM using the 256-bit symmetric key, returning JSON-encoded VaultEnvelope
    public func encrypt(plaintext: Data, keyData: Data) throws -> Data {
        guard keyData.count == 32 else {
            throw CryptoError.invalidKeySize
        }
        let symmetricKey = SymmetricKey(data: keyData)
        
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)
            let nonceData = Data(sealedBox.nonce)
            let tagData = sealedBox.tag
            let ciphertextData = sealedBox.ciphertext
            
            let envelope = VaultEnvelope(nonce: nonceData, tag: tagData, ciphertext: ciphertextData)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(envelope)
        } catch {
            throw CryptoError.encryptionFailed(error.localizedDescription)
        }
    }
    
    /// Decrypts VaultEnvelope JSON data with AES-256-GCM using the 256-bit symmetric key
    public func decrypt(vaultData: Data, keyData: Data) throws -> Data {
        guard keyData.count == 32 else {
            throw CryptoError.invalidKeySize
        }
        let symmetricKey = SymmetricKey(data: keyData)
        
        let envelope: VaultEnvelope
        do {
            envelope = try JSONDecoder().decode(VaultEnvelope.self, from: vaultData)
        } catch {
            throw CryptoError.invalidEnvelopeFormat
        }
        
        guard let nonceData = Data(base64Encoded: envelope.nonce),
              let tagData = Data(base64Encoded: envelope.tag),
              let ciphertextData = Data(base64Encoded: envelope.ciphertext) else {
            throw CryptoError.invalidEnvelopeFormat
        }
        
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw CryptoError.decryptionFailed(error.localizedDescription)
        }
    }
}
