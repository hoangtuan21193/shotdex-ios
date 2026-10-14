import Foundation
import Testing
@testable import ShotDex

/// FS-23.02 §3b — the rows of the Audio panel.
@Suite struct MovieAudioTrackLabelTests {
    /// AC-39 (labels): five tracks in file order, each language · name ·
    /// codec · channels, `Default` on the first.
    @Test func fiveTracks() {
        let tracks = [
            MovieAudioTrack(id: "a1", language: "eng", name: nil, codec: "truehd", channels: 8, isDefault: true),
            MovieAudioTrack(id: "a2", language: "eng", name: "English", codec: "ac3", channels: 6, isDefault: false),
            MovieAudioTrack(id: "a3", language: "en", name: "Commentary", codec: "aac", channels: 2, isDefault: false),
            MovieAudioTrack(id: "a4", language: "vie", name: nil, codec: "mp4a", channels: 2, isDefault: false),
            MovieAudioTrack(id: "a5", language: "jpn", name: "Japanese", codec: "a52", channels: 6, isDefault: false),
        ]
        let rows = tracks.enumerated().map { index, track in
            [MovieAudioTrackLabel.title(track, position: index + 1), MovieAudioTrackLabel.detail(track)]
        }
        #expect(rows == [
            ["English", "TrueHD 7.1"],
            ["English", "AC3 5.1"],
            ["English", "Commentary · AAC Stereo"],
            ["Tiếng Việt", "AAC Stereo"],
            ["日本語", "AC3 5.1"],
        ])
        #expect(tracks.filter(\.isDefault).map(\.id) == ["a1"])
    }

    @Test func unknownLanguageUsesPosition() {
        let track = MovieAudioTrack(id: "x", language: "und", name: nil, codec: "flac", channels: 1, isDefault: false)
        #expect(MovieAudioTrackLabel.title(track, position: 3) == "Track 3")
        #expect(MovieAudioTrackLabel.detail(track) == "FLAC Mono")
    }

    @Test func languageCodes() {
        #expect(MovieLanguage.code("ger") == "de")
        #expect(MovieLanguage.code("deu") == "de")
        #expect(MovieLanguage.code("pt-BR") == "pt")
        #expect(MovieLanguage.code("Vietnamese") == "vi")
        #expect(MovieLanguage.code("und") == nil)
        #expect(MovieLanguage.code("") == nil)
        #expect(MovieLanguage.endonym("fr") == "Français")
    }
}

/// FS-23.02 §3b / FS-23.03 §2 — what a movie opens with.
@Suite struct MovieTrackChoiceTests {
    private let enDefault = MovieAudioTrack(id: "en", language: "eng", codec: "ac3", channels: 6, isDefault: true)
    private let vi = MovieAudioTrack(id: "vi", language: "vie", codec: "aac", channels: 2, isDefault: false)

    /// AC-40: Audio Languages Tiếng Việt, English → the VI track; Original
    /// → the file's Default.
    @Test func preferredAudioLanguage() {
        #expect(MovieTrackChoice.audioTrack([enDefault, vi], preferredLanguages: ["vi", "en"], remembered: nil)?.id == "vi")
        #expect(MovieTrackChoice.audioTrack([enDefault, vi], preferredLanguages: [MovieTrackChoice.original], remembered: nil)?.id == "en")
        #expect(MovieTrackChoice.audioTrack([vi, enDefault], preferredLanguages: ["ja"], remembered: nil)?.id == "en")
        #expect(MovieTrackChoice.audioTrack([], preferredLanguages: ["vi"], remembered: nil) == nil)
    }

    /// AC-15 (logic): the track picked for this movie wins next time.
    @Test func rememberedWins() {
        #expect(MovieTrackChoice.audioTrack([enDefault, vi], preferredLanguages: ["en"], remembered: "vi")?.id == "vi")
        #expect(MovieTrackChoice.audioTrack([enDefault, vi], preferredLanguages: ["en"], remembered: "gone")?.id == "en")
    }

    @Test func unsupportedSkipped() {
        var dts = enDefault
        dts.isSupported = false
        let aac = MovieAudioTrack(id: "en2", language: "en", codec: "aac", channels: 2, isDefault: false)
        #expect(MovieTrackChoice.audioTrack([dts, aac], preferredLanguages: ["en"], remembered: nil)?.id == "en2")
    }

    @Test func primarySubtitleFollowsSubtitleLanguages() {
        let subtitles = [("s1", "en"), ("s2", "vie"), ("s3", nil as String?)]
        #expect(MovieTrackChoice.primarySubtitle(subtitles, language: { $0.1 }, preferredLanguages: ["vi", "en"])?.0 == "s2")
        #expect(MovieTrackChoice.primarySubtitle(subtitles, language: { $0.1 }, preferredLanguages: ["ja"]) == nil)
    }
}
