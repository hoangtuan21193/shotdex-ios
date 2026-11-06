import Foundation

/// FS-19.08 §6d: what the Compare window holds — one Same photo at a time,
/// its copies side by side (the first folder's on the left), and the way
/// to the next or previous row.
struct CommonPhotosCompare: Equatable, Sendable {
    /// One copy as a side shows it.
    struct Copy: Equatable, Sendable {
        /// The chosen folder it sits in, by position.
        let folder: Int
        /// "Tuấn/2025": the folder's name and the subfolder.
        let place: String
        let name: String
        /// Its path on the server.
        let path: String
        let size: Int64
    }

    /// The rows the window steps through, by id, in list order.
    private(set) var rowIds: [String]
    /// The row shown.
    private(set) var current: Int
    /// With three folders or more, the copy the right side shows (§6d: a
    /// popup picks it); an index into `copies` after the first.
    var rightCopy = 1

    init(rowIds: [String], showing id: String) {
        self.rowIds = rowIds
        current = rowIds.firstIndex(of: id) ?? 0
    }

    var currentId: String? { rowIds.indices.contains(current) ? rowIds[current] : nil }

    /// "3 of 282".
    var position: (index: Int, count: Int) { (current + 1, rowIds.count) }

    /// ↓ / →: the next row; stays on the last.
    mutating func next() {
        guard current + 1 < rowIds.count else { return }
        current += 1
        rightCopy = 1
    }

    /// ↑ / ←: the previous row; stays on the first.
    mutating func previous() {
        guard current > 0 else { return }
        current -= 1
        rightCopy = 1
    }

    /// The list changed under the window (a rescan, a row left out before):
    /// stay on the same row when it is still there, else on the one now at
    /// its place.
    mutating func update(rowIds: [String]) {
        let id = currentId
        self.rowIds = rowIds
        if let id, let index = rowIds.firstIndex(of: id) {
            current = index
        } else {
            current = min(current, max(0, rowIds.count - 1))
            rightCopy = 1
        }
    }

    /// The copies of a Same photo, one per folder — the first one each
    /// folder lists — in folder order.
    static func copies(of photo: CommonPhoto, folders: [String]) -> [Copy] {
        photo.files.compactMap(\.first).map { file in
            let folder = ServerUploadPath.lastComponent(of: folders[file.folder])
            return Copy(folder: file.folder, place: ServerUploadPath.join(folder, file.subfolder), name: file.name,
                        path: ServerUploadPath.join(folders[file.folder], file.relativePath), size: file.size)
        }
    }
}
