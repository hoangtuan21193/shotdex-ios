import Foundation
import GRDB

/// How much of a photo or video is kept on the device (intent
/// 2026-10-19-keep-offline, question 2). Asked once per keep.
enum KeepQuality: String, Codable, Sendable, CaseIterable {
    /// Photos up to 2732 px on the long side, videos at 1080p. RAW comes as a
    /// viewing copy too: it is for looking at, not editing.
    case viewingCopy
    /// The file itself, RAW and 4K included.
    case original

    /// The long side a viewing copy of a photo is drawn at.
    static let viewingLongSide = 2732
}

/// One photo or video the user chose to keep on this device, from any
/// source. User data the indexer never writes, so a table of its own — not a
/// column on `photo_metadata`, whose rows the indexer rewrites whole.
struct KeptItem: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kept_items"

    enum State: String, Codable, Sendable {
        /// Waiting its turn.
        case queued
        case downloading
        /// The file is here and opens without a connection.
        case onDevice
        /// The last try failed; `error` says why. Tapping Retry queues it again.
        case failed
        /// The row says "on device" but the file is gone (the launch sweep
        /// found it missing). Never deleted by the app: the user decides.
        case missing
    }

    /// The photo id — a PhotoKit local identifier for a Photos asset, the
    /// photo's own id for a folder or server copy.
    var id: String
    var isVideo: Bool
    var quality: KeepQuality
    var state: State
    /// Name of the kept file inside the item's folder once it is here.
    var fileName: String?
    /// Bytes on the device, 0 until it is here.
    var byteCount: Int64
    /// The kept album that brought this item in; nil when kept on its own.
    var albumId: String?
    var error: String?
    /// Seconds since 1970.
    var addedAt: Int

    init(id: String, isVideo: Bool, quality: KeepQuality, albumId: String?, addedAt: Date = .now) {
        self.id = id
        self.isVideo = isVideo
        self.quality = quality
        self.state = .queued
        self.fileName = nil
        self.byteCount = 0
        self.albumId = albumId
        self.error = nil
        self.addedAt = Int(addedAt.timeIntervalSince1970)
    }
}

/// An album kept as a whole. With `keepsNewPhotos`, a photo added to the
/// album later is kept too (intent question 4).
struct KeptAlbum: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kept_albums"

    /// The album's PhotoKit local identifier.
    var id: String
    var title: String
    var quality: KeepQuality
    var keepsNewPhotos: Bool
    var addedAt: Int

    init(id: String, title: String, quality: KeepQuality, keepsNewPhotos: Bool, addedAt: Date = .now) {
        self.id = id
        self.title = title
        self.quality = quality
        self.keepsNewPhotos = keepsNewPhotos
        self.addedAt = Int(addedAt.timeIntervalSince1970)
    }
}
