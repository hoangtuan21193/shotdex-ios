import Foundation

/// Where kept photos and videos live on the device: `Kept/<id>/<file>`, with
/// downloads in progress under `Kept/.incoming/`. Application Support — not
/// Documents (it must not show in Files), not Caches (the system may empty
/// Caches when the device is full, and these are the user's) — and excluded
/// from iCloud backup as a whole. Same shape as Movik's movie store.
struct KeptFileStore: Sendable {
    let root: URL

    static var standard: KeptFileStore {
        KeptFileStore(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Kept", directoryHint: .isDirectory))
    }

    var incoming: URL { root.appending(path: ".incoming", directoryHint: .isDirectory) }

    /// A photo id is a PhotoKit local identifier ("ABC/L0/001"): slashes are
    /// not a folder name.
    static func folderName(for id: String) -> String {
        id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
    }

    func directory(for id: String) -> URL {
        root.appending(path: Self.folderName(for: id), directoryHint: .isDirectory)
    }

    func file(for item: KeptItem) -> URL? {
        guard item.state == .onDevice, let name = item.fileName else { return nil }
        return directory(for: item.id).appending(path: name)
    }

    /// A fresh scratch folder for one download; `finish` moves its file in.
    func makeWorkFolder() throws -> URL {
        let folder = incoming.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Creates the folders and keeps them out of backups.
    func prepare() throws {
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        var root = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }

    /// Moves a finished file to `Kept/<id>/<name>` and returns its size.
    func finish(_ file: URL, id: String, as name: String) throws -> (name: String, bytes: Int64) {
        let folder = directory(for: id)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = Self.safeName(name)
        let target = folder.appending(path: safe)
        try FileManager.default.moveItem(at: file, to: target)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int64) ?? 0
        return (safe, bytes)
    }

    func remove(id: String) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }

    /// Launch sweep: scratch folders and folders no row explains go; returns
    /// the ids whose row says "on device" with no file there, so the caller
    /// marks them missing — never deletes them.
    func sweep(items: [KeptItem]) -> [String] {
        let fm = FileManager.default
        try? fm.removeItem(at: incoming)
        try? fm.createDirectory(at: incoming, withIntermediateDirectories: true)
        let known = Set(items.map { Self.folderName(for: $0.id) })
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent != ".incoming" && !known.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
        return items.filter { item in
            item.state == .onDevice && !(file(for: item).map { fm.fileExists(atPath: $0.path) } ?? false)
        }.map(\.id)
    }

    static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "kept" : cleaned
    }

    /// Bytes free for important use on this device.
    static func freeSpace() -> Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
