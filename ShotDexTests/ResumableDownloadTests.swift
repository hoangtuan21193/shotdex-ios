import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// A remote file that exists only as arithmetic: byte n is `n % 251`. Reads
/// are counted, so a test can say how much a resume asked for without a
/// gigabyte in memory.
private final class SyntheticFileClient: RemoteFileClient, @unchecked Sendable {
    let size: Int64
    private let lock = NSLock()
    private(set) var reads: [(offset: Int64, length: Int)] = []
    /// Throw `connectionLost` on this read (1-based), once.
    var dropOnRead: Int?

    init(size: Int64) { self.size = size }

    static func byte(at offset: Int64) -> UInt8 { UInt8(offset % 251) }

    var bytesRequested: Int64 { lock.withLock { reads.reduce(0) { $0 + Int64($1.length) } } }

    func fileSize(at path: String) async throws -> Int64? { path == "movie.mkv" ? size : nil }

    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        let number = lock.withLock { reads.append((offset, length)); return reads.count }
        if dropOnRead == number {
            dropOnRead = nil
            throw RemoteFileError.connectionLost
        }
        let end = min(size, offset + Int64(length))
        return Data((offset..<end).map(Self.byte(at:)))
    }

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

/// FS-23.01 §6 — a movie download picks up at the byte it stopped, without
/// reading the file twice.
@Suite struct ResumableDownloadTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "resume-\(UUID().uuidString).part")
    }

    private func tail(of url: URL, from offset: Int64, count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: count) ?? Data()
    }

    /// Plan task 2: resuming from 1.1 GB asks the server for no more than
    /// what is left plus 1 MB, starting at the byte the part ends on.
    @Test func resumesFromOnePointOneGigabytes() async throws {
        let have: Int64 = 1_100_000_000
        let left: Int64 = 18_000_000
        let remote = SyntheticFileClient(size: have + left)
        let local = temporaryFile()
        defer { try? FileManager.default.removeItem(at: local) }
        FileManager.default.createFile(atPath: local.path, contents: nil)
        let handle = try FileHandle(forWritingTo: local)
        try handle.truncate(atOffset: UInt64(have))  // sparse: costs no disk
        try handle.close()

        let reached = try await remote.resumeDownload("movie.mkv", to: local) { _ in }

        #expect(reached == have + left)
        #expect(remote.reads.first?.offset == have)
        #expect(remote.bytesRequested <= left + 1_048_576)
        let attributes = try FileManager.default.attributesOfItem(atPath: local.path)
        #expect((attributes[.size] as? Int64) == have + left)
        let sample = try tail(of: local, from: have + 7_654_321, count: 4)
        #expect(Array(sample) == (0..<4).map { SyntheticFileClient.byte(at: have + 7_654_321 + Int64($0)) })
    }

    @Test func freshDownloadReadsTheFileOnce() async throws {
        let remote = InMemoryRemoteFileClient()
        let movie = Data((0..<9_500_000).map { UInt8($0 % 239) })
        remote.put("Films/Dune.mkv", movie)
        let local = temporaryFile()
        defer { try? FileManager.default.removeItem(at: local) }
        let seen = ProgressLog()

        let reached = try await remote.resumeDownload("Films/Dune.mkv", to: local) { seen.add($0) }

        #expect(reached == Int64(movie.count))
        #expect(try Data(contentsOf: local) == movie)
        #expect(remote.bytesRead == movie.count)
        #expect(seen.values.first == 0)
        #expect(seen.values.last == Int64(movie.count))
        #expect(seen.values == seen.values.sorted())
    }

    /// The connection drops mid-way: what arrived stays, and the next call
    /// carries on from it.
    @Test func dropThenResumeLosesNothing() async throws {
        let remote = SyntheticFileClient(size: 10_000_000)
        remote.dropOnRead = 2
        let local = temporaryFile()
        defer { try? FileManager.default.removeItem(at: local) }

        await #expect(throws: RemoteFileError.connectionLost) {
            try await remote.resumeDownload("movie.mkv", to: local) { _ in }
        }
        let partial = try FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64
        #expect(partial == Int64(ResumableFile.chunkSize))

        let reached = try await remote.resumeDownload("movie.mkv", to: local) { _ in }

        #expect(reached == 10_000_000)
        #expect(remote.bytesRequested <= 10_000_000 + Int64(ResumableFile.chunkSize))
        let data = try Data(contentsOf: local)
        #expect(data == Data((0..<10_000_000).map { SyntheticFileClient.byte(at: Int64($0)) }))
    }

    /// The part is longer than the file on the server now (it was replaced):
    /// start over rather than keep bytes of another file.
    @Test func longerPartStartsOver() async throws {
        let remote = InMemoryRemoteFileClient()
        let movie = Data(repeating: 7, count: 3_000)
        remote.put("Dune.mkv", movie)
        let local = temporaryFile()
        defer { try? FileManager.default.removeItem(at: local) }
        try Data(repeating: 1, count: 5_000).write(to: local)

        let reached = try await remote.resumeDownload("Dune.mkv", to: local) { _ in }

        #expect(reached == 3_000)
        #expect(try Data(contentsOf: local) == movie)
    }

    @Test func finishedPartReadsNothing() async throws {
        let remote = SyntheticFileClient(size: 5_000)
        let local = temporaryFile()
        defer { try? FileManager.default.removeItem(at: local) }
        try Data((0..<5_000).map { SyntheticFileClient.byte(at: Int64($0)) }).write(to: local)

        #expect(try await remote.resumeDownload("movie.mkv", to: local) { _ in } == 5_000)
        #expect(remote.reads.isEmpty)
    }

    @Test func missingFileSaysSo() async throws {
        let remote = SyntheticFileClient(size: 5_000)
        let local = temporaryFile()
        defer { try? FileManager.default.removeItem(at: local) }
        await #expect(throws: RemoteFileError.fileMissing("gone.mkv")) {
            try await remote.resumeDownload("gone.mkv", to: local) { _ in }
        }
    }

    @Test func cancelStopsBetweenChunks() async throws {
        let remote = SyntheticFileClient(size: 40_000_000)
        let local = temporaryFile()
        defer { try? FileManager.default.removeItem(at: local) }
        let task = Task {
            try await remote.resumeDownload("movie.mkv", to: local) { reached in
                if reached >= Int64(ResumableFile.chunkSize) { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(remote.bytesRequested < 40_000_000)
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [Int64] = []
    func add(_ value: Int64) { lock.withLock { log.append(value) } }
    var values: [Int64] { lock.withLock { log } }
}
