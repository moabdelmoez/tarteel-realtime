import Foundation
import Security

final class KeychainBackendBearerTokenStore: BackendBearerTokenStoring {
    private let service: String

    init(service: String = "dev.mostafa.TarteelPrototypeMac.backend-token") {
        self.service = service
    }

    func token(for provider: BackendProvider) throws -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainBackendBearerTokenStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setToken(_ token: String?, for provider: BackendProvider) throws {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedToken.isEmpty {
            try deleteToken(for: provider)
            return
        }

        let data = Data(trimmedToken.utf8)
        var query = baseQuery(for: provider)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainBackendBearerTokenStoreError.unhandledStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainBackendBearerTokenStoreError.unhandledStatus(addStatus)
        }
    }

    private func deleteToken(for provider: BackendProvider) throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainBackendBearerTokenStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for provider: BackendProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}

private enum KeychainBackendBearerTokenStoreError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
