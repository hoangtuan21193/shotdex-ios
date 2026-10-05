import Foundation
import Testing
@testable import ShotDex

@MainActor
struct SettingsNavigationTests {

    private func makeNavigation() -> SettingsNavigation { SettingsNavigation() }

    // MARK: A fresh session

    /// Settings opens on the first item with nothing typed, every time. Neither
    /// is stored anywhere, which is the point: a search term belongs to the
    /// question being asked.
    @Test func aNewSessionStartsAtPhotoLibraryWithNoQuery() {
        let navigation = makeNavigation()
        #expect(navigation.selection == .photoLibrary)
        #expect(navigation.query.isEmpty)
        #expect(navigation.isSearching == false)
        #expect(navigation.compactPath.isEmpty)
        #expect(navigation.pendingScrollTarget == nil)
        #expect(navigation.flashedRow == nil)
    }

    /// Whitespace is not a search.
    @Test func blankQueryIsNotSearching() {
        let navigation = makeNavigation()
        navigation.query = "   "
        #expect(navigation.isSearching == false)
        navigation.query = "iso"
        #expect(navigation.isSearching)
    }

    // MARK: Opening a result

    /// On iPad the result opens its sidebar item; the query goes, because a
    /// results list left on screen hides the place the reader was just sent.
    @Test func openingAResultSelectsItsSectionAndArmsTheScroll() throws {
        let navigation = makeNavigation()
        navigation.query = "hdr"
        let entry = try #require(SettingsSearchIndex.results(for: "hdr").first)

        navigation.open(entry, usesSplitView: true)

        #expect(navigation.selection == .playback)
        #expect(navigation.pendingScrollTarget == .viewFullHDR)
        #expect(navigation.query.isEmpty)
    }

    /// On a phone the root is a list of items (FS-08.01b §1), so a result
    /// pushes the page holding its row — replacing whatever was pushed — and
    /// arms the scroll (AC-8).
    @Test func openingAResultOnAPhonePushesItsPage() throws {
        let navigation = makeNavigation()
        navigation.compactPath = [.display]
        let entry = try #require(SettingsSearchIndex.results(for: "cellular").first)

        navigation.open(entry, usesSplitView: false)

        #expect(navigation.compactPath == [.photoLibrary])
        #expect(navigation.pendingScrollTarget == .useCellularData)
        #expect(navigation.query.isEmpty)
    }

    /// A result whose page is a screen of its own opens that screen and leaves
    /// nothing waiting to scroll — a target no list claims would fire on the
    /// next page that drew it.
    @Test func openingAResultForAScreenOfItsOwnArmsNoScroll() throws {
        let navigation = makeNavigation()
        let entry = try #require(SettingsSearchIndex.results(for: "resize").first)

        navigation.open(entry, usesSplitView: false)
        #expect(navigation.compactPath == [.resizePresets])
        #expect(navigation.pendingScrollTarget == nil)

        let support = try #require(SettingsSearchIndex.results(for: "support").first)
        navigation.open(support, usesSplitView: true)
        #expect(navigation.selection == .support)
        #expect(navigation.pendingScrollTarget == nil)
    }

    /// The target is handed over once: the detail pane is rebuilt whenever the
    /// selection changes, and a target that stayed would scroll again on every
    /// return.
    @Test func theScrollTargetIsHandedOverOnce() throws {
        let navigation = makeNavigation()
        let entry = try #require(SettingsSearchIndex.results(for: "iso").first)
        navigation.open(entry, usesSplitView: true)

        #expect(navigation.consumeScrollTarget() == .iso)
        #expect(navigation.consumeScrollTarget() == nil)
        #expect(navigation.pendingScrollTarget == nil)
    }

    // MARK: The highlight

    /// The row lights up at once and goes out by itself.
    ///
    /// The timer lives on this type rather than on the view's `task`, which is
    /// keyed to the scroll target — consuming the target cancelled that task,
    /// and with it the highlight, before a single frame had been drawn.
    @Test func theFlashLightsUpImmediatelyAndClearsItself() async {
        let navigation = makeNavigation()

        navigation.flash(.useCellularData)
        #expect(navigation.flashedRow == .useCellularData)

        try? await Task.sleep(for: AppTheme.Motion.searchFlashDuration + .milliseconds(400))
        #expect(navigation.flashedRow == nil)
    }

    /// Still lit while the clock is running — the highlight has to outlive the
    /// frame that scrolled the row into place.
    @Test func theFlashOutlivesTheScroll() async {
        let navigation = makeNavigation()
        navigation.flash(.iso)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(navigation.flashedRow == .iso)
    }

    /// A second result taken while the first is still lit moves the highlight
    /// rather than leaving two rows glowing.
    @Test func asecondFlashReplacesTheFirst() async {
        let navigation = makeNavigation()
        navigation.flash(.iso)
        navigation.flash(.megapixels)
        #expect(navigation.flashedRow == .megapixels)
        try? await Task.sleep(for: AppTheme.Motion.searchFlashDuration + .milliseconds(400))
        #expect(navigation.flashedRow == nil)
    }

    // MARK: Crossing the size-class line

    /// Narrowing the window pushes the item the reader was on; widening it puts
    /// them back on the same item.
    @Test func theSelectedSectionSurvivesALayoutChange() {
        let navigation = makeNavigation()
        navigation.selection = .cameraDatabase

        navigation.layoutChanged(usesSplitView: false)
        #expect(navigation.compactPath == [.cameraDatabase])

        navigation.layoutChanged(usesSplitView: true)
        #expect(navigation.selection == .cameraDatabase)
        #expect(navigation.compactPath.isEmpty)
    }

    /// Except for the first item: shrinking the window while on Photo Library
    /// lands on the settings list itself, not on a screen to tap Back out of.
    @Test func narrowingFromTheFirstItemLandsOnTheList() {
        let navigation = makeNavigation()
        navigation.selection = .photoLibrary

        navigation.layoutChanged(usesSplitView: false)

        #expect(navigation.compactPath.isEmpty)
    }
}
