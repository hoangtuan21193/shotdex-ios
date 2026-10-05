import CryptoKit
import Foundation

/// What analysing sound found — a track's beats (FS-12.12 §4), later a
/// clip's voices (FS-12.13 §4) — kept as JSON in Caches, never in a recipe:
/// it is derived data, and the analysis is deterministic, so a lost cache
/// only costs the time to find it again. A write that fails (the disk is
/// full) keeps the result in memory for the session.
actor AudioAnalysisCache {
    private let directory: URL?
    private var memory: [String: Data] = [:]

    /// `directory` nil keeps everything in memory — the tests' cache.
    init(directory: URL? = AudioAnalysisCache.defaultDirectory) {
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AudioAnalysis", isDirectory: true)
    }

    /// A file's identity for its beats: its name, size and modification
    /// date — the same file copied again, or edited, is analysed again.
    static func fileKey(_ url: URL, kind: String) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        let size = values.fileSize ?? 0
        let date = Int((values.contentModificationDate ?? .distantPast).timeIntervalSince1970)
        return hashed("\(kind)|\(url.lastPathComponent)|\(size)|\(date)")
    }

    static func hashed(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        if let data = memory[key] { return try? JSONDecoder().decode(type, from: data) }
        guard let url = directory?.appendingPathComponent(key + ".json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        memory[key] = data
        return try? JSONDecoder().decode(type, from: data)
    }

    func store<T: Encodable>(_ value: T, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        memory[key] = data
        if let url = directory?.appendingPathComponent(key + ".json") {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// A music file's beats (FS-12.12 §4): from the cache, or decoded at
/// 11 025 Hz mono and run through `BeatDetector`. No network, ever.
struct MusicBeatAnalyzer: Sendable {
    let cache: AudioAnalysisCache

    enum Failure: Error, Equatable { case unreadable }

    func analysis(for url: URL) async throws -> BeatAnalysis {
        let key = AudioAnalysisCache.fileKey(url, kind: "beats")
        if let key, let cached = await cache.value(BeatAnalysis.self, for: key) { return cached }
        let samples: [Float]
        do {
            samples = try await AudioPCMReader.read(url, sampleRate: BeatDetector.sampleRate)
        } catch AudioPCMReader.ReadError.cancelled {
            throw CancellationError()
        } catch {
            throw Failure.unreadable
        }
        try Task.checkCancellation()
        let analysis = BeatDetector.analyze(samples)
        try Task.checkCancellation()
        if let key { await cache.store(analysis, for: key) }
        return analysis
    }
}
