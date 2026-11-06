import Foundation

/// Which folders Find Common Photos… starts from (FS-19.08 §3), from a
/// browser's pointer selection. Pure: the Mac server browser draws it, this
/// decides it.
///
/// Paths are relative to the source's root (the connection's Folder) until
/// `serverPaths`, which makes them the runner's server paths.
enum CommonPhotosEntry {
    /// The selection id of a folder named `name` — the browser's item id.
    static func folderId(_ name: String) -> String { "folder:\(name)" }

    /// The folders of `folder` that `selection` picks, in drawing order
    /// (`folders`). Nothing when the selection was made in another folder:
    /// a column's picks never leak into the open folder's grid or list.
    static func picked(_ selection: ClickSelection, selectionFolder: String, folder: String, folders: [String]) -> [String] {
        guard folder == selectionFolder else { return [] }
        return folders.filter { selection.contains(folderId($0)) }.map { ServerUploadPath.join(folder, $0) }
    }

    /// What a right-click on the folder `name` of `folder` acts on, as in
    /// Finder: the whole selection when that folder is part of it, else that
    /// folder alone.
    static func targets(rightClicked name: String, in folder: String, selection: ClickSelection,
                        selectionFolder: String, folders: [String]) -> [String] {
        if folder == selectionFolder, selection.contains(folderId(name)) {
            return picked(selection, selectionFolder: selectionFolder, folder: folder, folders: folders)
        }
        return [ServerUploadPath.join(folder, name)]
    }

    /// The context menu offers the command from two folders up; under that
    /// it is left out. File › Find Common Photos… opens with any number.
    static func canFind(_ folders: [String]) -> Bool { folders.count >= 2 }

    /// `folders` under the connection's Folder: the server paths the run uses.
    static func serverPaths(_ folders: [String], connectionFolder: String) -> [String] {
        folders.map { ServerUploadPath.join(ServerUploadPath.normalizedFolder(connectionFolder), $0) }
    }
}
