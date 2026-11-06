import Foundation

/// The line under a smart album that keeps an album in Photos (FS-06.12 §3).
/// The album has the smart album's name, so the line does not repeat it.
enum PhotosAlbumSyncLine {
    struct Line: Equatable {
        var text: String
        /// Whether the Move to Shared Library hint follows it.
        var showsHint: Bool
    }

    static let hint = String(localized: "To share these, open the album in Photos and choose Move to Shared Library.",
                             comment: "Smart album kept in Photos: how to move its photos to the iCloud Shared Library")

    /// Nil when Keep in Photos is off and nothing needs saying.
    static func line(state: PhotosAlbumSyncState?, isEnabled: Bool, assetCount: Int, lastSyncedAt: Date?,
                     progress: (done: Int, total: Int)?, now: Date = Date()) -> Line? {
        if state == .deletedInPhotos {
            return Line(text: String(localized: "The album was deleted in Photos. Keep in Photos is off.",
                                     comment: "Smart album: the album ShotDex kept in Photos was deleted there"),
                        showsHint: false)
        }
        guard isEnabled, let state else { return nil }
        if let progress {
            return Line(text: String(localized: "Updating album in Photos… \(progress.done.formatted()) of \(progress.total.formatted())",
                                     comment: "Smart album: Keep in Photos writing; e.g. Updating album in Photos… 3,200 of 8,412"),
                        showsHint: false)
        }
        switch state {
        case .needsFullAccess:
            return Line(text: String(localized: "Needs Full Photos Access to keep the album in Photos.",
                                     comment: "Smart album: Keep in Photos is on but ShotDex has only limited Photos access"),
                        showsHint: false)
        case .failed:
            return Line(text: String(localized: "Couldn’t update the album in Photos. Will try again.",
                                     comment: "Smart album: a Keep in Photos write failed; it retries"),
                        showsHint: false)
        case .synced where assetCount == 0:
            // Nothing to move yet — no instruction to move it (UX review).
            return Line(text: String(localized: "In Photos · No photos yet",
                                     comment: "Smart album kept in Photos: its album holds nothing yet, e.g. while the NAS check runs"),
                        showsHint: false)
        case .synced:
            let count = String(localized: "In Photos · \(assetCount) photos",
                               comment: "Smart album kept in Photos: how many photos its album holds; e.g. In Photos · 8,412 photos")
            guard let lastSyncedAt else { return Line(text: count, showsHint: true) }
            let ago = min(lastSyncedAt, now).formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            return Line(text: String(localized: "\(count) · Updated \(ago)",
                                     comment: "Smart album kept in Photos: count line and when it was last updated; e.g. … · Updated 2 min ago"),
                        showsHint: true)
        case .idle, .updating, .deletedInPhotos:
            return Line(text: String(localized: "Updating album in Photos…", comment: "Smart album: Keep in Photos about to write"),
                        showsHint: false)
        }
    }
}
