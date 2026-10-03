import Foundation

/// What a selected item is called (FS-12.04 §5): the name the session
/// footer, the viewer header and the Look panel all use, and a second line
/// saying what it is and where it sits.
///
/// Clips are named by their position on the track — "Clip 2", "Photo 2",
/// "Freeze 2" — because a project has no other names for them; a caption by
/// its words; a music bed by its song.
enum VideoItemTitle {
    struct Lines: Equatable {
        let name: String
        let detail: String
    }

    static let table = "VideoStudio"

    /// "Clip 2" for the video clip at `index` (0-based) on the track.
    static func clipName(_ kind: VideoClipKind, index: Int) -> String {
        let position = index + 1
        return switch kind {
        case .video:
            String(localized: "Clip \(position)", comment: "Video Studio viewer header: the video clip under the playhead, by its position on the track")
        case .photo:
            String(localized: "Photo \(position)", comment: "Video Studio viewer header: the still under the playhead, by its position on the track")
        case .freeze:
            String(localized: "Freeze \(position)", comment: "Video Studio viewer header: the held frame under the playhead, by its position on the track")
        }
    }

    /// "Clip 2" over "6.2s · video".
    static func clip(_ clip: VideoClip, index: Int, locale: Locale = .current) -> Lines {
        let kind: String = switch clip.kind {
        case .video: String(localized: "video", table: table, locale: locale, comment: "Video Studio session footer: the kind of a selected clip, after its length — 6.2s · video")
        case .photo: String(localized: "photo", table: table, locale: locale, comment: "Video Studio session footer: the kind of a selected still, after its length — 3.0s · photo")
        case .freeze: String(localized: "freeze", table: table, locale: locale, comment: "Video Studio session footer: the kind of a selected held frame, after its length — 2.0s · freeze")
        }
        return Lines(
            name: clipName(clip.kind, index: index),
            detail: "\(seconds(clip.effectiveDuration)) · \(kind)"
        )
    }

    /// The caption's words over "Text · 1.0 → 5.0s"; a sticker is "Sticker".
    static func overlay(_ timed: TimedOverlay, totalDuration: Double, locale: Locale = .current) -> Lines {
        let end = timed.duration.map { timed.start + $0 } ?? totalDuration
        let isSticker = timed.overlay.kind == .image
        let kind = isSticker
            ? String(localized: "Sticker", table: table, locale: locale, comment: "Video Studio: a picture laid over the video")
            : String(localized: "Text", table: table, locale: locale, comment: "Video Studio: a caption laid over the video")
        let words = timed.overlay.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Lines(
            name: isSticker || words.isEmpty ? kind : words,
            detail: "\(kind) · \(span(timed.start, end))"
        )
    }

    /// The song over "Music · 0.0 → 18.4s".
    static func music(_ track: MusicTrack, end: Double, locale: Locale = .current) -> Lines {
        let kind = String(localized: "Music", table: table, locale: locale, comment: "Video Studio: a music bed on the timeline")
        return Lines(name: track.displayName, detail: "\(kind) · \(span(track.start, end))")
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1fs", value)
    }

    private static func span(_ start: Double, _ end: Double) -> String {
        String(format: "%.1f → %.1fs", start, end)
    }
}
