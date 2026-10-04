import Foundation

/// Where the shared preview cache lives on disk (`PreviewCachePolicy`).
enum PreviewCacheLocation {
    /// `Application Support/PreviewCache`, created and excluded from backup.
    static var standard: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return prepare(support.appendingPathComponent(PreviewCachePolicy.folderName, isDirectory: true))
    }

    /// Creates the folder if needed and marks it excluded from backup. The
    /// flag sits on the folder, so everything written inside inherits it.
    @discardableResult
    static func prepare(_ directory: URL) -> URL {
        var url = directory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    /// The server thumbnail cache used to sit in Caches; nothing in it is
    /// worth keeping, so the old folder simply goes.
    static func removeRetiredServerThumbnails() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("ServerThumbnails", isDirectory: true))
    }
}
