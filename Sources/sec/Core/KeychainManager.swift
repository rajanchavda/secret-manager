import Foundation
import Security

public enum KeychainError: LocalizedError {
    case duplicateItem
    case itemNotFound
    case unhandledError(status: OSStatus)
    case invalidKeyData
    
    public var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "Item already exists in Keychain."
        case .itemNotFound:
            return "Master key not found in Keychain."
        case .unhandledError(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "Keychain error (\(status)): \(msg)"
        case .invalidKeyData:
            return "Invalid key data retrieved from Keychain."
        }
    }
}

public final class KeychainManager {
    public static let shared = KeychainManager()
    
    private let service = "com.sec.vault"
    private let account = "master-key"
    
    private init() {}
    
    /// Checks if a master key already exists in the macOS Keychain
    public func hasMasterKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Retrieves the 256-bit master key from Keychain, creating one if it doesn't exist
    public func getOrCreateMasterKey() throws -> Data {
        if let existingKey = try? getMasterKey() {
            return existingKey
        }
        
        // Generate a new 256-bit (32 bytes) cryptographically secure random key
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        guard result == errSecSuccess else {
            throw KeychainError.unhandledError(status: result)
        }
        let keyData = Data(keyBytes)
        
        try storeMasterKey(keyData)
        return keyData
    }
    
    /// Retrieves existing master key from Keychain
    public func getMasterKey() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = dataTypeRef as? Data, data.count == 32 else {
            throw KeychainError.invalidKeyData
        }
        
        return data
    }
    
    /// Stores master key in Keychain
    private func storeMasterKey(_ keyData: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Update existing
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: keyData
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandledError(status: updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Deletes the master key from Keychain (used for reset)
    public func deleteMasterKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}
