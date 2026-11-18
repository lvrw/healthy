import Foundation
import Security

enum KeychainError: LocalizedError {
    case encoding
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encoding:
            return "API Key 编码失败"
        case .status(let status):
            return "钥匙串操作失败（\(status)）"
        }
    }
}

struct KeychainStore: Sendable {
    let service: String

    init(service: String = "cn.rw.healthy.llm") {
        self.service = service
    }

    func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encoding }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertQuery = query
            for (key, value) in attributes {
                insertQuery[key] = value
            }
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }

    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func hasKey(account: String) -> Bool {
        read(account: account)?.isEmpty == false
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
