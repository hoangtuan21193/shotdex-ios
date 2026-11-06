#if DEBUG
import Foundation

/// `-ShotDexDemoLibrary -ShotDexDemoSources`: sources for screenshots of
/// Settings › Sources — a folder of six landscape desktop pictures (no
/// faces), a folder that lost its permission, and the local test SMB share
/// (127.0.0.1:4450) when it answers. The demo database is in memory; the
/// folder is a temporary copy.
enum MacDemoSources {
    static let argument = "-ShotDexDemoSources"

    @MainActor
    static func seedIfAsked(_ dependencies: MacDependencies) async {
        guard MacDemoLibrary.isOn, ProcessInfo.processInfo.arguments.contains(argument) else { return }
        let store = SourceStore(database: dependencies.database)
        let names = Set(((try? store.sources()) ?? []).map(\.name))
        if !names.contains("2026 Japan"), let folder = landscapes() {
            await dependencies.sourcesModel.addFolder(folder, includesSubfolders: true, pairsRawAndJpeg: true)
        }
        if !names.contains("Client Shoots 2026"),
           let id = try? store.addFolder(name: "Client Shoots 2026", bookmark: Data([0]), includesSubfolders: true, pairsRawAndJpeg: true) {
            _ = try? FolderSourceAccess(database: dependencies.database).open(sourceId: id)
        }
        if !names.contains("Test SMB") { _ = await MacDemoLibrary.seedServerSource(dependencies) }
        if MacDemoLibrary.section == "sourceIndexing" { seedSourceIndexing(dependencies, store: store, names: names) }
        dependencies.sourcesModel.load()
    }

    /// `-ShotDexSection sourceIndexing` (board `MAC_SourceIndexing`): a
    /// drive that is offline and holds the RAW files, and "Client Shoots
    /// 2026" being added, a third read.
    @MainActor
    private static func seedSourceIndexing(_ dependencies: MacDependencies, store: SourceStore, names: Set<String>) {
        guard !names.contains("T7 RAW Archive"),
              let drive = try? store.addFolder(name: "T7 RAW Archive", bookmark: Data([0]), includesSubfolders: true,
                                               pairsRawAndJpeg: true, kind: "drive")
        else { return }
        try? store.setOnline(false, sourceId: drive)
        try? dependencies.database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, isOnline, lastSeenAt)
                SELECT 't7:' || m.assetId, m.assetId, ?, 'file', m.originalFilename, lower(m.originalFilename) || m.assetId, 0, 1
                FROM photo_metadata m
                WHERE upper(m.originalFilename) LIKE '%.ARW' OR upper(m.originalFilename) LIKE '%.RAF' OR upper(m.originalFilename) LIKE '%.CR3'
                """, arguments: [drive])
            // Those RAW files live only on the drive, as on the board: offline glyph.
            try db.execute(sql: "DELETE FROM photo_copies WHERE kind = 'photos' AND photoId IN (SELECT photoId FROM photo_copies WHERE sourceId = ?)",
                           arguments: [drive])
        }
        let client = (try? store.sources())?.first(where: { $0.name == "Client Shoots 2026" })?.id ?? drive
        var progress = SourceReadProgress(sourceId: client, sourceName: "Client Shoots 2026", isAdding: true, done: 1240, total: 3812)
        let start = Date().addingTimeInterval(-60)
        for step in 0...12 { progress.estimate.record(processed: step * 100 + 40, at: start.addingTimeInterval(Double(step) * 5)) }
        dependencies.sourcesModel.debugShowRead(progress)
    }

    private static func landscapes() -> URL? {
        let pictures = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails", isDirectory: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexDemoSources/2026 Japan", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["Big Sur Coastline", "Catalina Rock", "Big Sur Mountains", "Catalina Coast", "Big Sur Road", "Catalina Sunset"] {
            let target = folder.appendingPathComponent(name + ".heic")
            if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.copyItem(at: pictures.appendingPathComponent(name + ".heic"), to: target)
            }
        }
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }
}
#endif
