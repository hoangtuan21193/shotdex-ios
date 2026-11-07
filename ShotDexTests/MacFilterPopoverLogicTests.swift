import Foundation
import Testing
@testable import ShotDex

/// FS-18 AC-35 (02 §5) — the pure half of the Mac's Filter and Sort: the
/// "N of M photos" line, the Sort By pair, and the filter bar's chips (the
/// same tokens the iOS token bar shows, split into field and value).
struct MacFilterPopoverLogicTests {

    // MARK: Count line

    @Test func filteredLineReadsShownOfTotal() {
        #expect(LibraryCountLine.text(shown: 18_240, videos: 12, total: 55_231, isFiltered: true)
            == "\(18_240.formatted()) of \(55_231.formatted()) photos")
    }

    /// A library with videos says items: the filtered line does not split kinds.
    @Test func libraryWithVideosSaysItems() {
        #expect(LibraryCountLine.text(shown: 212, videos: 3, total: 55_231, isFiltered: true, libraryHasVideos: true)
            == "212 of \(55_231.formatted()) items")
    }

    /// A typo keeps the bound, an empty field clears it, numbers must be
    /// finite and above zero, ISO is whole.
    @Test func rangeBoundInputKeepsTheBoundOnATypo() {
        #expect(RangeBoundInput.iso.parse("32o0") == .invalid)
        #expect(RangeBoundInput.iso.parse("  ") == .cleared)
        #expect(RangeBoundInput.iso.parse("3200.4") == .value(3200))
        #expect(RangeBoundInput.iso.parse("ISO 800") == .value(800))
        #expect(RangeBoundInput.aperture.parse("f/2.8") == .value(2.8))
        #expect(RangeBoundInput.aperture.parse("F4") == .value(4))
        #expect(RangeBoundInput.focal.parse("85mm") == .value(85))
        #expect(RangeBoundInput.focal.parse("0") == .invalid)
        #expect(RangeBoundInput.focal.parse("-35") == .invalid)
        #expect(RangeBoundInput.focal.parse("inf") == .invalid)
    }

    /// "3200 to 400" is read as 400–3200.
    @Test func crossedBoundsSwap() {
        let range = RangeBoundInput.setting(400, lower: false, in: NumericRangeFilter(lowerBound: 3200))
        #expect(range == NumericRangeFilter(lowerBound: 400, upperBound: 3200))
        #expect(RangeBoundInput.setting(nil, lower: true, in: range) == NumericRangeFilter(upperBound: 3200))
    }

    @Test func oneItemLibrarySaysPhotoInTheSingular() {
        #expect(LibraryCountLine.text(shown: 0, videos: 0, total: 1, isFiltered: true) == "0 of 1 photo")
    }

    /// Unfiltered, or the total not known yet: photos and videos apart.
    @Test func unfilteredLineSplitsPhotosAndVideos() {
        #expect(LibraryCountLine.text(shown: 1_210, videos: 10, total: 1_210, isFiltered: false)
            == "\(1_200.formatted()) photos · 10 videos")
        #expect(LibraryCountLine.text(shown: 1, videos: 0, total: nil, isFiltered: true) == "1 photo")
        #expect(LibraryCountLine.text(shown: 2, videos: 1, total: nil, isFiltered: false) == "1 photo · 1 video")
        // Only videos — the Videos place, a day of clips: no "0 photos".
        #expect(LibraryCountLine.text(shown: 14, videos: 14, total: nil, isFiltered: false) == "14 videos")
    }

    // MARK: Sort By

    /// Field and direction round-trip through every menu order.
    @Test func sortPairCoversEveryMenuOrder() {
        for sort in SortOption.menuOrders {
            let field = LibrarySortField(sort)
            #expect(field.sort(newestFirst: LibrarySortField.isNewestFirst(sort)) == sort)
        }
        #expect(LibrarySortField(.dateModifiedOldest) == .dateModified)
        #expect(!LibrarySortField.isNewestFirst(.dateTakenOldest))
        // Flipping the field keeps the direction.
        #expect(LibrarySortField.dateModified.sort(newestFirst: LibrarySortField.isNewestFirst(.dateTakenOldest))
            == .dateModifiedOldest)
    }

    /// File Size is the popover's third field; Largest is its "first" end.
    @Test func fileSizeField() {
        #expect(LibrarySortField.allCases == [.dateTaken, .dateModified, .fileSize])
        #expect(LibrarySortField(.fileSizeLargest) == .fileSize)
        #expect(LibrarySortField(.fileSizeSmallest) == .fileSize)
        #expect(LibrarySortField.isNewestFirst(.fileSizeLargest))
        #expect(!LibrarySortField.isNewestFirst(.fileSizeSmallest))
        #expect(LibrarySortField.fileSize.sort(newestFirst: false) == .fileSizeSmallest)
        // Switching the field from Date Taken (Oldest) keeps the direction.
        #expect(LibrarySortField.fileSize.sort(newestFirst: LibrarySortField.isNewestFirst(.dateTakenOldest))
            == .fileSizeSmallest)
    }

    /// AC-S9: the Order pop-up says Largest / Smallest First for File Size.
    @Test func fileSizeDirectionTitles() {
        #expect(LibrarySortField.fileSize.directionTitles.first == "Largest First")
        #expect(LibrarySortField.fileSize.directionTitles.last == "Smallest First")
        #expect(LibrarySortField.dateModified.directionTitles.first == "Newest First")
        #expect(LibrarySortField(.fileSizeSmallest).directionTitles.last == "Smallest First")
    }

    /// A metric order (not in the menu) reads as Date Taken, Newest First.
    @Test func metricOrderReadsAsDateTaken() {
        #expect(LibrarySortField(.isoDescending) == .dateTaken)
        #expect(LibrarySortField.isNewestFirst(.isoDescending))
    }

    // MARK: Filter bar chips

    private static var boardCriteria: FilterCriteria {
        var criteria = FilterCriteria()
        criteria.cameraBodies = ["Canon EOS R6 Mark II"]
        criteria.lenses = ["RF 85mm F1.2 L USM"]
        criteria.focalRange = NumericRangeFilter(lowerBound: 85, upperBound: 85)
        criteria.isoRange = NumericRangeFilter(lowerBound: 3200, upperBound: 12800)
        criteria.apertureRange = NumericRangeFilter(lowerBound: 1.2, upperBound: 2)
        criteria.flags = [.picks]
        criteria.ratingFilter = .atLeast(3)
        criteria.originalOnDeviceOnly = true
        return criteria
    }

    /// The board's chips: a dim key where the value needs one.
    @Test func chipsSplitFieldAndValueAsTheBoardDraws() throws {
        let tokens = ActiveFilterToken.tokens(for: Self.boardCriteria)
        func chip(_ id: String) throws -> ActiveFilterToken { try #require(tokens.first { $0.id == id }) }
        #expect(try chip("body-Canon EOS R6 Mark II").field == "Camera")
        #expect(try chip("body-Canon EOS R6 Mark II").value == "Canon EOS R6 Mark II")
        #expect(try chip("lens-RF 85mm F1.2 L USM").field == "Lens")
        #expect(try chip("focal").field == "Focal")
        #expect(try chip("focal").value == "85mm")
        #expect(try chip("iso").value == "3200–12800")
        #expect(try chip("aperture").value == "f/1.2–f/2")
        #expect(try chip("flag-picks").field == nil)
        #expect(try chip("flag-picks").value == "Picks")
        #expect(try chip("originalOnDevice").value == OriginalPresence.filterTitle)
    }

    /// The iOS labels are unchanged by the split.
    @Test func iOSLabelsKeepTheirPrefix() throws {
        let tokens = ActiveFilterToken.tokens(for: Self.boardCriteria)
        #expect(tokens.first { $0.id == "iso" }?.label == "ISO 3200–12800")
        #expect(tokens.first { $0.id == "aperture" }?.label == "f 1.2–2")
        #expect(tokens.first { $0.id == "focal" }?.label == "focal 85mm")
        var equivalent = FilterCriteria()
        equivalent.focalRange = NumericRangeFilter(lowerBound: 50)
        equivalent.focalLengthMode = .equivalent
        let focal = try #require(ActiveFilterToken.tokens(for: equivalent).first)
        #expect(focal.label == "focal eq ≥ 50mm")
        #expect(focal.value == "≥ 50mm")
    }

    /// × on every chip in turn empties the criteria — Reset by hand.
    @Test func removingEveryChipClearsTheFilter() {
        var criteria = Self.boardCriteria
        for token in ActiveFilterToken.tokens(for: criteria) { token.clear(&criteria) }
        #expect(criteria.isEmpty)
    }
}
