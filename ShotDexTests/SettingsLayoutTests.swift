import SwiftUI
import Testing
@testable import ShotDex

struct SettingsLayoutTests {

    // MARK: usesSplitView

    /// Every window that reports regular width gets the split view — iPad in
    /// both orientations, a half Split View, and the Duo's inner display.
    @Test func regularWidthUsesSplitView() {
        #expect(SettingsLayout.usesSplitView(horizontalSizeClass: .regular))
    }

    /// Compact and "not resolved yet" both take the single column: the list is
    /// right at any width, so the unknown case takes the layout that cannot be
    /// wrong.
    @Test func compactAndUnknownUseList() {
        #expect(SettingsLayout.usesSplitView(horizontalSizeClass: .compact) == false)
        #expect(SettingsLayout.usesSplitView(horizontalSizeClass: nil) == false)
    }

    // MARK: the two orders and the mapping between them

    /// Nine sidebar items cover all thirteen groups, and no group is shown twice.
    @Test func bothLayoutsCoverEverySection() {
        let mapped = SettingsSection.allCases.flatMap(\.groups)
        #expect(Set(mapped) == Set(SettingsGroup.allCases))
        #expect(mapped.count == SettingsGroup.allCases.count)
        #expect(SettingsSection.allCases.count == 9)
        #expect(SettingsGroup.allCases.count == 14)
    }

