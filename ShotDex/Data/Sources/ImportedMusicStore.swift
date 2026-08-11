import Foundation

/// One user-imported music bed that persists across sessions.
struct ImportedMusicTrack: Identifiable, Equatable, Sendable {
    /// Stable UUID stem — also the on-disk filename stem.
    let id: String
    let displayName: String
    let url: URL
}

/// Persists music the user imports from Files so it can be reused in later
/// sessions (unlike clip/project data, which is session-ephemeral). Files live
/// in Application Support so they survive app launches and are excluded from the
/// user's document browser; a small JSON manifest keeps the display names.
///
/// This is the *legal* alternative to ripping audio from streaming services:
/// the user brings audio they already have the right to use, and it is stored
/// for reuse. Reads and writes, so `*Store`.
@MainActor
final class ImportedMusicStore: ObservableObject {
    @Published private(set) var tracks: [ImportedMusicTrack] = []

    private let directory: URL
    private let manifestURL: URL
    private var names: [String: String] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ImportedMusic", isDirectory: true)
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
        tracks = files
            .filter { $0.pathExtension.lowercased() != "json" }
            .sorted { (modified($0) ?? .distantPast) > (modified($1) ?? .distantPast) }
            .map { url in
                let id = url.deletingPathExtension().lastPathComponent
                return ImportedMusicTrack(id: id, displayName: names[id] ?? id, url: url)
            }
    }

    /// Copies a security-scoped Files pick into persistent storage and returns
    /// the reusable track.
    @discardableResult
    func add(from pickedURL: URL) throws -> ImportedMusicTrack {
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessing { pickedURL.stopAccessingSecurityScopedResource() } }

        let id = UUID().uuidString
        let ext = pickedURL.pathExtension.isEmpty ? "m4a" : pickedURL.pathExtension
        let destination = directory.appendingPathComponent(id).appendingPathExtension(ext)
        try FileManager.default.copyItem(at: pickedURL, to: destination)

        let base = pickedURL.deletingPathExtension().lastPathComponent
        let name = base.isEmpty ? String(localized: "Imported") : base
        names[id] = name
        saveManifest()
        reload()
        return ImportedMusicTrack(id: id, displayName: name, url: destination)
    }

    func delete(_ track: ImportedMusicTrack) {
        try? FileManager.default.removeItem(at: track.url)
        names[track.id] = nil
        saveManifest()
        reload()
    }

    private func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        names = map
    }

    private func saveManifest() {
        if let data = try? JSONEncoder().encode(names) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }
}
