import Foundation

/// Whether a Photos item has every original on this device (FS-06.10 §3):
/// what the background check stores and what the **Original** rule reads.
/// A photo with no row, or a row marked for a recheck, is *not checked* and
/// matches neither value.
enum OriginalPresence: String, Codable, CaseIterable, Sendable {
    /// Every original resource reads back with the network off.
    case onDevice
    /// At least one original resource would have to come from iCloud.
    case iCloudOnly

    /// One of a Photos item's resources, in the app's own words so the rule
    /// is testable without PhotoKit. `PHAssetResourceType` maps onto it in
    /// the Data layer.
    enum Resource: Hashable, Sendable {
        /// The photo as shot.
        case photo
        /// The second file of a RAW+JPEG pair.
        case alternatePhoto
        /// The movie of a Live Photo.
        case pairedVideo
        /// A video as shot.
        case video
        /// The rendered edit of a photo.
        case fullSizePhoto
        /// The rendered edit of a Live Photo's movie.
        case fullSizePairedVideo
        /// The rendered edit of a video.
        case fullSizeVideo
        /// Anything else PhotoKit lists — adjustment data, the edit's base
        /// photo, audio: not something viewing or exporting offline needs.
        case other
    }

    /// The resources that have to be here for the item to be *on this
    /// device*: everything viewing or exporting it offline reads — the
    /// original, the Live Photo's movie, the RAW of a pair and, once edited,
    /// the render (§4).
    static func required(among resources: [Resource]) -> [Resource] {
        var seen = Set<Resource>()
        return resources.filter { $0 != .other && seen.insert($0).inserted }
    }

    /// The verdict for one item from what each required resource's offline
    /// check said. One resource in iCloud settles it; otherwise a check that
    /// could not tell leaves the item unchecked rather than guessing (§3),
    /// and so does an item with no required resource at all.
    static func judge(_ results: [OriginalAvailability]) -> OriginalPresence? {
        guard !results.isEmpty else { return nil }
        if results.contains(.inCloud) { return .iCloudOnly }
        if results.contains(.unknown) { return nil }
        return .onDevice
    }
}
