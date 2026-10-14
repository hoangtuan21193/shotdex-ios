import CryptoKit
import Foundation
import NaturalLanguage

/// Subtitle files the user brings (FS-23.03 §5): Import File… in the panel,
/// or Share / AirDrop. Copied into `Movies/<id>/`; a zip gives up every
/// subtitle inside and nothing else; the language comes from the file name,
/// else from the text; the same text twice on one movie is added once.
struct SubtitleImporter: Sendable {
    let store: MovieStore
    let files: MovieFileStore

    enum Failure: LocalizedError, Equatable {
        case noSubtitles
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noSubtitles: String(localized: "No subtitles in this file.", comment: "Subtitle import: a zip without subtitle files")
            case .unreadable: String(localized: "ShotDex can't read this subtitle file.", comment: "Subtitle import: a file that is not a subtitle")
            }
        }
    }

    struct Result: Equatable, Sendable {
        var added: [MovieSubtitle] = []
        var duplicates = 0
    }

    /// The subtitle files `urls` hold — zips opened — named and read.
    static func candidates(_ urls: [URL]) throws -> [(name: String, data: Data)] {
        var found: [(String, Data)] = []
        for url in urls {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            if SubtitleFileName.isZip(name) {
                let entries = try ZipReader.entries(try Data(contentsOf: url)) { SubtitleFileName.isSubtitle($0) }
                found += entries.map { (($0.name as NSString).lastPathComponent, $0.data) }
            } else if SubtitleFileName.isSubtitle(name) {
                found.append((name, try Data(contentsOf: url)))
            }
        }
        guard !found.isEmpty else { throw Failure.noSubtitles }
        return found
    }

    func importFiles(_ urls: [URL], into movieId: String, origin: MovieSubtitle.Origin, at date: Date = Date()) throws -> Result {
        let candidates: [(name: String, data: Data)]
        do {
            candidates = try Self.candidates(urls)
        } catch ZipReader.Failure.notZip {
            throw Failure.unreadable
        }
        var known = Set(try store.subtitles(movieId: movieId).compactMap { subtitle -> String? in
            guard !subtitle.fileName.isEmpty,
                  let data = try? Data(contentsOf: files.directory(for: movieId).appending(path: subtitle.fileName)) else { return nil }
            return Self.fingerprint(SubtitleDecoder.decode(data, languageHint: subtitle.language).text)
        })
        var result = Result()
        for (name, data) in candidates {
            guard let format = SubtitleFileName.format(name) else { continue }
            let named = SubtitleFileName.language(name)
            let decoded = SubtitleDecoder.decode(data, languageHint: named)
            let document = SubtitleParser.parse(decoded.text, format: format)
            guard !document.cues.isEmpty else { continue }
            let fingerprint = Self.fingerprint(decoded.text)
            guard known.insert(fingerprint).inserted else {
                result.duplicates += 1
                continue
            }
            let language = named ?? Self.guessLanguage(document)
            var subtitle = MovieSubtitle(
                movieId: movieId, language: language, origin: origin,
                format: MovieSubtitle.Format(rawValue: format.rawValue) ?? .srt, fileName: "",
                addedAt: Int(date.timeIntervalSince1970)
            )
            subtitle.encoding = "utf-8"
            // Stored as UTF-8, whatever it came in.
            subtitle.fileName = try files.write(Data(decoded.text.utf8), named: "\(subtitle.id).\(subtitle.format.rawValue)", for: movieId)
            try store.saveSubtitle(subtitle)
            result.added.append(subtitle)
        }
        if result.added.isEmpty, result.duplicates == 0 { throw Failure.unreadable }
        return result
    }

    /// Line breaks and spacing aside, the same words are the same subtitle.
    private static func fingerprint(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r", with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// From the words, when the file name does not say.
    private static func guessLanguage(_ document: SubtitleDocument) -> String? {
        let sample = document.cues.prefix(80).map(\.plainText).joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage, language != .undetermined,
              (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) > 0.6 else { return nil }
        return MovieLanguage.code(language.rawValue)
    }
}
