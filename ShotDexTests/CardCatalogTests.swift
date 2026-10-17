import Foundation
import Testing
@testable import ShotDex

/// FS-20 §5: what a card's file list becomes on the Import from Card grid.
@Suite struct CardCatalogTests {
    private func file(_ path: String, _ size: Int64 = 1_000, minute: Int = 0) -> CardFile {
        CardFile(path: path, size: size, modified: Date(timeIntervalSince1970: 1_790_000_000 + Double(minute) * 60))
    }

    /// AC-6: `IMG_0042.CR3` + `IMG_0042.JPG` are one tile holding both files,
    /// the RAW first; a Canon `.HIF` pairs the same way.
    @Test func pairIsOneTile() {
        let items = CardCatalog.items([
            file("DCIM/100CANON/IMG_0042.CR3", 30_000_000),
            file("DCIM/100CANON/IMG_0042.JPG", 8_000_000),
            file("DCIM/100CANON/IMG_0043.CR3", minute: 1),
            file("DCIM/100CANON/img_0043.hif", minute: 1),
            file("DCIM/100CANON/IMG_0044.JPG", minute: 2),
        ])
        #expect(items.map(\.files.count) == [2, 2, 1])
        #expect(items[0].files.map(\.name) == ["IMG_0042.CR3", "IMG_0042.JPG"])
        #expect(items[0].byteCount == 38_000_000)
        #expect(items[0].kind == .photo)
        #expect(items[1].files.map(\.name) == ["IMG_0043.CR3", "img_0043.hif"])
    }

    /// Two folders on one card can both hold an `IMG_0001`: a pair never
    /// crosses folders.
    @Test func sameNameInTwoDCIMFoldersIsTwoTiles() {
        let items = CardCatalog.items([
            file("DCIM/100CANON/IMG_0001.CR3"),
            file("DCIM/101CANON/IMG_0001.JPG", minute: 5),
        ])
        #expect(items.map(\.files.count) == [1, 1])
        #expect(Set(items.map(\.id)) == ["DCIM/100CANON/IMG_0001.CR3", "DCIM/101CANON/IMG_0001.JPG"])
    }

    /// Oldest first (FS-20 §5), then by path for files with one date.
    @Test func oldestFirst() {
        let items = CardCatalog.items([
            file("DCIM/100CANON/IMG_0003.JPG", minute: 9),
            file("DCIM/100CANON/IMG_0001.JPG", minute: 1),
            file("DCIM/100CANON/IMG_0002.JPG", minute: 1),
        ])
        #expect(items.map(\.primary.name) == ["IMG_0001.JPG", "IMG_0002.JPG", "IMG_0003.JPG"])
    }
}
