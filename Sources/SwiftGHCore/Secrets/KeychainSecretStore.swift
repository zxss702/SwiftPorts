#if canImport(Security)
import Foundation
import Security

/// Apple-platforms `SecretStore` backed by the Security framework's
/// keychain. macOS uses the user's login keychain by default; iOS
/// uses the app's keychain (sandboxed per app).
///
/// The Go gh uses `zalando/go-keyring` which on macOS calls these
/// same Security APIs. This is the direct Swift equivalent — no
/// third-party wrapper needed.
public struct KeychainSecretStore: SecretStore {
    public init() {}

    public func get(service: String, account: String) async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw SecretStoreError.invalidValue
            }
            guard let value = String(data: data, encoding: .utf8) else {
                throw SecretStoreError.invalidValue
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw SecretStoreError.backendError(
                status: status, message: keychainMessage(status))
        }
    }

    public func set(service: String, account: String, secret: String) async throws {
        let data = Data(secret.utf8)
        // Add or update — try add first, fall back to update on duplicate.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { return }
        if addStatus == errSecDuplicateItem {
            let lookupQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let updateAttrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(
                lookupQuery as CFDictionary, updateAttrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecretStoreError.backendError(
                    status: updateStatus, message: keychainMessage(updateStatus))
            }
            return
        }
        throw SecretStoreError.backendError(
            status: addStatus, message: keychainMessage(addStatus))
    }

    public func delete(service: String, account: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw SecretStoreError.backendError(
            status: status, message: keychainMessage(status))
    }

    private func keychainMessage(_ status: OSStatus) -> String {
        if let cf = SecCopyErrorMessageString(status, nil) {
            return cf as String
        }
        return "OSStatus \(status)"
    }
}
#endif
