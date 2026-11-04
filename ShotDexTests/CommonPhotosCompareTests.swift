import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6d: the Compare window's rows and sides.
@Suite struct CommonPhotosCompareTests {
    private func file(_ folder: Int, _ path: String, size: Int64 = 100) -> CommonPhotosFile {
        CommonPhotosFile(folder: folder, relativePath: path, size: size, modified: nil)
    }

    /// AC-181: a Same photo's copies, first folder left — one per folder,
    /// the folder's first copy, with its place and path on the server.
    @Test func rowsAndSides() {
        let photo = CommonPhoto(sha256: "s", size: 100, files: [
            [file(0, "2025/IMG_4021.HEIC"), file(0, "older/IMG_4021.HEIC")],
            [file(1, "Phone/2025-06-01 IMG_4021.HEIC")]
        ])
        let copies = CommonPhotosCompare.copies(of: photo, folders: ["photos/Tuan", "photos/Vo"])
        #expect(copies.map(\.place) == ["Tuan/2025", "Vo/Phone"])
        #expect(copies.map(\.name) == ["IMG_4021.HEIC", "2025-06-01 IMG_4021.HEIC"])
        #expect(copies.map(\.path) == ["photos/Tuan/2025/IMG_4021.HEIC", "photos/Vo/Phone/2025-06-01 IMG_4021.HEIC"])
    }

    /// ↓ steps to the next row and stops on the last; ↑ back, stops on the first.
    @Test func stepsThroughTheRows() {
        var compare = CommonPhotosCompare(rowIds: ["a", "b", "c"], showing: "b")
        #expect(compare.position == (2, 3))
        compare.next()
        compare.next()
        #expect(compare.currentId == "c")
        compare.previous()
        compare.previous()
        compare.previous()
        #expect(compare.currentId == "a")
    }

    /// The list changes under the window: the same row stays shown when it
    /// is still there; gone, the window shows the one now at its place.
    @Test func followsTheList() {
        var compare = CommonPhotosCompare(rowIds: ["a", "b", "c"], showing: "c")
        compare.update(rowIds: ["x", "c"])
        #expect(compare.currentId == "c")
        compare.update(rowIds: ["x"])
        #expect(compare.currentId == "x")
        compare.update(rowIds: [])
        #expect(compare.currentId == nil)
    }
}
