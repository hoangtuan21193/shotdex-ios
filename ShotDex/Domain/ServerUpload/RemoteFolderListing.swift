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

    /// A typed New Folder or Rename name, trimmed; nil when empty, when it
    /// holds a `/` (a path), or when it starts with `.` — the browser hides
    /// dot files, so the new item would vanish (FS-17.01 §2c).
    static func validatedName(_ typed: String) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return name
    }
}
