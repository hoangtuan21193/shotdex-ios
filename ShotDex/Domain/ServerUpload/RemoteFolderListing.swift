import Foundation

/// What the folder browser shows of a server folder (FS-15.02 §2a).
enum RemoteFolderListing {
    /// Folders a photographer would pick: no dot folders (`.snapshots`,
    /// `.Trash`), in Finder order — `2` before `10`.
    static func visible(_ names: some Sequence<String>) -> [String] {
        names
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A typed New Folder name, trimmed; nil when empty or when it holds a
    /// `/`, which would make it a path.
    static func validatedName(_ typed: String) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return nil }
        return name
    }
}
