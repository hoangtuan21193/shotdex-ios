import Foundation

/// Connection names (FS-15.01 §3). The same server can be added several
/// times — one per folder or login — and the name is all that tells them
/// apart in the ⋯ menu, so no two may read the same.
enum FileServerNaming {
    /// `name` if no other connection uses it (ignoring case), else the first
    /// free `name (2)`, `name (3)`, …. Unlike Keep Both's file names there is
    /// no extension to keep: `nas.local` is a host, not `nas` + `.local`.
    static func uniqueName(_ name: String, existing: some Sequence<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var n = 2
        while taken.contains("\(name) (\(n))".lowercased()) { n += 1 }
        return "\(name) (\(n))"
    }
}
