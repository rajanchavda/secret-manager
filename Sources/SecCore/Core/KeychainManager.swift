import Foundation
import CryptoKit
import LocalAuthentication

public enum KeychainError: LocalizedError {
    case itemNotFound
    case hardwareEnclaveUnavailable
    case generationFailed(String)
    case derivationFailed(String)
    case masterKeyMissingWithExistingVaults(Int)
    case invalidRecoveryKey
    case differentMasterKeyExists
    case authenticationRequired
    
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
            return "Master key not found in ~/.sec, but \(count) existing encrypted vault(s) were found on this system. Creating a new key would permanently prevent decrypting those vaults. Restore your ~/.sec/master.wrapped or run 'sec import-key' with your recovery key."
        case .invalidRecoveryKey:
            return "The provided recovery key is invalid. It must be a valid Base64-encoded 256-bit (32-byte) key."
        case .differentMasterKeyExists:
            return "A different working master key already exists in ~/.sec. Importing would make vaults encrypted with it unreadable, so the import was refused."
        case .authenticationRequired:
            return "Touch ID or your Mac password is required to import a master key. Nothing was changed."
        }
    }
}

/// On-disk form of the master key: sealed to a Secure Enclave key that requires
/// Touch ID or the Mac password for every use. The file alone is useless to other processes.
struct WrappedMasterKey: Codable {
    let version: Int
    let enclaveKey: Data          // Secure Enclave key blob, only usable on this Mac's enclave
    let ephemeralPublicKey: Data  // x963
    let sealedKey: Data           // AES.GCM combined box holding the 32-byte master key
}

/// HardwareKeyManager manages the master encryption key backed by Apple's Secure Enclave hardware chip.
/// Completely avoids legacy macOS login.keychain password dialogs while providing true hardware-level security.
public final class KeychainManager {
    public static let shared = KeychainManager()
    
    private let salt = "sec-vault-master-salt-v1".data(using: .utf8)!
    private static let wrapSalt = "sec-master-key-wrap-v1".data(using: .utf8)!
    
    /// Replaces the real master key. Set only from the test suite via `@testable import`.
    internal var testMasterKey: Data?
    
