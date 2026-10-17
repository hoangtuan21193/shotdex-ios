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
