import Foundation
import Testing
@testable import ShotDex

/// FS-17 AC-19, AC-20: Back and Forward walk the visits; the title menu
/// lists the folders above.
@Suite struct BrowseHistoryTests {
    @Test func backForwardLikeABrowser() {
        var history = BrowseHistory(start: "A")
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
        history.open("A/B")
        history.open("A/B/C")
        #expect(history.canGoBack)
        history.goBack()
        #expect(history.canGoBack)
        history.goBack()
        #expect(history.current == "A")
        #expect(history.canGoForward)
        #expect(history.canGoForward)
        history.goForward()
        #expect(history.current == "A/B")
        history.open("A/D")
        #expect(!history.canGoForward)
        #expect(history.canGoBack)
        history.goBack()
        #expect(history.current == "A/B")
        #expect(history.canGoBack)
        history.goBack()
        #expect(history.current == "A")
        // The first visit: Back leaves the screen instead.
        let refused = history.goBack()
        #expect(!refused)
        #expect(history.current == "A")
    }

    @Test func openingTheCurrentFolderIsNotAVisit() {
        var history = BrowseHistory(start: "A")
        history.open("A")
        #expect(!history.canGoBack)
    }

    @Test func titleMenuListsAncestors() {
        #expect(BrowseHistory.ancestors(of: "photos/2026/Trip") == ["photos/2026", "photos", ""])
        #expect(BrowseHistory.ancestors(of: "photos") == [""])
        #expect(BrowseHistory.ancestors(of: "").isEmpty)

        // Jumping up is a visit: Back returns to where the menu was opened.
        var history = BrowseHistory(start: "photos/2026/Trip")
        history.open("photos")
        #expect(history.current == "photos")
        #expect(history.canGoBack)
        history.goBack()
        #expect(history.current == "photos/2026/Trip")
    }
}

/// FS-15 AC-47: an SMB path's first folder is the share.
@Suite struct SMBPathTests {
    @Test func splitsShareFromPath() {
        let file = SMBPath.split("photos/RAW/a.CR3")
        #expect(file?.share == "photos")
        #expect(file?.rest == "RAW/a.CR3")
        let share = SMBPath.split("/photos/")
        #expect(share?.share == "photos")
        #expect(share?.rest == "")
        #expect(SMBPath.split("") == nil)
        #expect(SMBPath.split("/") == nil)
    }
}

/// FS-17 AC-24: names New Folder and Rename accept.
@Suite struct RemoteFolderListingTests {
    @Test func validatedName() {
        #expect(RemoteFolderListing.validatedName("  Trip ") == "Trip")
        #expect(RemoteFolderListing.validatedName("") == nil)
        #expect(RemoteFolderListing.validatedName("   ") == nil)
        #expect(RemoteFolderListing.validatedName("a/b") == nil)
        #expect(RemoteFolderListing.validatedName(".x") == nil)
        #expect(RemoteFolderListing.validatedName("..") == nil)
        #expect(RemoteFolderListing.validatedName("2026-09-27 Beach") == "2026-09-27 Beach")
    }
}
