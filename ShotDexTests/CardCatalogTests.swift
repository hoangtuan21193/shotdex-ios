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

    /// AC-23: a voice memo `IMG_0200.WAV` rides in its photo's tile; a clip
    /// `MVI_0201.MP4` is a tile of its own; its `.THM` thumbnail is not
    /// copied.
    @Test func wavJoinsPhoto() {
        let items = CardCatalog.items([
            file("DCIM/100CANON/IMG_0200.JPG"),
            file("DCIM/100CANON/IMG_0200.WAV"),
            file("DCIM/100CANON/MVI_0201.MP4", minute: 1),
            file("DCIM/100CANON/MVI_0201.THM", minute: 1),
            file("DCIM/100CANON/IMG_0202.CR3", minute: 2),
            file("DCIM/100CANON/IMG_0202.JPG", minute: 2),
            file("DCIM/100CANON/IMG_0202.WAV", minute: 2),
        ])
        #expect(items.map(\.kind) == [.photo, .video, .photo])
        #expect(items[0].files.map(\.name) == ["IMG_0200.JPG", "IMG_0200.WAV"])
        #expect(items[1].files.map(\.name) == ["MVI_0201.MP4"])
        #expect(items[2].files.map(\.name) == ["IMG_0202.CR3", "IMG_0202.JPG", "IMG_0202.WAV"])
    }

    /// The camera's own files never reach the grid: THM, the MISC folder,
    /// catalog files, anything hidden, and a WAV with no photo of its name.
    @Test func thmAndMiscSkipped() {
        let items = CardCatalog.items([
            file("DCIM/100CANON/IMG_0001.JPG"),
            file("DCIM/100CANON/MVI_0002.THM"),
            file("MISC/IMG_0003.JPG"),
            file("MISC/CANONMSC/M0100.CTG"),
            file("PRIVATE/M4ROOT/MEDIAPRO.XML"),
            file("DCIM/100CANON/._IMG_0001.JPG"),
            file(".Spotlight-V100/Store-V2/x.db"),
            file("DCIM/100CANON/VOICE_0004.WAV"),
            file("PRIVATE/M4ROOT/CLIP/C0001.MP4", minute: 3),
        ])
        #expect(items.map(\.id) == ["DCIM/100CANON/IMG_0001.JPG", "PRIVATE/M4ROOT/CLIP/C0001.MP4"])
        #expect(items[1].kind == .video)
    }
}
