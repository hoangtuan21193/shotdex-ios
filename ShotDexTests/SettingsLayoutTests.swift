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
        #expect(SettingsGroup.allCases.count == 13)
    }

    /// The sidebar reads in the order FS-08 lists it.
    @Test func sidebarOrderMatchesTheSpecTable() {
        #expect(SettingsSection.allCases == [
            .photoLibrary, .notifications, .widgets, .display, .playback,
            .subjectScan, .sharingAndExport, .cameraDatabase, .support,
        ])
    }

    /// The compact list keeps the order it shipped with, File Servers added
    /// after Export (FS-15) — the reason `SettingsGroup` exists.
    @Test func compactOrderIsUnchangedFromBeforeTheSplitView() {
        #expect(SettingsGroup.allCases == [
            .photoLibrary, .notifications, .widgets, .display, .playback,
            .subjectScan, .libraryStorage, .sharing, .export, .fileServers,
            .cameraDatabase, .support, .privacy,
        ])
    }

    /// Library Size and Privacy have no sidebar item of their own; they ride
    /// with the photo library.
    @Test func libraryStorageAndPrivacyBelongToPhotoLibrary() {
        #expect(SettingsSection.photoLibrary.groups == [.photoLibrary, .libraryStorage, .privacy])
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
        #expect(SettingsLayout.selection(afterExpanding: []) == .photoLibrary)
    }

    /// Narrowing pushes the selected item — except the first one, which is as
    /// much "nothing chosen" as it is a choice, so the reader lands on the
    /// settings list rather than on a screen they have to tap Back out of.
    @Test func collapsingPushesTheSelectionButNotTheFirstItem() {
        #expect(SettingsLayout.path(afterCollapsing: .display) == [.display])
        #expect(SettingsLayout.path(afterCollapsing: .support) == [.support])
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
