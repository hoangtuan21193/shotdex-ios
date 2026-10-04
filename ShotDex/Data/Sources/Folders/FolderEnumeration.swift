import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a folder source holds (FS-19.01 §2): every image and video the
/// system can read, and the `.xmp` sidecars beside them. Never a package —
/// the Photos library sits in `~/Pictures`, and reading it would mean
/// reading Photos' private store and doubling the Photos source — and never
/// anything whose name starts with a dot.
enum FolderEnumeration {
    struct Entry: Equatable, Sendable {
        /// Relative to the source folder, `/`-separated.
        let relativePath: String
        let size: Int64
        let modified: Date?
        let isSidecar: Bool
    }

    /// Package extensions the system may not know on every platform (the
    /// Photos library is not a registered package on iOS).
    static let knownPackageExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary",
        "lrdata", "lrlibrary", "cocatalog", "cocatalogdb", "fcpbundle",
    ]

    /// Types ImageIO reads, plus every movie type.
    static let readableImageTypes: Set<String> = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])

    static func isReadable(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return readableImageTypes.contains(type.identifier) || type.conforms(to: .rawImage) || type.conforms(to: .movie)
    }

    static func entries(in root: URL, includeSubfolders: Bool) -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !includeSubfolders { options.insert(.skipsSubdirectoryDescendants) }
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: options) else { return [] }
        let rootPath = root.standardizedFileURL.path
        var out: [Entry] = []
        for case let url as URL in walk {
            let name = url.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if values?.isPackage == true || knownPackageExtensions.contains(url.pathExtension.lowercased())
                    || UTType(filenameExtension: url.pathExtension)?.conforms(to: .package) == true {
                    walk.skipDescendants()
                }
                continue
            }
            let isSidecar = url.pathExtension.lowercased() == "xmp"
            guard isSidecar || isReadable(url) else { continue }
            var relative = url.standardizedFileURL.path
            if relative.hasPrefix(rootPath) { relative.removeFirst(rootPath.count) }
            if relative.hasPrefix("/") { relative.removeFirst() }
            out.append(Entry(relativePath: relative, size: Int64(values?.fileSize ?? 0),
                             modified: values?.contentModificationDate, isSidecar: isSidecar))
        }
        return out.sorted { $0.relativePath < $1.relativePath }
    }
}
