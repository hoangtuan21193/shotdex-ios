import Foundation
import Security

/// What the app hands the Photos background-upload extension (FS-22.02 §3c):
/// the Photos → WebDAV jobs, written to the App Group. The extension never
/// opens the database.
struct BackupUploadConfig: Codable, Equatable, Sendable {
    struct Job: Codable, Equatable, Sendable {
        var jobId: String
        /// `https://nas.local:5006` — scheme, host and port of the connection.
        var baseURL: String
        /// Folder on the server, `/`-separated, no leading slash.
        var folder: String
        var settings: BackupSettings
        /// Keychain account of the connection's sign-in.
        var account: String
    }

    var jobs: [Job] = []
}

/// Where the config, the extension's change tokens and the WebDAV sign-ins
/// live, so both processes reach them.
enum BackupUploadShared {
    static let groupIdentifier = "group.com.hoangtuan.shotdex"
    static let keychainService = "com.hoangtuan.shotdex.backup-webdav"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("Backup", isDirectory: true)
    }

    static func readConfig() -> BackupUploadConfig {
        guard let url = container?.appendingPathComponent("upload-config.json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(BackupUploadConfig.self, from: data) else { return BackupUploadConfig() }
        return config
    }

    static func writeConfig(_ config: BackupUploadConfig) {
        guard let folder = container else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(config).write(to: folder.appendingPathComponent("upload-config.json"), options: .atomic)
    }

    /// The extension's own change token per job.
    static func readTokens() -> [String: Data] {
        guard let url = container?.appendingPathComponent("upload-tokens.plist"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? PropertyListDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    static func writeTokens(_ tokens: [String: Data]) {
        guard let folder = container else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? PropertyListEncoder().encode(tokens).write(to: folder.appendingPathComponent("upload-tokens.plist"), options: .atomic)
    }

    /// `Basic …` for the connection, from the Keychain item both processes
    /// share through the App Group.
    static func authorization(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: groupIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setAuthorization(_ value: String?, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: groupIdentifier,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// The requests the extension hands Photos for one file: PUT to the
/// `.shotdex-part` name, never the real one — the app reads it back and
/// renames it on its next run (FS-22.02 §3c). Pure, so it is a unit test.
enum BackupUploadRequests {
    static let partSuffix = ".shotdex-part"

    /// Folders under the job's folder, top first, that must exist before the PUT.
    static func folders(for relativePath: String, job: BackupUploadConfig.Job) -> [String] {
        var result: [String] = []
        var current = job.folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !current.isEmpty {
            var partial = ""
            for part in current.split(separator: "/") {
                partial = partial.isEmpty ? String(part) : partial + "/" + part
                result.append(partial)
            }
        }
        let parts = relativePath.split(separator: "/").dropLast()
        for part in parts {
            current = current.isEmpty ? String(part) : current + "/" + part
            result.append(current)
        }
        return result
    }

    static func url(_ path: String, job: BackupUploadConfig.Job) -> URL? {
        let escaped = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? String($0)
        }.joined(separator: "/")
        let base = job.baseURL.hasSuffix("/") ? String(job.baseURL.dropLast()) : job.baseURL
        return URL(string: "\(base)/\(escaped)")
    }

    /// The PUT for a file whose path under the job's folder is `relativePath`.
    static func put(relativePath: String, job: BackupUploadConfig.Job, authorization: String?) -> URLRequest? {
        let folder = job.folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let full = folder.isEmpty ? relativePath : "\(folder)/\(relativePath)"
        guard let url = url(full + partSuffix, job: job) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        request.allowsExpensiveNetworkAccess = !job.settings.onlyOnWiFi
        request.allowsConstrainedNetworkAccess = !job.settings.onlyOnWiFi
        return request
    }

    static func mkcol(_ folder: String, job: BackupUploadConfig.Job, authorization: String?) -> URLRequest? {
        guard let url = url(folder + "/", job: job) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        return request
    }
}
