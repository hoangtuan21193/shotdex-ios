import AVFoundation
import Foundation

/// A movie file on the device as a byte source.
struct FileByteSource: MovieByteSource {
    let url: URL
    let size: Int64

    init(url: URL) throws {
        self.url = url
        size = Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
    }

    func read(offset: Int64, length: Int) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: length) ?? Data()
    }
}

/// Subtitles inside the movie file (FS-23.03 §1, §3): Matroska text tracks
/// by Cues (or, on the device, by walking the file), MP4 `mov_text` through
/// AVFoundation. Each becomes an `In File` subtitle row; on the device its
/// text is written to `Movies/<id>/` once, so the next open reads nothing;
/// streamed, it stays in memory (AC-3).
struct EmbeddedSubtitleExtractor: Sendable {
    let store: MovieStore
    let files: MovieFileStore

    struct Found: Sendable {
        var subtitle: MovieSubtitle
        /// nil: VLC has to draw it — a picture subtitle, or a streamed
        /// track the Cues do not index (AC-55).
        var document: SubtitleDocument?
        /// Its place among the file's subtitle tracks, which is VLC's order.
        var order: Int
    }

    func extract(movie: Movie, source: any MovieByteSource, isLocal: Bool, localURL: URL?) async -> [Found] {
        let ext = (movie.originalFileName as NSString).pathExtension.lowercased()
        if ["mkv", "mk3d", "webm"].contains(ext) {
            return (try? await matroska(movie: movie, source: source, isLocal: isLocal)) ?? []
        }
        if ["mp4", "m4v", "mov"].contains(ext), let localURL {
            return (try? await movText(movie: movie, url: localURL)) ?? []
        }
        return []
    }

    private func matroska(movie: Movie, source: any MovieByteSource, isLocal: Bool) async throws -> [Found] {
        let reader = MatroskaSubtitleReader(source: source)
        let tracks = try await reader.readTracks()
        guard !tracks.isEmpty else { return [] }
        let existing = try store.subtitles(movieId: movie.id).filter { $0.origin == .inFile }
        // Text already pulled out on an earlier open needs no reading.
        let pending = Set(tracks.filter { track in
            guard track.format != nil else { return false }
            guard let row = existing.first(where: { $0.inFileTrack == Int(track.number) }) else { return true }
            return row.fileName.isEmpty
        }.map(\.number))
        let extraction = try await reader.extract(pending, walkWithoutCues: isLocal)

        var found: [Found] = []
        for (order, track) in tracks.enumerated() {
            var row = existing.first { $0.inFileTrack == Int(track.number) }
                ?? MovieSubtitle(movieId: movie.id, language: MovieLanguage.code(track.language) ?? track.language, origin: .inFile, format: .srt, fileName: "")
            row.inFileTrack = Int(track.number)
            row.format = MovieSubtitle.Format(rawValue: track.format?.rawValue ?? "srt") ?? .srt
            var document: SubtitleDocument?
            if let text = extraction.texts[track.number], let format = track.format {
                document = SubtitleParser.parse(text, format: format)
                if isLocal {
                    row.fileName = try files.write(Data(text.utf8), named: "infile-\(track.number).\(row.format.rawValue)", for: movie.id)
                    row.encoding = "utf-8"
                }
            } else if !row.fileName.isEmpty, let format = track.format,
                      let data = try? Data(contentsOf: files.directory(for: movie.id).appending(path: row.fileName)) {
                document = SubtitleParser.parse(String(decoding: data, as: UTF8.self), format: format)
            }
            try store.saveSubtitle(row)
            found.append(Found(subtitle: row, document: document, order: order))
        }
        return found
    }

    /// MP4 text tracks (`tx3g`/`mov_text`): AVFoundation reads them from a
    /// file on the device only (spike S2 §6).
    private func movText(movie: Movie, url: URL) async throws -> [Found] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .text) + (try await asset.loadTracks(withMediaType: .subtitle))
        let existing = try store.subtitles(movieId: movie.id).filter { $0.origin == .inFile }
        var found: [Found] = []
        for (order, track) in tracks.enumerated() {
            var row = existing.first { $0.inFileTrack == Int(track.trackID) }
                ?? MovieSubtitle(movieId: movie.id, language: nil, origin: .inFile, format: .srt, fileName: "")
            let language = try? await track.load(.languageCode)
            row.language = MovieLanguage.code(language) ?? row.language
            row.inFileTrack = Int(track.trackID)
            let cues = try Self.cues(of: track, in: asset)
            let document = SubtitleDocument(cues: cues)
            if row.fileName.isEmpty {
                row.fileName = try files.write(Data(Self.srt(cues).utf8), named: "infile-\(track.trackID).srt", for: movie.id)
                row.encoding = "utf-8"
            }
            try store.saveSubtitle(row)
            found.append(Found(subtitle: row, document: document, order: order))
        }
        return found
    }

    private static func cues(of track: AVAssetTrack, in asset: AVAsset) throws -> [SubtitleCue] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var cues: [SubtitleCue] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(buffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer, length >= 2 else { continue }
            let raw = UnsafeRawPointer(pointer)
            // tx3g: a 16-bit text length, then UTF-8.
            let textLength = Int(raw.load(as: UInt8.self)) << 8 | Int(raw.load(fromByteOffset: 1, as: UInt8.self))
            guard textLength > 0 else { continue }
            let text = String(decoding: UnsafeRawBufferPointer(start: raw + 2, count: min(textLength, length - 2)), as: UTF8.self)
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let duration = CMSampleBufferGetDuration(sample).seconds
            guard start.isFinite else { continue }
            let startMs = Int64((start * 1000).rounded())
            let endMs = startMs + Int64(((duration.isFinite ? duration : 2) * 1000).rounded())
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { [SubtitleRun(text: String($0))] }
            cues.append(SubtitleCue(startMs: startMs, endMs: endMs, lines: lines))
        }
        return cues
    }

    private static func srt(_ cues: [SubtitleCue]) -> String {
        func stamp(_ ms: Int64) -> String {
            String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1_000 % 60, ms % 1_000)
        }
        return cues.enumerated().map { "\($0.offset + 1)\n\(stamp($0.element.startMs)) --> \(stamp($0.element.endMs))\n\($0.element.plainText)\n" }.joined(separator: "\n")
    }
}
