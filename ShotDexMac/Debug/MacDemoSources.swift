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
        dependencies.sourcesModel.load()
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
