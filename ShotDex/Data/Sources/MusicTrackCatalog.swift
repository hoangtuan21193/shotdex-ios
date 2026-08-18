import Foundation

/// One bundled music bed reference (kept for the `MusicSource.bundled` code
/// paths, which now resolve to nothing — the app ships no bundled beds). Not to
/// be confused with `MusicTrack`, the bed a project actually places.
struct BundledMusicTrack: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let url: URL?
}

/// The bundled-music catalog is intentionally **empty**: ShotDex ships no
/// pre-made soundtracks. Users bring their own audio via Files import, persisted
/// for reuse by `ImportedMusicStore`. The lookup remains so the older
/// `MusicSource.bundled(id:)` case resolves safely to `nil` (no music).
enum MusicTrackCatalog {
    static let availableTracks: [BundledMusicTrack] = []

    static func track(id: String) -> BundledMusicTrack? { nil }
}
