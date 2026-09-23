import Foundation

/// How much room is left for something the user asked for.
///
/// `volumeAvailableCapacityForImportantUsage` is the right key rather than
/// `volumeAvailableCapacity`: it counts space the system can reclaim by
/// purging caches, which is space a photo the user asked to save is entitled
/// to. It is a required-reason API (`PrivacyInfo.xcprivacy`, category
/// `NSPrivacyAccessedAPICategoryDiskSpace`, reason `E174.1` — telling the user
/// their device is out of space).
enum DiskSpace {
    /// Bytes available for user-initiated work, or nil when the volume cannot
    /// be read — in which case the caller shows no warning rather than a wrong
    /// one.
    static func availableBytes(
        for url: URL = URL.temporaryDirectory
    ) -> Int64? {
        guard let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage
    }
}