    /// The sidebar reads in the order of the four headings (FS-08.01b §1).
    @Test func sidebarOrderFollowsTheHeadings() {
        #expect(SettingsSection.allCases == [
            .photoLibrary, .display, .playback, .subjectScan, .cameraDatabase,
            .sharingAndExport,
            .widgets, .notifications,
            .support,
        ])
        #expect(SettingsCategory.allCases.flatMap(\.sections) == SettingsSection.allCases)
    }

    // MARK: The compact root (FS-08.01b §1)

    /// Four headings, eleven rows, in the table's order — Sharing and Export
    /// split into its three settings.
    @Test func compactRootRowsMatchTheSpecTable() {
        #expect(SettingsCategory.libraryAndViewing.destinations == [
            .photoLibrary, .display, .playback, .subjectScan, .cameraDatabase,
        ])
        #expect(SettingsCategory.sharingAndExport.destinations == [
            .metadataWhenSharing, .resizePresets, .fileServers,
        ])
        #expect(SettingsCategory.widgetsAndNotifications.destinations == [.widgets, .notifications])
        #expect(SettingsCategory.help.destinations == [.support])
        #expect(SettingsCategory.allCases.flatMap(\.destinations) == SettingsDestination.allCases)
    }

    /// The headings are sentence case, not title case.
    @Test func headingsAreSentenceCase() {
        #expect(SettingsCategory.allCases.map { String(localized: $0.title) } == [
            "Library and viewing", "Sharing and export", "Widgets and notifications", "Help",
        ])
    }

    /// The root and the sidebar are one list in two arrangements: every root
    /// row belongs to a sidebar item, and every sidebar item has a root row.
    @Test func rootAndSidebarShareOneList() {
        #expect(Set(SettingsDestination.allCases.map(\.section)) == Set(SettingsSection.allCases))
        for section in SettingsSection.allCases {
            #expect(!section.destinations.isEmpty, "\(section) has no root row")
            #expect(section.destinations.allSatisfy { $0.section == section })
        }
        // Every group a sidebar item draws is reachable from the phone's root.
        let rootGroups = SettingsDestination.allCases.flatMap(\.groups)
        #expect(Set(rootGroups) == Set(SettingsGroup.allCases))
    }

    /// Three rows open a screen of their own instead of a page of rows.
    @Test func rootRowsThatOpenAScreenDirectly() {
        let direct = SettingsDestination.allCases.filter { !$0.drawsRows }
        #expect(direct == [.resizePresets, .fileServers, .support])
    }

    /// Every root row has a symbol, and no two root rows share one.
    @Test func everyRootRowHasItsOwnSymbol() {
        let symbols = SettingsDestination.allCases.map(\.systemImage)
        #expect(symbols.allSatisfy { !$0.isEmpty })
        #expect(Set(symbols).count == symbols.count)
    }

    /// A search result lands on the root row that holds its row.
    @Test func eachRowLabelHasARootRow() {
        #expect(SettingsDestination.containing(.useCellularData) == .photoLibrary)
        #expect(SettingsDestination.containing(.clearLocalMetadataIndex) == .photoLibrary)
        #expect(SettingsDestination.containing(.showInsights) == .display)
        #expect(SettingsDestination.containing(.metadataWhenSharing) == .metadataWhenSharing)
        #expect(SettingsDestination.containing(.resizePresets) == .resizePresets)
        #expect(SettingsDestination.containing(.fileServers) == .fileServers)
        for label in SettingsRowLabel.allCases {
            #expect(SettingsDestination.containing(label).section == SettingsSearchIndex.section(for: label))
        }
    }

    /// The three rows that moved into the library card scroll to the card.
    @Test func libraryCardRowsScrollToTheCard() {
        for label in [SettingsRowLabel.indexedPhotosAndVideos, .lastIndexed, .reindexLibrary] {
            #expect(label.scrollAnchor == .indexedPhotosAndVideos)
        }
        #expect(SettingsRowLabel.useCellularData.scrollAnchor == .useCellularData)
    }

    /// Rows that throw something away have a red tile.
    @Test func destructiveRowsAreRed() {
        for label in [SettingsRowLabel.clearScanResults, .resetCustomMappings, .clearLocalMetadataIndex] {
            #expect(label.tint == .red)
        }
    }

    /// Library Size and Privacy have no sidebar item of their own; they ride
    /// with the photo library.
    @Test func libraryStorageAndPrivacyBelongToPhotoLibrary() {
        #expect(SettingsSection.photoLibrary.groups == [.photoLibrary, .libraryStorage, .privacy])
        // Display holds Thumbnail Metadata and Statistics (Show Insights, FS-07.02 §6).
        #expect(SettingsSection.display.groups == [.display, .statistics])
        // File Servers joins them rather than taking a tenth item: nine is what
        // fits the Duo's 669pt without scrolling (FS-15.01 §1).
        #expect(SettingsSection.sharingAndExport.groups == [.sharing, .export, .fileServers])
    }

    /// Every sidebar item names an SF Symbol, and no two share one.
    @Test func everySidebarItemHasItsOwnSymbol() {
        let symbols = SettingsSection.allCases.map(\.systemImage)
        #expect(symbols.allSatisfy { !$0.isEmpty })
        #expect(Set(symbols).count == symbols.count)
    }

    // MARK: crossing the size-class line

    /// Widening puts the reader on what they had pushed, or on the first item
    /// when they were on the list itself.
    @Test func expandingSelectsWhateverWasPushed() {
        #expect(SettingsLayout.selection(afterExpanding: [.cameraDatabase]) == .cameraDatabase)
        #expect(SettingsLayout.selection(afterExpanding: [.fileServers]) == .sharingAndExport)
        #expect(SettingsLayout.selection(afterExpanding: []) == .photoLibrary)
    }

    /// Narrowing pushes the selected item — except the first one, which is as
    /// much "nothing chosen" as it is a choice, so the reader lands on the
    /// settings list rather than on a screen they have to tap Back out of.
    @Test func collapsingPushesTheSelectionButNotTheFirstItem() {
        #expect(SettingsLayout.path(afterCollapsing: .display) == [.display])
        #expect(SettingsLayout.path(afterCollapsing: .support) == [.support])
        #expect(SettingsLayout.path(afterCollapsing: .sharingAndExport) == [.metadataWhenSharing])
        #expect(SettingsLayout.path(afterCollapsing: .photoLibrary) == [])
        #expect(SettingsLayout.path(afterCollapsing: nil) == [])
    }

    /// A trip out to the wide layout and back leaves the reader where they
    /// started.
    @Test func aRoundTripAcrossTheSizeClassKeepsThePlace() {
        for section in SettingsSection.allCases {
            let collapsed = SettingsLayout.path(afterCollapsing: section)
            #expect(SettingsLayout.selection(afterExpanding: collapsed) == section)
        }
    }
}
