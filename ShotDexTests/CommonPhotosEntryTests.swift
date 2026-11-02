import Testing
@testable import ShotDex

/// FS-19.08 §3: which folders Find Common Photos… starts from.
@Suite struct CommonPhotosEntryTests {
    let folders = ["edited", "from-tuan", "own"]

    private func selection(_ names: [String]) -> ClickSelection {
        var selection = ClickSelection()
        let order = folders.map(CommonPhotosEntry.folderId)
        for name in names {
            selection.click(CommonPhotosEntry.folderId(name), in: order, extendsSelection: true, extendsRange: false)
        }
        return selection
    }

    @Test func pickedFoldersComeInDrawingOrder() {
        let picked = CommonPhotosEntry.picked(selection(["own", "edited"]), selectionFolder: "Vo", folder: "Vo", folders: folders)
        #expect(picked == ["Vo/edited", "Vo/own"])
    }

    @Test func picksMadeInAnotherFolderDoNotCount() {
        // A column of the root picked "own"; the open folder Vo has an "own" too.
        let picked = CommonPhotosEntry.picked(selection(["own"]), selectionFolder: "", folder: "Vo", folders: folders)
        #expect(picked.isEmpty)
    }

    @Test func rightClickOnAPickedFolderActsOnTheSelection() {
        let targets = CommonPhotosEntry.targets(rightClicked: "own", in: "Vo", selection: selection(["from-tuan", "own"]),
                                                selectionFolder: "Vo", folders: folders)
        #expect(targets == ["Vo/from-tuan", "Vo/own"])
    }

    @Test func rightClickElsewhereActsOnThatFolderAlone() {
        let picks = selection(["from-tuan", "own"])
        #expect(CommonPhotosEntry.targets(rightClicked: "edited", in: "Vo", selection: picks, selectionFolder: "Vo", folders: folders)
                == ["Vo/edited"])
        #expect(CommonPhotosEntry.targets(rightClicked: "own", in: "Tuan", selection: picks, selectionFolder: "Vo", folders: folders)
                == ["Tuan/own"])
    }

    @Test func theMenuItemNeedsTwoFolders() {
        #expect(!CommonPhotosEntry.canFind([]))
        #expect(!CommonPhotosEntry.canFind(["Vo/own"]))
        #expect(CommonPhotosEntry.canFind(["Vo/own", "Tuan"]))
    }

    @Test func serverPathsSitUnderTheConnectionFolder() {
        #expect(CommonPhotosEntry.serverPaths(["Vo/own", "Tuan"], connectionFolder: "/photos/") == ["photos/Vo/own", "photos/Tuan"])
        #expect(CommonPhotosEntry.serverPaths(["Vo"], connectionFolder: "") == ["Vo"])
    }
}
