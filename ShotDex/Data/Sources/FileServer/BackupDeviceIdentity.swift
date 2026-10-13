import Foundation
import Security

/// This device's name in the shared backup index (FS-22.05 §2): a UUID made
/// the first time and kept in the Keychain, so reinstalling the app on the
/// same phone keeps writing as the same device.
enum BackupDeviceIdentity {
    private static let service = "com.hoangtuan.shotdex.backup-device"
    private static let account = "device"
    private static let lock = NSLock()

    static func current() -> String {
        lock.withLock {
            if let stored = read() { return stored }
            let made = UUID().uuidString
            // A Keychain that refuses still backs up: the next run writes
            // under a new name, which costs a segment, never a photo.
            save(made)
            return made
        }
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let id = String(data: data, encoding: .utf8), !id.isEmpty
        else { return nil }
        return id
    }

    private static func save(_ id: String) {
        var item = query
        item[kSecValueData as String] = Data(id.utf8)
        // Background runs happen with the phone locked.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
