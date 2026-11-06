import Foundation

/// The one preview cache every source shares (FS-19 01b §3, NF-02 §2):
/// thumbnails and previews of photos read from folders, drives and servers.
/// It lives in Application Support — out of reach of the system's Caches
/// purge, so a drive that is unplugged still shows its photos — and is kept
/// out of the device backup, because every byte in it can be read again.
enum PreviewCachePolicy {
    /// Cache Size Limit choices, in gigabytes, as Settings lists them.
    static let limitChoices: [Int] = [2, 5, 10, 25, 50]

    /// The Mac has the disk for a library's worth of previews; a phone or a
    /// tablet does not.
    static var defaultLimit: Int {
        #if os(macOS)
        25
        #else
        5
        #endif
    }

    /// Cache Size Limit as Settings stored it (Mac Settings › Sources ›
    /// Previews, FS-18.04 §3 AC-76); the platform default when unset or not
    /// one of the choices.
    static func limit(from defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: SettingsKeys.previewCacheLimitGB)
        return limitChoices.contains(stored) ? stored : defaultLimit
    }

    /// Gigabytes the way Finder and Settings count them.
    static func bytes(gigabytes: Int) -> Int64 {
        Int64(gigabytes) * 1_000_000_000
    }

    static let folderName = "PreviewCache"
    /// Server thumbnails and capture dates, until W2 gives every source one
    /// eviction order.
    static let serverFolderName = "Servers"
}
