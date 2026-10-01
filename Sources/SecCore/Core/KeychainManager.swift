import Foundation
import CryptoKit

public enum KeychainError: LocalizedError {
    case itemNotFound
    case hardwareEnclaveUnavailable
    case generationFailed(String)
    case derivationFailed(String)
    case masterKeyMissingWithExistingVaults(Int)
    case invalidRecoveryKey
    
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
        case .masterKeyMissingWithExistingVaults(let count):
            return "Master key not found at ~/.sec/enclave.token, but \(count) existing encrypted vault(s) were found on this system. Creating a new key would permanently prevent decrypting those vaults. Restore your ~/.sec/enclave.token or run 'sec import-key' with your recovery key."
        case .invalidRecoveryKey:
            return "The provided recovery key is invalid. It must be a valid Base64-encoded 256-bit (32-byte) key."
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
        
        // Prevent silent key generation if existing vaults exist on disk
        let records = RegistryManager.shared.loadRegistry().records
        let existingVaults = records.filter { FileManager.default.fileExists(atPath: $0.vaultPath) }
        if !existingVaults.isEmpty {
            throw KeychainError.masterKeyMissingWithExistingVaults(existingVaults.count)
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
                if FileManager.default.fileExists(atPath: fallbackKeyURL.path),
                   let keyData = try? Data(contentsOf: fallbackKeyURL), keyData.count == 32 {
                    return keyData
                }
                throw KeychainError.derivationFailed("Secure Enclave key agreement failed (\(error.localizedDescription)). This token may be bound to a different physical Mac. If you migrated to a new Mac, import your recovery key using 'sec import-key'.")
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
    
    /// Exports the master key encoded as Base64 for disaster recovery (e.g. migrating to a new Mac)
    public func exportRecoveryKey() throws -> String {
        let key = try getMasterKey()
        return key.base64EncodedString()
    }
    
    /// Imports a previously exported master key for disaster recovery
    public func importRecoveryKey(base64String: String) throws {
        guard let keyData = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)),
              keyData.count == 32 else {
            throw KeychainError.invalidRecoveryKey
        }
        ensureSecDirectory()
        try keyData.write(to: fallbackKeyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fallbackKeyURL.path)
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
