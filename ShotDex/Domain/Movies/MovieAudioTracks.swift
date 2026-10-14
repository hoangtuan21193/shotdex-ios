import Foundation

/// One audio track of a movie, as the player reports it — independent of
/// VLCKit so the labels and the choice are plain logic (FS-23.02 §3b).
struct MovieAudioTrack: Equatable, Identifiable, Sendable {
    var id: String
    /// ISO 639-1/-2 or BCP 47 (`eng`, `vi`, `pt-BR`); nil when the file
    /// does not say.
    var language: String?
    /// The track's own name (`Commentary`, `Director's Cut`).
    var name: String?
    /// Codec short name (`truehd`, `ac3`, `aac`…).
    var codec: String?
    var channels: Int?
    var isDefault: Bool
    /// The device has no decoder for it (rare): shown dimmed.
    var isSupported = true
}

/// The row text of the Audio panel: `Tiếng Việt` over
/// `Commentary · AAC Stereo`.
enum MovieAudioTrackLabel {
    /// The language in that language (`Tiếng Việt`, `日本語`), or
    /// `Track 3` when the file does not say.
    static func title(_ track: MovieAudioTrack, position: Int) -> String {
        if let code = MovieLanguage.code(track.language), let name = MovieLanguage.endonym(code) { return name }
        return String(localized: "Track \(position)", comment: "Audio track with no language: its position in the file")
    }

    /// Name · codec · channels, whichever the file gives.
    static func detail(_ track: MovieAudioTrack) -> String {
        var parts: [String] = []
        if let name = track.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
           MovieLanguage.code(name) == nil || MovieLanguage.code(name) != MovieLanguage.code(track.language) {
            parts.append(name)
        }
        // `AC3 5.1` reads as one fact (board PH_MovieTracks); the name is
        // a separate one.
        let format = [track.codec.map(codecName), track.channels.map(channelName)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !format.isEmpty { parts.append(format) }
        return parts.joined(separator: " · ")
    }

    static func codecName(_ codec: String) -> String {
        switch codec.lowercased().trimmingCharacters(in: .whitespaces) {
        case "truehd", "mlp", "trhd": "TrueHD"
        case "ac3", "a52", "ac-3": "AC3"
        case "eac3", "e-ac3", "ec-3", "ec3": "E-AC3"
        case "dts", "dca": "DTS"
        case "dts-hd", "dtshd", "dts-hd ma": "DTS-HD"
        case "aac", "mp4a": "AAC"
        case "opus": "Opus"
        case "vorbis", "vorb": "Vorbis"
        case "flac": "FLAC"
        case "mp3", "mpga", "mp2": "MP3"
        case "alac": "ALAC"
        case let pcm where pcm.hasPrefix("pcm") || ["lpcm", "araw", "s16l", "s16b", "s24l", "s24b", "s32l", "f32l", "f64l", "twos", "sowt"].contains(pcm): "PCM"
        case let other: other.uppercased()
        }
    }

    static func channelName(_ channels: Int) -> String {
        switch channels {
        case 1: String(localized: "Mono", comment: "Audio track: one channel")
        case 2: String(localized: "Stereo", comment: "Audio track: two channels")
        case 3: "2.1"
        case 6: "5.1"
        case 7: "6.1"
        case 8: "7.1"
        default: String(localized: "\(channels) ch", comment: "Audio track: number of channels")
        }
    }
}

/// Which track a movie opens with (FS-23.02 §3b, FS-23.03 §2).
enum MovieTrackChoice {
    /// The Settings value meaning "the file's default track".
    static let original = "original"

    /// The track the user picked for this movie, if it still exists; else
    /// the first preferred language present; else the file's default;
    /// else the first.
    static func audioTrack(_ tracks: [MovieAudioTrack], preferredLanguages: [String], remembered: String?) -> MovieAudioTrack? {
        if let remembered, let track = tracks.first(where: { $0.id == remembered }) { return track }
        let playable = tracks.filter(\.isSupported)
        let pool = playable.isEmpty ? tracks : playable
        for preference in preferredLanguages {
            if preference == original { break }
            guard let wanted = MovieLanguage.code(preference) else { continue }
            if let track = pool.first(where: { MovieLanguage.code($0.language) == wanted }) { return track }
        }
        return pool.first(where: \.isDefault) ?? pool.first
    }

    /// Primary subtitle for a movie opened the first time: the first
    /// subtitle in the first Subtitle Language that has one; else none.
    static func primarySubtitle<S>(_ subtitles: [S], language: (S) -> String?, preferredLanguages: [String]) -> S? {
        for preference in preferredLanguages {
            guard let wanted = MovieLanguage.code(preference) else { continue }
            if let found = subtitles.first(where: { MovieLanguage.code(language($0)) == wanted }) { return found }
        }
        return nil
    }
}

/// Language codes as files write them (`eng`, `vie`, `ger`, `pt-BR`) down
/// to one key, and their names in their own language.
enum MovieLanguage {
    /// ISO 639-2 (B and T) → 639-1 for the languages films come in most.
    private static let threeLetter: [String: String] = [
        "eng": "en", "vie": "vi", "jpn": "ja", "kor": "ko", "chi": "zh", "zho": "zh", "cmn": "zh", "yue": "zh",
        "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "spa": "es", "ita": "it", "por": "pt", "rus": "ru",
        "ukr": "uk", "pol": "pl", "cze": "cs", "ces": "cs", "dut": "nl", "nld": "nl", "swe": "sv", "nor": "no",
        "nob": "no", "dan": "da", "fin": "fi", "gre": "el", "ell": "el", "tur": "tr", "ara": "ar", "heb": "he",
        "hin": "hi", "tha": "th", "ind": "id", "may": "ms", "msa": "ms", "fil": "fil", "tgl": "fil", "hun": "hu",
        "rum": "ro", "ron": "ro", "bul": "bg", "hrv": "hr", "srp": "sr", "slo": "sk", "slk": "sk", "per": "fa", "fas": "fa",
        "cat": "ca", "baq": "eu", "eus": "eu", "ice": "is", "isl": "is", "khm": "km", "lao": "lo", "bur": "my", "mya": "my",
    ]

    /// `en`, `vi`, `zh`… — nil for "und", "mis", empty or unknown.
    static func code(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else { return nil }
        value = String(value.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
        if ["und", "mis", "mul", "zxx", "qaa"].contains(value) { return nil }
        if value.count == 3 { return threeLetter[value] }
        if value.count == 2, Locale(identifier: "en").localizedString(forLanguageCode: value) != nil { return value }
        // A whole name (`English`, `Vietnamese`) in a track title.
        for code in Locale.LanguageCode.isoLanguageCodes.map(\.identifier) where code.count == 2 {
            if Locale(identifier: "en").localizedString(forLanguageCode: code)?.lowercased() == value { return code }
        }
        return nil
    }

    /// The language's own name, capitalised as a list row starts.
    static func endonym(_ code: String) -> String? {
        guard let name = Locale(identifier: code).localizedString(forLanguageCode: code) else { return nil }
        return name.prefix(1).uppercased(with: Locale(identifier: code)) + name.dropFirst()
    }
}
