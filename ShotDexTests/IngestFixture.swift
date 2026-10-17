import Foundation
@testable import ShotDex

/// A memory card as a folder (`DCIM/…` in a temporary directory) and a
/// destination folder, for the card import tests.
final class IngestFixture: @unchecked Sendable {
    let card: URL
    let destination: URL
    let backup: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Ingest-\(UUID().uuidString)", isDirectory: true)
        card = base.appendingPathComponent("EOS_DIGITAL", isDirectory: true)
        destination = base.appendingPathComponent("T7 RAW Archive", isDirectory: true)
        backup = base.appendingPathComponent("LaCie Backup", isDirectory: true)
        for url in [card, destination, backup] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func cleanUp() { try? FileManager.default.removeItem(at: card.deletingLastPathComponent()) }

    /// A file of `bytes` pseudo-random bytes (different per path), dated `date`.
    func add(_ path: String, bytes: Int, date: Date) throws {
        let url = card.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var seed = UInt64(truncatingIfNeeded: path.hashValue) | 1
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { raw in
            for i in 0..<bytes {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                raw[i] = UInt8(truncatingIfNeeded: seed >> 33)
            }
        }
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func reader() -> FolderCardReader { FolderCardReader(root: card) }

    func plan(_ reader: any CardReader, template: FileNameTemplate = .originalName,
              folders: IngestFolderTemplate = IngestFolderTemplate(pattern: ""),
              writer: LocalFolderWriter? = nil) async throws -> FileExportPlan {
        let items = CardCatalog.items(try await reader.list()).map { IngestPlan.exportItem($0) }
        let destination = writer ?? LocalFolderWriter(root: destination)
        var existing: [String: Set<String>] = [:]
        for folder in IngestPlan.folders(for: items, template: folders, timeZone: IngestRunnerTests.utc) {
            existing[folder] = try await destination.existingNames(in: folder)
        }
        return IngestPlan.make(items, template: template, folders: folders, existing: existing, timeZone: IngestRunnerTests.utc)
    }

    func importAll(template: FileNameTemplate = .originalName,
                   folders: IngestFolderTemplate = IngestFolderTemplate(pattern: ""),
                   reader: (any CardReader)? = nil,
                   writer: LocalFolderWriter? = nil,
                   backupWriter: LocalFolderWriter? = nil) async throws -> (IngestSummary, [IngestEvent]) {
        let reader = reader ?? self.reader()
        let plan = try await plan(reader, template: template, folders: folders, writer: writer)
        let log = EventLog()
        let runner = IngestRunner(card: reader, plan: plan,
                                  primary: IngestTarget(destination: writer ?? LocalFolderWriter(root: destination), name: "T7 RAW Archive"),
                                  backup: backupWriter.map { IngestTarget(destination: $0, name: "LaCie Backup") },
                                  onEvent: { await log.append($0) })
        let summary = await runner.run()
        return (summary, await log.events)
    }

    /// Every file under the destination, relative, sorted.
    func destinationFiles(in root: URL? = nil) throws -> [String] {
        let root = (root ?? destination).standardizedFileURL
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        var out: [String] = []
        while let url = walk?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            out.append(String(url.standardizedFileURL.path.dropFirst(root.path.count + 1)))
        }
        return out.sorted()
    }

    func sha(_ path: String, onDestination: Bool) throws -> String {
        try FileChecksum.sha256(of: (onDestination ? destination : card).appendingPathComponent(path))
    }
}

actor EventLog {
    private(set) var events: [IngestEvent] = []
    func append(_ event: IngestEvent) { events.append(event) }
}

/// A card that fails on a chosen file: pulled out there, or slow.
struct FaultyCardReader: CardReader {
    let inner: FolderCardReader
    var disconnectsAt: String?
    /// A pause per chunk, to stop mid-file.
    var chunkDelay: Duration = .zero
    var name: String { inner.name }

    func list() async throws -> [CardFile] { try await inner.list() }

    func read(_ path: String, chunkSize: Int, _ body: (Data) throws -> Void) async throws {
        if let disconnectsAt, path.hasSuffix(disconnectsAt) { throw IngestFailure.cardDisconnected }
        if chunkDelay == .zero {
            try await inner.read(path, chunkSize: chunkSize, body)
            return
        }
        // Small chunks with a pause between them: a long file to stop in.
        let data = try Data(contentsOf: inner.root.appendingPathComponent(path))
        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            try await Task.sleep(for: chunkDelay)
            let end = min(offset + 64 * 1024, data.count)
            try body(data.subdata(in: offset..<end))
            offset = end
        }
    }
}

/// A destination that refuses from its `failsFrom`-th write on.
final class FailingDestination: IngestDestination, @unchecked Sendable {
    let inner: LocalFolderWriter
    let failsFrom: Int
    let failure: IngestFailure
    private let lock = NSLock()
    private var writes = 0

    init(_ inner: LocalFolderWriter, failsFrom: Int, failure: IngestFailure) {
        self.inner = inner
        self.failsFrom = failsFrom
        self.failure = failure
    }

    func existingNames(in folder: String) async throws -> Set<String> { try await inner.existingNames(in: folder) }
    func freeBytes() async -> Int64? { await inner.freeBytes() }
    func sweepLeftoverParts(in folder: String) async { await inner.sweepLeftoverParts(in: folder) }
    func remove(_ path: String) async { await inner.remove(path) }

    func writeVerified(name: String, in folder: String, produce: @Sendable (URL) async throws -> String) async throws -> ExportWrittenFile {
        let count = lock.withLock { writes += 1; return writes }
        if count >= failsFrom { throw failure }
        return try await inner.writeVerified(name: name, in: folder, produce: produce)
    }
}

extension IngestFixture {
    /// Ten photos `IMG_0001.JPG`…`IMG_0010.JPG`, a minute apart.
    func addTen(bytes: Int = 200_000) throws {
        for n in 1...10 {
            try add(String(format: "DCIM/100CANON/IMG_%04d.JPG", n), bytes: bytes,
                    date: IngestRunnerTests.shot.addingTimeInterval(Double(n) * 60))
        }
    }

    func runner(reader: any CardReader, plan: FileExportPlan, primary: any IngestDestination,
                backup: (any IngestDestination)? = nil) -> IngestRunner {
        IngestRunner(card: reader, plan: plan, primary: IngestTarget(destination: primary, name: "T7 RAW Archive"),
                     backup: backup.map { IngestTarget(destination: $0, name: "LaCie Backup") })
    }

    func parts() throws -> [String] {
        try (destinationFiles() + destinationFiles(in: backup)).filter { $0.hasSuffix(ServerUploadPath.partSuffix) }
    }
}
