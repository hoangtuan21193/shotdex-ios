import Foundation
import Security

/// Where file-server passwords live. A protocol so the stores can be tested
/// without the Keychain, which a unit-test host cannot always reach.
protocol ServerPasswordStoring: Sendable {
    func password(for serverId: String) -> String?
    func setPassword(_ password: String, for serverId: String) throws
    func removePassword(for serverId: String)
}

/// Generic-password items in the app's Keychain, one per server id,
/// readable only while the device is unlocked on this device (never synced
/// or restored to another phone: a backup is not where a NAS password goes).
struct KeychainPasswordStore: ServerPasswordStoring {
    private let service = "com.hoangtuan.shotdex.file-server"

    private func query(_ serverId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId,
        ]
    }

    func password(for serverId: String) -> String? {
        var request = query(serverId)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setPassword(_ password: String, for serverId: String) throws {
        let data = Data(password.utf8)
        let status = SecItemUpdate(
            query(serverId) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = query(serverId)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func removePassword(for serverId: String) {
        SecItemDelete(query(serverId) as CFDictionary)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let reason = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
        return String(localized: "Couldn't save the password: \(reason)", comment: "File server form: the Keychain refused the password")
    }
}

/// For tests and previews.
final class InMemoryPasswordStore: ServerPasswordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var passwords: [String: String] = [:]

    func password(for serverId: String) -> String? {
        lock.withLock { passwords[serverId] }
    }

    func setPassword(_ password: String, for serverId: String) throws {
        lock.withLock { passwords[serverId] = password }
    }

    func removePassword(for serverId: String) {
        lock.withLock { passwords[serverId] = nil }
    }
}
