import Foundation

/// A subtitle's cues for the player (FS-23.03 §3–4): from its file in
/// `Movies/<id>/`, or — a sidecar of a streamed movie — read off the source
/// over the playback's own connection and kept in memory only, so streaming
/// still writes nothing (AC-3). Subtitles inside the movie file come in
/// plan task 24.
struct MovieSubtitleLoader: Sendable {
    let files: MovieFileStore
    /// Reads a small file on the movie's source; nil when playing from the
    /// device.
    var remote: (@Sendable (String) async throws -> Data)?

    func document(for subtitle: MovieSubtitle) async throws -> SubtitleDocument? {
        let data: Data
        if !subtitle.fileName.isEmpty {
            data = try Data(contentsOf: files.directory(for: subtitle.movieId).appending(path: subtitle.fileName))
        } else if let path = subtitle.remotePath, let remote {
            data = try await remote(path)
        } else {
            return nil
        }
        let decoded: SubtitleDecoder.Decoded
        if let encoding = subtitle.encoding, let text = SubtitleDecoder.decode(data, encoding: encoding) {
            decoded = SubtitleDecoder.Decoded(text: text, encoding: encoding)
        } else {
            decoded = SubtitleDecoder.decode(data, languageHint: subtitle.language)
        }
        let format = SubtitleParser.Format(rawValue: subtitle.format.rawValue) ?? .srt
        return SubtitleParser.parse(decoded.text, format: format)
    }
}
