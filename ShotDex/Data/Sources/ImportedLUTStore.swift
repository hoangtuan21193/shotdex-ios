import Foundation

/// One user-imported `.cube` LUT that persists across sessions.
struct ImportedLUT: Identifiable, Equatable, Sendable {
    /// Stable UUID stem — also the on-disk filename stem.
    let id: String
    let displayName: String
    let url: URL
}

/// Persists LUTs the user imports from Files.
///
/// Same shape and the same reasoning as `ImportedMusicStore`: a colourist
/// owns look packs, brings them in once, and expects them to still be there
/// next week. Application Support so they survive launches and stay out of
/// the document browser; a JSON manifest keeps the display names, because a
/// UUID stem is not a name.
///
/// Reads and writes, so `*Store`.
@MainActor
@Observable
final class ImportedLUTStore {
    private(set) var luts: [ImportedLUT] = []

    private let directory: URL
    private let manifestURL: URL
    private var names: [String: String] = [:]

    /// Where a LUT lives, from its id alone.
    ///
    /// Static and nonisolated on purpose: the compositor runs on
    /// AVFoundation's queue and cannot ask a main-actor store anything, and
    /// threading a URL through four call sites to say what the id already
    /// says is worse than agreeing on the path.
    nonisolated static func fileURL(for id: String) -> URL {
        storageDirectory().appendingPathComponent(id).appendingPathExtension("cube")
    }

    nonisolated private static func storageDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ImportedLUTs", isDirectory: true)
    }

    init() {
        directory = Self.storageDirectory()
        manifestURL = directory.appendingPathComponent("names.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadManifest()
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        luts = files
            .filter { $0.pathExtension.lowercased() == "cube" }
            .sorted { (modified($0) ?? .distantPast) > (modified($1) ?? .distantPast) }
            .map { url in
                let id = url.deletingPathExtension().lastPathComponent
                return ImportedLUT(id: id, displayName: names[id] ?? id, url: url)
            }
    }

    func url(for id: String) -> URL? {
        luts.first { $0.id == id }?.url
    }

    /// Copies a security-scoped Files pick into persistent storage.
    ///
    /// The file is **parsed before it is kept**: a `.cube` that does not
    /// read is rejected here, where the user is still looking at the picker
    /// and can pick another, rather than silently doing nothing to the
    /// picture later.
    @discardableResult
    func add(from pickedURL: URL) throws -> ImportedLUT {
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessing { pickedURL.stopAccessingSecurityScopedResource() } }

        let text = try String(contentsOf: pickedURL, encoding: .utf8)
        let parsed = try CubeLUTParser.parse(text)

        let id = UUID().uuidString
        let destination = directory.appendingPathComponent(id).appendingPathExtension("cube")
        try text.write(to: destination, atomically: true, encoding: .utf8)

        let fileName = pickedURL.deletingPathExtension().lastPathComponent
        let name = parsed.title ?? (fileName.isEmpty ? String(localized: "Imported LUT") : fileName)
        names[id] = name
        saveManifest()
        reload()
        return ImportedLUT(id: id, displayName: name, url: destination)
    }

    func delete(_ lut: ImportedLUT) {
        try? FileManager.default.removeItem(at: lut.url)
        names.removeValue(forKey: lut.id)
        VideoLUTTableCache.shared.forget(lut.id)
        saveManifest()
        reload()
    }

    private func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        names = decoded
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(names) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
