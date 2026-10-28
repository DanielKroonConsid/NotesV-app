import Foundation
import Security

/// Stores secrets, such as API keys, in the macOS Keychain.
struct KeychainService: Sendable {
    struct KeychainError: LocalizedError {
        var status: OSStatus

        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return String(localized: "Couldn’t access the Keychain: \(message)")
        }
    }

    /// The Keychain service name; one account per server.
    var service = "se.consid.NotesV.ai-endpoint"

    func password(for account: String) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).map { String(decoding: $0, as: UTF8.self) }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// Saves the password, or deletes it if `password` is empty or `nil`.
    func setPassword(_ password: String?, for account: String) throws {
        guard let password, !password.isEmpty else {
            let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }

        let data = Data(password.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var query = baseQuery(for: account)
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
