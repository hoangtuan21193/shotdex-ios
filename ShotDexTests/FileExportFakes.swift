import CryptoKit
import Foundation
import os
@testable import ShotDex
import ShotDexKit

/// Assets as files on disk, read the way PhotoKit hands them over: in
/// blocks, cancellable between blocks.
final class FixtureExportSource: ExportAssetSource, @unchecked Sendable {
    struct State {
        var copies: [String] = []
        var failures: [String: Error] = [:]
    }

    let directory: URL
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// A pause per block, so a test can cancel mid-file.
    var blockDelay: Duration = .zero
    static let blockSize = 1 << 20

    init(directory: URL) {
        self.directory = directory
    }

    /// Every `copy` asked for, by file key.
    var copies: [String] { state.withLock { $0.copies } }

    func fail(_ key: String, with error: Error) { state.withLock { $0.failures[key] = error } }
    func heal(_ key: String) { state.withLock { $0.failures[key] = nil } }

    func url(for key: String) -> URL { directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_")) }

    func copy(_ file: FileExportSourceFile, of item: FileExportItem, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let failure = state.withLock { state -> Error? in
            state.copies.append(file.key)
            return state.failures[file.key]
        }
        if let failure { throw failure }
        let input = try FileHandle(forReadingFrom: self.url(for: file.key))
        defer { try? input.close() }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        try output.truncate(atOffset: 0)
        while let block = try input.read(upToCount: Self.blockSize), !block.isEmpty {
            try Task.checkCancellation()
            if blockDelay > .zero { try await Task.sleep(for: blockDelay) }
            try output.write(contentsOf: block)
        }
    }
}

/// Builds assets for a test: bytes on disk and the item that names them.
struct ExportFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileExportTest-\(UUID().uuidString)", isDirectory: true)
    var sourceDirectory: URL { root.appendingPathComponent("source", isDirectory: true) }
    var destination: URL { root.appendingPathComponent("Exports", isDirectory: true) }
    let source: FixtureExportSource

    static let utc = TimeZone(identifier: "UTC")!

    init() {
        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        try? FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("Exports"), withIntermediateDirectories: true)
        source = FixtureExportSource(directory: sourceDirectory)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    /// 2026-09-20 + `minutes` past 17:00 UTC.
    static func date(day: Int = 20, minutes: Int = 0) -> Date {
        var components = DateComponents(year: 2026, month: 9, day: day, hour: 17, minute: minutes)
        components.timeZone = utc
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    /// A file of the asset, written to disk.
    func file(_ assetId: String, _ name: String, role: FileExportSourceFile.Role, data: Data, isRAW: Bool = false) throws -> FileExportSourceFile {
        let key = "\(assetId)-\(role.rawValue)-\(name)"
        try data.write(to: source.url(for: key))
        return FileExportSourceFile(key: key, filename: name, role: role, isRAW: isRAW, byteCount: Int64(data.count))
    }

    static func randomData(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    func writer() -> LocalFolderWriter { LocalFolderWriter(root: destination) }

    func runner(
        rendering: any ExportRendering = KitExportRenderer(),
        writer: (any ExportDestinationWriter)? = nil,
        onEvent: @escaping @Sendable (FileExportRunner.Event) -> Void = { _ in }
    ) -> FileExportRunner {
        FileExportRunner(source: source, writer: writer ?? self.writer(), rendering: rendering,
                         workDirectory: root.appendingPathComponent("work"), onEvent: onEvent)
    }

    func plan(
        _ items: [FileExportItem],
        mode: FileExportMode,
        template: FileNameTemplate = .originalName,
        policy: FileExportConflictPolicy = .keepBoth,
        dateFolders: Bool = false,
        livePhotoVideo: Bool = true,
        renderExtension: String = "jpg"
    ) throws -> FileExportPlan {
        var existing: [String: Set<String>] = [:]
        for folder in FileExportPlan.folders(for: items, dateFolders: dateFolders, timeZone: Self.utc) {
            existing[folder] = (try? FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent(folder).path)).map(Set.init) ?? []
        }
        return FileExportPlan.make(
            items: items, mode: mode, template: template, policy: policy, dateFolders: dateFolders,
            includesLivePhotoVideo: livePhotoVideo, renderExtension: { _ in renderExtension },
            existing: existing, timeZone: Self.utc
        )
    }

    /// Names in the export folder (not recursive).
    func names(_ folder: String = "") -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent(folder).path)) ?? []).sorted()
    }

    static func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}
