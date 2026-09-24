import Foundation
import Testing
@testable import ShotDex

struct SettingsSearchTests {

    // MARK: Matching

    /// Typing the letters is enough — case is not part of the question.
    @Test func matchesRowLabelCaseInsensitively() {
        let lower = SettingsSearchIndex.results(for: "hdr")
        let upper = SettingsSearchIndex.results(for: "HDR")
        let padded = SettingsSearchIndex.results(for: "  HDR ")
        #expect(lower == upper)
        #expect(lower == padded)
        #expect(lower.count == 1)
        #expect(lower.first?.text == "View Full HDR")
        #expect(lower.first?.section == .playback)
    }

    /// The subtitle under a result names the item that holds the row, so the
    /// reader learns where it lives instead of only being sent there.
    @Test func resultsCarryTheOwningSectionAsSubtitle() {
        let hit = SettingsSearchIndex.results(for: "view full hdr").first
        #expect(hit?.sectionTitle == "Playback")
    }

    /// Diacritics are not a spelling test.
    @Test func matchesIgnoringDiacritics() {
        let hits = SettingsSearchIndex.results(for: "megapíxels")
        #expect(hits.map(\.label) == [.megapixels])
    }

    /// Substring, not prefix — "cellular" sits in the middle of the row that
    /// owns it, and that is the case this search exists for.
    @Test func matchesMidWordSoCellularAndISOAreFound() {
        #expect(SettingsSearchIndex.results(for: "cellular").map(\.label) == [.useCellularData])
        #expect(SettingsSearchIndex.results(for: "iso").map(\.label) == [.iso])
        #expect(SettingsSearchIndex.results(for: "index").count >= 3)
    }

    /// Nothing typed, nothing found — the caller keeps showing the settings
    /// rather than listing all 38 rows as "results".
    @Test func emptyQueryReturnsNothing() {
        #expect(SettingsSearchIndex.results(for: "").isEmpty)
        #expect(SettingsSearchIndex.results(for: "   ").isEmpty)
    }

    @Test func nonsenseQueryReturnsNothing() {
        #expect(SettingsSearchIndex.results(for: "zzzz").isEmpty)
    }

    /// A query that hits several places comes back in sidebar order, so a
    /// driver dump of the results is the same every run.
    @Test func resultsAreOrderedBySidebarOrder() {
        let hits = SettingsSearchIndex.results(for: "s")
        let order = SettingsSection.allCases
        let indices = hits.compactMap { order.firstIndex(of: $0.section) }
        #expect(indices == indices.sorted())
        #expect(hits.count > 5)
    }

    // MARK: The index covers the screen

    @Test func everySectionIsIndexed() {
        for section in SettingsSection.allCases {
            #expect(!SettingsSearchIndex.entries(in: section).isEmpty, "\(section) has no rows")
        }
    }

    /// The golden table. Each number is the rows that section draws today, with
    /// the file line it was counted from — if a row is added and not named in
    /// `SettingsRowLabel`, this is what says so.
    @Test func eachSectionIndexesEveryRowItDraws() {
        let expected: [SettingsSection: Int] = [
            .photoLibrary: 13,      // SettingsScreen.swift:127 (10) + :463 (2) + :543 (1); Import gone (FS-10)
            .notifications: 4,      // :346
            .widgets: 1,            // :413
            .display: 8,            // :429
            .playback: 2,           // :449
            .subjectScan: 4,        // :279
            .sharingAndExport: 3,   // :258 (1) + :496 (1) + File Servers (1, FS-15)
            .cameraDatabase: 2,     // :515
            .support: 1,            // :528
        ]
        for section in SettingsSection.allCases {
            #expect(
                SettingsSearchIndex.entries(in: section).count == expected[section],
                "\(section) indexes \(SettingsSearchIndex.entries(in: section).count) rows"
            )
        }
        #expect(SettingsSearchIndex.entries.count == 38)
    }

    /// One case, one entry — a copy-pasted case that forgot to change its text
    /// shows up here.
    @Test func everyRowLabelProducesExactlyOneEntry() {
        #expect(SettingsSearchIndex.entries.count == SettingsRowLabel.allCases.count)
        let pairs = SettingsSearchIndex.entries.map { "\($0.section.rawValue)|\($0.text)" }
        #expect(Set(pairs).count == pairs.count)
    }

    /// A row that can be absent has to say when it appears, or tapping its
    /// result is a silent no-op.
    @Test func everyConditionalRowSaysWhyItMayBeMissing() {
        let conditional = SettingsRowLabel.allCases.filter { $0.availability != .always }
        #expect(Set(conditional) == Set([
            .manageSelectedPhotos, .openPhotoSettings, .notificationsDenied,
            .openNotificationSettings, .continueIndexing, .lastIndexed, .measured,
            .findPeopleAndPets, .scanAgain, .clearScanResults,
        ]))
        for label in conditional {
            #expect(label.availability.explanation != nil, "\(label) hides with no explanation")
        }
        for label in SettingsRowLabel.allCases where label.availability == .always {
            #expect(label.availability.explanation == nil)
        }
    }

    /// Both "Open Settings" rows exist, one per section — the shared wording is
    /// deliberate, the shared entry would be a bug.
    @Test func theTwoOpenSettingsRowsStayApart() {
        let hits = SettingsSearchIndex.results(for: "open settings")
        #expect(hits.map(\.section) == [.photoLibrary, .notifications])
    }
}
