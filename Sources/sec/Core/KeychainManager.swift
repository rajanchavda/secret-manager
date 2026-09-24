import Foundation
import CryptoKit

public enum KeychainError: LocalizedError {
    case itemNotFound
    case hardwareEnclaveUnavailable
    case generationFailed(String)
    case derivationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Hardware master key not found. Run 'sec lock' to initialize."
        case .hardwareEnclaveUnavailable:
            return "Secure Enclave hardware is not available on this machine."
        case .generationFailed(let msg):
            return "Failed to generate Secure Enclave hardware key: \(msg)"
        case .derivationFailed(let msg):
            return "Failed to derive 256-bit AES master key: \(msg)"
        }
    }
}

/// HardwareKeyManager manages the master encryption key backed by Apple's Secure Enclave hardware chip.
/// Completely avoids legacy macOS login.keychain password dialogs while providing true hardware-level security.
public final class KeychainManager {
    public static let shared = KeychainManager()
    
    private let salt = "sec-vault-master-salt-v1".data(using: .utf8)!
    
    private var secDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".sec", isDirectory: true)
    }
    
    private var tokenFileURL: URL {
        return secDirectory.appendingPathComponent("enclave.token")
    }
    
    private var fallbackKeyURL: URL {
        return secDirectory.appendingPathComponent("master.key")
    }
    
    private init() {
        ensureSecDirectory()
    }
    
    private func ensureSecDirectory() {
        let path = secDirectory.path
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(at: secDirectory, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }
    }
    
    /// Checks if a master key token exists on the system
    public func hasMasterKey() -> Bool {
        return FileManager.default.fileExists(atPath: tokenFileURL.path) ||
               FileManager.default.fileExists(atPath: fallbackKeyURL.path)
    }
    
    /// Retrieves the 256-bit AES master key, creating one if it does not yet exist
    public func getOrCreateMasterKey() throws -> Data {
        if hasMasterKey() {
            return try getMasterKey()
        }
        
        ensureSecDirectory()
        
        if SecureEnclave.isAvailable {
            do {
                let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()
                let tokenData = enclaveKey.dataRepresentation
                try tokenData.write(to: tokenFileURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFileURL.path)
                return try deriveSymmetricKey(from: enclaveKey)
            } catch {
                throw KeychainError.generationFailed(error.localizedDescription)
            }
        } else {
            // Software fallback for Intel machines without Secure Enclave
            var keyBytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
            let keyData = Data(keyBytes)
            try keyData.write(to: fallbackKeyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fallbackKeyURL.path)
            return keyData
        }
    }
    
    /// Retrieves existing master key derived from Secure Enclave hardware
    public func getMasterKey() throws -> Data {
        ensureSecDirectory()
        
        if FileManager.default.fileExists(atPath: tokenFileURL.path) {
            guard let tokenData = try? Data(contentsOf: tokenFileURL) else {
                throw KeychainError.itemNotFound
            }
            
            do {
                let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: tokenData)
                return try deriveSymmetricKey(from: enclaveKey)
            } catch {
                throw KeychainError.derivationFailed(error.localizedDescription)
            }
        } else if FileManager.default.fileExists(atPath: fallbackKeyURL.path) {
            guard let keyData = try? Data(contentsOf: fallbackKeyURL), keyData.count == 32 else {
                throw KeychainError.itemNotFound
            }
            return keyData
        } else {
            throw KeychainError.itemNotFound
        }
    }
    
    /// Derives a 256-bit symmetric AES key from the Secure Enclave hardware key agreement using HKDF
    private func deriveSymmetricKey(from enclaveKey: SecureEnclave.P256.KeyAgreement.PrivateKey) throws -> Data {
        do {
            let sharedSecret = try enclaveKey.sharedSecretFromKeyAgreement(with: enclaveKey.publicKey)
            let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: salt,
                sharedInfo: Data(),
                outputByteCount: 32
            )
            return symmetricKey.withUnsafeBytes { Data($0) }
        } catch {
            throw KeychainError.derivationFailed(error.localizedDescription)
        }
    }
    
    /// Deletes the master key token (used for reset)
    public func deleteMasterKey() throws {
        try? FileManager.default.removeItem(at: tokenFileURL)
        try? FileManager.default.removeItem(at: fallbackKeyURL)
    }
}
