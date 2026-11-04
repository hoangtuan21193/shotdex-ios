import Foundation

/// The shared preview cache as a whole (FS-19 01b §3, Mac Settings › Sources
/// › Previews, FS-18.04 §3 AC-76): how much it holds, held to the limit the
/// user picked, and emptied on Clear Cache. Thumbnails live under
/// `Thumbnails/` (folders and drives) and `Servers/`; anything else in it is
/// a full-size preview and goes first (`PreviewCacheEviction`).
struct PreviewCacheStore: Sendable {
    let directory: URL

    static var standard: PreviewCacheStore { PreviewCacheStore(directory: PreviewCacheLocation.standard) }

    static let thumbnailFolders = ["Thumbnails", PreviewCachePolicy.serverFolderName]
    static let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]

    /// Bytes on disk.
    func usage() -> Int64 {
        Self.groups(files(), kind: kind(of:)).reduce(0) { $0 + $1.item.size }
    }

    /// Deletes until the cache is at or under `limit`: previews first, then
    /// the thumbnails used longest ago.
    func trim(to limit: Int64) {
        Self.evict(Self.groups(files(), kind: kind(of:)), limit: limit)
    }

    /// Clear Cache: everything goes; the folders come back empty, still out of backups.
    func clear() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents { try? FileManager.default.removeItem(at: url) }
        PreviewCacheLocation.prepare(directory)
        for folder in Self.thumbnailFolders {
            PreviewCacheLocation.prepare(directory.appendingPathComponent(folder, isDirectory: true))
        }
    }

    private func files() -> [URL] {
        guard let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Self.keys) else { return [] }
        return walk.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    /// By the folder right under the cache, compared by path component, not by string length.
    private func kind(of url: URL) -> PreviewCacheEviction.Kind {
        let base = directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let path = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard path.starts(with: base), path.count > base.count else { return .preview }
        return Self.thumbnailFolders.contains(path[base.count]) ? .thumbnail : .preview
    }

    /// A thumbnail and its sidecar (`<key>.jpg` + `<key>.json` in `Servers/`)
    /// are one item: evicting half of one leaves a record that says "cached"
    /// with nothing behind it. Last used is the newer of the two
    /// (modification date: what every writer touches; APFS keeps no reliable
    /// access date).
    static func groups(_ urls: [URL], kind: (URL) -> PreviewCacheEviction.Kind) -> [(item: PreviewCacheEviction.Item, urls: [URL])] {
        let byStem = Dictionary(grouping: urls) { $0.deletingPathExtension().path }
        return byStem.values.map { members in
            var size: Int64 = 0
            var lastUsed = Date.distantPast
            for url in members {
                let values = try? url.resourceValues(forKeys: Set(keys))
                size += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                lastUsed = max(lastUsed, values?.contentModificationDate ?? .distantPast)
            }
            let first = members.sorted { $0.path < $1.path }[0]
            return (PreviewCacheEviction.Item(url: first, kind: kind(first), size: size, lastUsed: lastUsed), members)
        }
    }

    static func evict(_ groups: [(item: PreviewCacheEviction.Item, urls: [URL])], limit: Int64) {
        let members = Dictionary(groups.map { ($0.item.url, $0.urls) }) { first, _ in first }
        for victim in PreviewCacheEviction.victims(groups.map(\.item), limit: limit) {
            for url in members[victim.url] ?? [victim.url] { try? FileManager.default.removeItem(at: url) }
        }
    }
}
