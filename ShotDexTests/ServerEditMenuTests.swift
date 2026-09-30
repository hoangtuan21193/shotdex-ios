import Testing
@testable import ShotDex

/// FS-17.06 §3, D9: server photos get the album's commands that work on a
/// file, named and drawn by the same definitions.
@Suite struct ServerEditMenuTests {
    /// AC-53: the selection ⋯ of a server folder is the album's, in the
    /// album's order, less what only Photos can do — plus Import.
    @Test func matchesAlbumMenu() {
        let shared = PhotoCommand.serverSelectionMenu.filter { PhotoCommand.albumSelectionMenu.contains($0) }
        let albumOrder = PhotoCommand.albumSelectionMenu.filter { shared.contains($0) }
        #expect(shared == albumOrder)
        #expect(PhotoCommand.serverSelectionMenu.last == .importToLibrary)
        for photosOnly in [PhotoCommand.addToCollection, .duplicate] {
            #expect(!PhotoCommand.serverSelectionMenu.contains(photosOnly))
            #expect(!PhotoCommand.serverPhotoMenu.contains(photosOnly))
        }
        // Phase 1 (FS-17.06 §2): Combine, Collage and Video are not offered yet.
        for later in [PhotoCommand.combine, .collage, .video] {
            #expect(!PhotoCommand.serverSelectionMenu.contains(later))
        }
    }

    /// AC-52: the long-press menu is Edit, Share, Copy, Import to Library.
    @Test func longPressMenu() {
        #expect(PhotoCommand.serverPhotoMenu == [.edit, .share, .copy, .importToLibrary])
    }

    /// Every command has a name and a glyph — a row that draws empty is a
    /// row nobody can find.
    @Test func everyCommandIsNamedAndDrawn() {
        for command in PhotoCommand.allCases {
            #expect(!command.title.isEmpty)
            #expect(!command.systemImage.isEmpty)
        }
        #expect(PhotoCommand.edit.systemImage == "slider.horizontal.3")
        #expect(PhotoCommand.pasteEdits.title == "Paste Edits")
    }
}
