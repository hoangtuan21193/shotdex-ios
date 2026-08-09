import Foundation

/// One bundled soundtrack bed for the Video Studio.
struct MusicTrack: Identifiable, Equatable, Sendable {
    /// Filename stem in `Resources/Music/` — also the id stored in
    /// `MusicSource.bundled(id:)`.
    let id: String
    let displayName: String
    /// The bundle URL, nil when the file didn't ship — the chip then hides
    /// rather than offering a track that can't play.
    let url: URL?
}

/// The fixed bundled-music catalog. Hardcoded rather than a JSON manifest:
/// five known entries don't justify a parser, and the compiler checking the
/// ids is worth more than data-driving them. Licensing for the shipped files
/// is tracked in `Resources/Music/THIRD_PARTY_NOTICES.md`.
enum MusicTrackCatalog {
    static let tracks: [MusicTrack] = [
        make("Upbeat", String(localized: "Upbeat")),
        make("Chill", String(localized: "Chill")),
        make("Cinematic", String(localized: "Cinematic")),
        make("Acoustic", String(localized: "Acoustic")),
        make("Electronic", String(localized: "Electronic")),
    ]

    /// Only tracks whose audio actually shipped.
    static var availableTracks: [MusicTrack] {
        tracks.filter { $0.url != nil }
    }

    static func track(id: String) -> MusicTrack? {
        tracks.first { $0.id == id && $0.url != nil }
    }

    private static func make(_ id: String, _ displayName: String) -> MusicTrack {
        MusicTrack(
            id: id,
            displayName: displayName,
            url: Bundle.main.url(forResource: id, withExtension: "m4a")
        )
    }
}
