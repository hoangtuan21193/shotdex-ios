import Foundation

/// One photo the pipeline is about to read, as the shared index knows it:
/// the library's own id and the asset's modification date in whole seconds.
/// A result read on another device is reused only for the same date — the
/// photo was edited since otherwise, and its file may say something else.
struct SharedIndexKey: Sendable, Hashable {
    let assetId: String
    let modificationDate: Int?
}

/// A file read this device finished, offered to the other devices.
struct SharedIndexRead: Sendable {
    let key: SharedIndexKey
    let exif: RawExif
}

/// The EXIF other devices on the same iCloud account already read
/// (intent 2026-11-02-icloud-shared-index). The pipeline asks before a batch's
/// reads and hands over what it read after; how the results travel is not
/// its concern.
protocol SharedIndexSource: Sendable {
    /// Results read elsewhere for these assets, keyed by asset id — only
    /// those whose modification date matches.
    func sharedExif(for keys: [SharedIndexKey]) async -> [String: RawExif]
    /// Records this device's own reads so the other devices can skip them.
    func share(_ reads: [SharedIndexRead]) async
}