    private var secDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".sec", isDirectory: true)
    }
    
    private var wrappedKeyURL: URL {
        return secDirectory.appendingPathComponent("master.wrapped")
    }
    
    /// Legacy Secure Enclave key created without access control. Migrated to `master.wrapped`.
    private var tokenFileURL: URL {
        return secDirectory.appendingPathComponent("enclave.token")
    }
    
    /// Plaintext key: Intel fallback, or legacy import. Migrated to `master.wrapped` when an enclave exists.
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
        let fm = FileManager.default
        return fm.fileExists(atPath: wrappedKeyURL.path) ||
               fm.fileExists(atPath: tokenFileURL.path) ||
               fm.fileExists(atPath: fallbackKeyURL.path)
    }
    
    /// Retrieves the 256-bit AES master key, creating one if it does not yet exist
    public func getOrCreateMasterKey() throws -> Data {
        if testMasterKey != nil || hasMasterKey() {
            return try getMasterKey()
        }
        
        // Prevent silent key generation if existing vaults exist on disk
        let records = RegistryManager.shared.loadRegistry().records
        let existingVaults = records.filter { FileManager.default.fileExists(atPath: $0.vaultPath) }
        if !existingVaults.isEmpty {
            throw KeychainError.masterKeyMissingWithExistingVaults(existingVaults.count)
        }
        
        ensureSecDirectory()
        
        var keyBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes) == errSecSuccess else {
            throw KeychainError.generationFailed("Secure random generator failed")
        }
        let keyData = Data(keyBytes)
        
        if SecureEnclave.isAvailable {
            try storeWrapped(keyData)
        } else {
            // Software fallback for Intel machines without Secure Enclave
            try keyData.write(to: fallbackKeyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fallbackKeyURL.path)
        }
        return keyData
    }
    
    /// Retrieves the master key. Unsealing requires Touch ID / Mac password, enforced by the
    /// Secure Enclave itself; the context from the last `BiometricAuth` prompt avoids a second prompt.
    public func getMasterKey() throws -> Data {
        if let testKey = testMasterKey {
            return testKey
        }
        ensureSecDirectory()
        
        if FileManager.default.fileExists(atPath: wrappedKeyURL.path) {
            guard let data = try? Data(contentsOf: wrappedKeyURL),
                  let wrapped = try? JSONDecoder().decode(WrappedMasterKey.self, from: data) else {
                throw KeychainError.itemNotFound
            }
            let key = try Self.open(wrapped, context: SessionManager.shared.authContext)
            removeLegacyKeyFiles(ifMatching: key)
            return key
        }
        
        guard let legacyKey = try legacyMasterKey() else {
            throw KeychainError.itemNotFound
        }
        // ponytail: Intel Macs keep the plaintext master.key (no enclave to seal to).
        guard SecureEnclave.isAvailable else {
            return legacyKey
        }
        // One-time migration: re-seal the same key so vaults, snapshots and recovery keys keep
        // working. The recursive call unseals it (proving the wrapper works) before legacy files go.
        try storeWrapped(legacyKey)
        return try getMasterKey()
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
        // Never replace a working key: vaults encrypted with it would become unreadable.
        // Old key files are left in place; getMasterKey removes them only if they match.
        if hasMasterKey() || testMasterKey != nil, let currentKey = try? getMasterKey() {
            guard currentKey == keyData else {
                throw KeychainError.differentMasterKeyExists
            }
            return // Already the active key
        }
        // Installing a key needs a fresh Touch ID / password approval. Without it, a cancelled
        // unseal prompt above would look like "no readable key" and let the import swap it out.
        guard SessionManager.shared.authContext != nil else {
            throw KeychainError.authenticationRequired
        }
        ensureSecDirectory()
        if SecureEnclave.isAvailable {
            preserveExisting(wrappedKeyURL)
            try storeWrapped(keyData)
        } else {
            preserveExisting(fallbackKeyURL)
            try keyData.write(to: fallbackKeyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fallbackKeyURL.path)
        }
    }

    /// Seals the master key to a new Secure Enclave key that requires user presence for every use.
    /// Only the enclave's public key is needed here, so sealing never prompts.
    static func seal(_ masterKey: Data) throws -> WrappedMasterKey {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            &error
        ) else {
            let msg = error?.takeRetainedValue().localizedDescription ?? "Could not create access control"
            throw KeychainError.generationFailed(msg)
        }
        do {
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
            let ephemeral = P256.KeyAgreement.PrivateKey()
            let kek = try wrappingKey(ephemeral.sharedSecretFromKeyAgreement(with: enclaveKey.publicKey), ephemeral.publicKey)
            guard let sealed = try AES.GCM.seal(masterKey, using: kek).combined else {
                throw KeychainError.generationFailed("AES-GCM seal failed")
            }
            return WrappedMasterKey(
                version: 1,
                enclaveKey: enclaveKey.dataRepresentation,
                ephemeralPublicKey: ephemeral.publicKey.x963Representation,
                sealedKey: sealed
            )
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.generationFailed(error.localizedDescription)
        }
    }
    
    /// Unseals the master key. The Secure Enclave refuses unless `context` is authenticated
    /// (or, if nil, shows its own Touch ID / password prompt).
    static func open(_ wrapped: WrappedMasterKey, context: LAContext?) throws -> Data {
        do {
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: wrapped.enclaveKey,
                authenticationContext: context
            )
            let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: wrapped.ephemeralPublicKey)
            let kek = try wrappingKey(enclaveKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey), ephemeralPublicKey)
            let key = try AES.GCM.open(AES.GCM.SealedBox(combined: wrapped.sealedKey), using: kek)
            guard key.count == 32 else {
                throw KeychainError.derivationFailed("Unsealed master key has invalid length")
            }
            return key
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.derivationFailed("Secure Enclave refused to unseal the master key (\(error.localizedDescription)). Touch ID or your Mac password is required.")
        }
    }
    
    private static func wrappingKey(_ sharedSecret: SharedSecret, _ ephemeralPublicKey: P256.KeyAgreement.PublicKey) -> SymmetricKey {
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: wrapSalt,
            sharedInfo: ephemeralPublicKey.x963Representation,
            outputByteCount: 32
        )
    }
    
    private func storeWrapped(_ masterKey: Data) throws {
        let data = try JSONEncoder().encode(Self.seal(masterKey))
        try data.write(to: wrappedKeyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: wrappedKeyURL.path)
    }
    
    /// Reads the pre-wrapping key (`enclave.token` or `master.key`), or nil if neither exists.
    private func legacyMasterKey() throws -> Data? {
        let fm = FileManager.default
        if fm.fileExists(atPath: tokenFileURL.path) {
            guard let tokenData = try? Data(contentsOf: tokenFileURL) else {
                throw KeychainError.itemNotFound
            }
            do {
                let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: tokenData)
                return try deriveSymmetricKey(from: enclaveKey)
            } catch {
                if let keyData = try? Data(contentsOf: fallbackKeyURL), keyData.count == 32 {
                    return keyData
                }
                throw KeychainError.derivationFailed("Secure Enclave key agreement failed (\(error.localizedDescription)). This token may be bound to a different physical Mac. If you migrated to a new Mac, import your recovery key using 'sec import-key'.")
            }
        }
        if fm.fileExists(atPath: fallbackKeyURL.path) {
            guard let keyData = try? Data(contentsOf: fallbackKeyURL), keyData.count == 32 else {
                throw KeychainError.itemNotFound
            }
            return keyData
        }
        return nil
    }
    
    /// Legacy files let any process derive the key without Touch ID. Delete them once the
    /// sealed copy is proven to hold the same key; keep them if they differ, to avoid data loss.
    private func removeLegacyKeyFiles(ifMatching key: Data) {
        // Each file is checked on its own: a master.key holding a different key than
        // enclave.token may still be the only copy able to decrypt some older vault.
        if let tokenData = try? Data(contentsOf: tokenFileURL),
           let enclaveKey = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: tokenData),
           let derived = try? deriveSymmetricKey(from: enclaveKey), derived == key {
            try? FileManager.default.removeItem(at: tokenFileURL)
        }
        if let plainKey = try? Data(contentsOf: fallbackKeyURL), plainKey == key {
            try? FileManager.default.removeItem(at: fallbackKeyURL)
        }
    }

    /// Moves a key file aside instead of overwriting it, so key material that could not be
    /// read right now (cancelled prompt, other Mac) is never destroyed.
    private func preserveExisting(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("replaced-\(stamp)"))
    }
    
    /// Derives a 256-bit symmetric AES key from a legacy Secure Enclave token using HKDF
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
        try? FileManager.default.removeItem(at: wrappedKeyURL)
        try? FileManager.default.removeItem(at: tokenFileURL)
        try? FileManager.default.removeItem(at: fallbackKeyURL)
    }
}
