import Foundation
import Testing
import UIKit
@testable import ShotDex

/// FS-23.01 §3, AC-3: a streamed movie is read on demand from its source —
/// no copy on the device, only the bytes playback asks for.
@Suite(.serialized) @MainActor struct MovieStreamTests {
    /// A file that exists only as arithmetic, reads counted.
    private final class Arithmetic: RemoteFileClient, @unchecked Sendable {
        let size: Int64
        private let lock = NSLock()
        private(set) var requested: Int64 = 0
        var failing = false
        init(size: Int64) { self.size = size }
        static func byte(_ n: Int64) -> UInt8 { UInt8(truncatingIfNeeded: n &* 13) }
        func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
            if failing { throw RemoteFileError.unreachable(host: "nas") }
            lock.withLock { requested += Int64(length) }
            return Data((offset..<min(size, offset + Int64(length))).map(Self.byte))
        }
        func fileSize(at path: String) async throws -> Int64? { size }
        func connect() async throws {}
        func disconnect() async {}
        func directoryExists(_ path: String) async throws -> Bool { false }
        func fileNames(in directory: String) async throws -> Set<String> { [] }
        func folderNames(in directory: String) async throws -> Set<String> { [] }
        func createDirectory(_ path: String) async throws {}
        func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {}
        func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String { "" }
        func entries(in directory: String) async throws -> [RemoteEntry] { [] }
        func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String { "" }
        func move(_ source: String, to destination: String) async throws {}
        func remove(_ path: String) async throws {}
        func removeEmptyDirectory(_ path: String) async throws {}
    }

    /// Reads happen on a thread of their own, as VLC's input thread does.
    private func read(_ stream: RemoteMovieStream, count: Int) async -> Data {
        await onOwnThread {
            var out = Data()
            var buffer = [UInt8](repeating: 0, count: 32_768)
            while out.count < count {
                let n = stream.read(&buffer, maxLength: min(buffer.count, count - out.count))
                if n <= 0 { break }
                out.append(buffer, count: n)
            }
            return out
        }
    }

    /// Only what was read is fetched: 1 MB of a 100 MB movie costs one
    /// chunk; a jump to the end costs the last chunk, not the middle.
    @Test func fetchesOnlyWhatIsRead() async {
        let nas = Arithmetic(size: 100_000_000)
        let stream = RemoteMovieStream(client: nas, path: "Dune.mkv", size: nas.size, chunk: 1 << 20)
        stream.open()

        let head = await read(stream, count: 1_000_000)
        #expect(head == Data((0..<1_000_000).map { Arithmetic.byte(Int64($0)) }))
        #expect(nas.requested == 1 << 20)

        #expect(stream.setProperty(NSNumber(value: 99_999_000), forKey: .fileCurrentOffsetKey))
        let tail = await read(stream, count: 2_000)
        #expect(tail.count == 1_000)
        #expect(tail.first == Arithmetic.byte(99_999_000))
        #expect(nas.requested == (1 << 20) + 1_000)
        #expect(stream.stats.seeks == 1)
    }

    /// SFTP reads in 128 000-byte requests (S1).
    @Test func sftpChunks() async {
        let nas = Arithmetic(size: 1_000_000)
        let stream = RemoteMovieStream(client: nas, path: "a", size: nas.size, chunk: 128_000)
        stream.open()
        _ = await read(stream, count: 300_000)
        #expect(nas.requested == 384_000)
    }

    @Test func serverGoneEndsTheRead() async {
        let nas = Arithmetic(size: 1_000_000)
        nas.failing = true
        let stream = RemoteMovieStream(client: nas, path: "a", size: nas.size)
        stream.open()
        let got = await read(stream, count: 10)
        #expect(got.isEmpty)
        #expect(stream.streamError != nil)
    }

    /// AC-3 (engine half): VLC plays a movie from a source through the
    /// stream, and nothing lands in Movies/.
    @Test func streamsWithoutCopy() async throws {
        let clip = try Data(contentsOf: MoviePlayerFormatsTests.folder.appending(path: "clip.mkv"))
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/clip.mkv", clip)
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "movies-\(UUID().uuidString)"))
        try files.prepare()
        let stream = RemoteMovieStream(client: nas, path: "Movies/clip.mkv", size: Int64(clip.count))
        let engine = VLCMoviePlayer(input: .stream(stream, fileName: "clip.mkv"))
        engine.view.frame = CGRect(x: 0, y: 0, width: 160, height: 90)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.addSubview(engine.view)
        let started = Date()
        engine.play()
        var firstPicture: Double?
        while Date().timeIntervalSince(started) < 12, engine.timeMs < 4_000 {
            if firstPicture == nil, engine.timeMs > 0 { firstPicture = Date().timeIntervalSince(started) }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(engine.timeMs >= 4_000)
        #expect((firstPicture ?? 99) <= 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.root.path).filter { $0 != ".incoming" }.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.incoming.path).isEmpty)
        engine.close()
        engine.view.removeFromSuperview()
    }
}
