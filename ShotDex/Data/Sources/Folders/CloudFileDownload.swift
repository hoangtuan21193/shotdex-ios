import Foundation

/// Brings one file of a folder source down from its file provider — iCloud
/// Drive, Dropbox, OneDrive behind Files (FS-19.01b §4). Only ever called
/// for the file the user opened; the read of a source never downloads.
protocol CloudFileDownloading: Sendable {
    /// Returns once `url` is on the device. `progress` gets 0…1 when the
    /// provider reports it and nil while it does not. Cancelling the task
    /// stops the download and leaves the placeholder as it was.
    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws
}

/// The system's own download: `startDownloadingUbiquitousItem`, then a look
/// four times a second until the file is current. Third-party providers
/// publish no progress an app can read on iOS, so the fraction stays nil and
/// the bar is indeterminate; a cancel evicts what came down so far.
struct UbiquitousFileDownloader: CloudFileDownloading {
    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        do {
            while !Self.isDownloaded(url) {
                progress(nil)
                try await Task.sleep(for: .milliseconds(250))
            }
            progress(1)
        } catch is CancellationError {
            try? FileManager.default.evictUbiquitousItem(at: url)
            throw CancellationError()
        }
    }

    /// iOS swaps `.Name.ext.icloud` for `Name.ext`; macOS keeps the name and
    /// flips the downloading status to current.
    static func isDownloaded(_ url: URL) -> Bool {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        if let status = try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus {
            return status == .current
        }
        return FileManager.default.fileExists(atPath: url.path)
            && !FileManager.default.fileExists(atPath: CloudPlaceholder.placeholderURL(for: url).path)
    }
}

/// What a placeholder says about the file it stands for without downloading
/// it: iOS writes the size into the `.icloud` property list.
enum CloudPlaceholder {
    /// `.IMG_1.JPG.icloud` beside `IMG_1.JPG`.
    static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    /// Bytes the download will take, when the placeholder or the provider
    /// knows; nil otherwise.
    static func size(of url: URL) -> Int64? {
        if let data = try? Data(contentsOf: placeholderURL(for: url)),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let size = (plist["NSURLFileSizeKey"] as? NSNumber)?.int64Value, size > 0 {
            return size
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 { return Int64(size) }
        return nil
    }
}

#if DEBUG
/// `-ShotDexSimulateCloudDownloads`: the simulator has no iCloud Drive, so a
/// UI script stands a placeholder up as `.Name.ext.icloud` with the real file
/// stashed beside it as `.Name.ext.shotdex-cloud`; this "downloads" it over
/// twenty seconds with a real fraction, the way a provider that reports one
/// would look — long enough for a script to reach Cancel.
struct SimulatedCloudDownloader: CloudFileDownloading {
    static let argument = "-ShotDexSimulateCloudDownloads"

    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        let stash = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).shotdex-cloud")
        for step in 0...40 {
            progress(Double(step) / 40)
            try await Task.sleep(for: .milliseconds(500))
        }
        try FileManager.default.moveItem(at: stash, to: url)
        try? FileManager.default.removeItem(at: CloudPlaceholder.placeholderURL(for: url))
    }
}
#endif
