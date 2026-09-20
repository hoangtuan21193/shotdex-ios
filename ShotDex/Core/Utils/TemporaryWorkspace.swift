import Foundation

/// The app's scratch directories under `/tmp`, and the sweep that removes the
/// ones nobody came back for.
///
/// Every tool that copies a file out of the photo library works in a
/// directory of its own — the editor's session source, a drag's exported
/// file, a drop's imported file, the Video Studio's session media — and each
/// removes its own on the way out. None of them get that chance when the app
/// is force-quit, crashes, or is killed for memory mid-edit, and a leftover
/// directory can hold a copied RAW.
///
/// The system purges `/tmp` eventually, on its own schedule and under its own
/// pressure rules. This is the app taking responsibility for its own litter
/// at the one moment it is certain nothing is using it: the launch after.
enum TemporaryWorkspace {
    /// Prefixes the app creates. A directory (or file) whose name starts with
    /// one of these was ours and, at launch, is not in use by anyone.
    static let prefixes = [
        "ShotDexPhoto-",
        "ShotDexDrag-",
        "ShotDexDrop-",
        "ShotDexVideo-",
        "ShotDex-Video-",
    ]

    /// Removes every leftover scratch directory. Safe to call only at launch,
    /// before any session exists — it cannot tell a live directory from a
    /// dead one, and at launch there are none alive.
    static func sweepOrphans(
        in directory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return 0 }
        var removed = 0
        for entry in entries where prefixes.contains(where: { entry.lastPathComponent.hasPrefix($0) }) {
            if (try? fileManager.removeItem(at: entry)) != nil { removed += 1 }
        }
        return removed
    }
}
