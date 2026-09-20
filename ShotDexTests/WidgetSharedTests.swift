import Foundation
import SwiftUI
import Testing
@testable import ShotDex

/// The pure parts of the widget payloads: the day key both processes spell,
/// the deep links a tap carries, which photos a day features, how a clock
/// format is sanitized and which album frame is showing.
struct WidgetSharedTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: Day keys

    @Test func dayKeyPadsToFixedWidth() {
        #expect(WidgetSharedContainer.dayKey(for: date(2026, 9, 5), calendar: calendar) == "2026-09-05")
        #expect(WidgetSharedContainer.dayKey(for: date(2026, 12, 31), calendar: calendar) == "2026-12-31")
    }

    @Test func dayKeyRoundTripsToLocalMidnight() throws {
        let key = WidgetSharedContainer.dayKey(for: date(2026, 9, 20, hour: 23), calendar: calendar)
        let parsed = try #require(WidgetSharedContainer.date(fromDayKey: key, calendar: calendar))
        #expect(parsed == date(2026, 9, 20, hour: 0))
    }

    @Test func malformedDayKeysAreRejected() {
        for key in ["", "2026-9-5", "2026-13-01", "2026-02-30", "not-a-day", "2026-09-05-01"] {
            #expect(WidgetSharedContainer.date(fromDayKey: key, calendar: calendar) == nil)
        }
    }

    // MARK: Deep links

    @Test func onThisDayLinkRoundTrips() {
        let link = WidgetDeepLink.onThisDay(dayKey: "2026-09-20")
        #expect(WidgetDeepLink(url: link.url) == link)
    }

    /// A PhotoKit local identifier contains slashes, which is why it travels
    /// as a query item rather than a path component.
    @Test func photoLinkSurvivesAnIdentifierWithSlashes() {
        let link = WidgetDeepLink.photo(assetId: "9F3C1B2A-1111-2222-3333-444455556666/L0/001")
        #expect(WidgetDeepLink(url: link.url) == link)
    }

    @Test func foreignAndIncompleteURLsAreNotLinks() {
        for string in [
            "https://example.com/on-this-day?day=2026-09-20",
            "shotdex://on-this-day",
            "shotdex://photo?id=",
            "shotdex://statistics",
        ] {
            #expect(WidgetDeepLink(url: URL(string: string)!) == nil)
        }
    }

    // MARK: On This Day selection

    @Test func featuredPhotosTakeOneYearEachBeforeDoublingUp() {
        // Four photos from 2025, then one each from 2024 and 2022.
        let years = [2025, 2025, 2025, 2025, 2024, 2022]
        #expect(OnThisDaySnapshot.featuredIndices(years: years) == [0, 4, 5, 1])
    }

    @Test func featuredPhotosFallBackToOrderWhenOneYearIsAll() {
        #expect(OnThisDaySnapshot.featuredIndices(years: [2024, 2024, 2024]) == [0, 1, 2])
        #expect(OnThisDaySnapshot.featuredIndices(years: []) == [])
    }

    @Test func writerCoversTodayAndTheDaysTheWidgetRollsOverTo() {
        let days = OnThisDaySnapshotWriter.days(from: date(2026, 9, 20, hour: 22), calendar: calendar)
        #expect(days.count == OnThisDaySnapshot.daysAhead + 1)
        #expect(days.first == date(2026, 9, 20, hour: 0))
        #expect(days.last == date(2026, 9, 20 + OnThisDaySnapshot.daysAhead, hour: 0))
    }

    // MARK: Clock formats

    /// A widget is rebuilt once a minute at best, so a seconds field would sit
    /// frozen on a wrong value — it is removed when the format is stored.
    @Test func secondsAreStrippedFromAClockFormat() {
        #expect(PhotoWidgetFormat.sanitized(pattern: "HH:mm:ss") == "HH:mm:")
        #expect(PhotoWidgetFormat.sanitized(pattern: "  h:mm a  ") == "h:mm a")
        #expect(PhotoWidgetFormat.sanitized(pattern: "") == "")
    }

    @Test func customPatternsAreUsedAndEmptyOnesFollowTheRegion() {
        var settings = PhotoWidgetSettings.default
        settings.timeFormat = "HH:mm"
        settings.dateFormat = "yyyy-MM-dd"
        let moment = date(2026, 9, 20, hour: 9)
        let zone = calendar.timeZone
        #expect(
            PhotoWidgetFormat.timeString(
                for: moment, settings: settings, locale: Locale(identifier: "en_GB"), timeZone: zone
            ) == "09:00"
        )
        #expect(
            PhotoWidgetFormat.dateString(
                for: moment, settings: settings, locale: Locale(identifier: "en_GB"), timeZone: zone
            ) == "2026-09-20"
        )

        settings.timeFormat = ""
        let systemTime = PhotoWidgetFormat.timeString(
            for: moment, settings: settings, locale: Locale(identifier: "en_GB"), timeZone: zone
        )
        // en_GB is a 24-hour region, so the short style has no AM/PM marker.
        #expect(systemTime.contains("09"))
    }

    // MARK: Clock rotation

    @Test func albumRotationPicksOneFramePerHourOrDay() {
        let noon = date(2026, 9, 20, hour: 12)
        let laterHour = date(2026, 9, 20, hour: 13)
        let nextDay = date(2026, 9, 21, hour: 12)

        let hourly = PhotoWidgetSnapshot.frameIndex(
            at: noon, count: 4, rotation: .hourly, calendar: calendar
        )
        let hourlyLater = PhotoWidgetSnapshot.frameIndex(
            at: laterHour, count: 4, rotation: .hourly, calendar: calendar
        )
        #expect(hourly != hourlyLater)

        let daily = PhotoWidgetSnapshot.frameIndex(
            at: noon, count: 4, rotation: .daily, calendar: calendar
        )
        #expect(
            PhotoWidgetSnapshot.frameIndex(
                at: laterHour, count: 4, rotation: .daily, calendar: calendar
            ) == daily
        )
        #expect(
            PhotoWidgetSnapshot.frameIndex(
                at: nextDay, count: 4, rotation: .daily, calendar: calendar
            ) != daily
        )

        #expect(
            PhotoWidgetSnapshot.frameIndex(
                at: laterHour, count: 4, rotation: .never, calendar: calendar
            ) == 0
        )
    }

    @Test func rotationHasNoFrameWhenThereAreNoPictures() {
        for rotation in PhotoWidgetSettings.Rotation.allCases {
            #expect(
                PhotoWidgetSnapshot.frameIndex(
                    at: .now, count: 0, rotation: rotation, calendar: calendar
                ) == nil
            )
        }
    }

    // MARK: Colour

    @Test func hexColoursParseWithOrWithoutTheHash() throws {
        let withHash = try #require(WidgetTextColor.components(hex: "#EB9526"))
        let without = try #require(WidgetTextColor.components(hex: "eb9526"))
        #expect(withHash.red == without.red)
        #expect(abs(withHash.red - 235.0 / 255) < 0.001)
        #expect(abs(withHash.green - 149.0 / 255) < 0.001)
        #expect(abs(withHash.blue - 38.0 / 255) < 0.001)
    }

    @Test func nonsenseHexIsNotAColour() {
        for hex in ["", "#FFF", "#GGGGGG", "FFFFFFFF"] {
            #expect(WidgetTextColor.components(hex: hex) == nil)
            #expect(!WidgetTextColor.isValid(hex: hex))
        }
        #expect(WidgetTextColor.swatches.allSatisfy { WidgetTextColor.isValid(hex: $0) })
    }

    // MARK: Scaling

    @Test func theMediumWidgetGetsExactlyTheSizeTheUserSet() {
        var settings = PhotoWidgetSettings.default
        settings.timeSize = 40
        #expect(settings.scaledHeadlineSize(forWidgetWidth: 329) == 40)
        #expect(settings.scaledHeadlineSize(forWidgetWidth: 158) < 40)
        #expect(settings.scaledHeadlineSize(forWidgetWidth: 360) > 40)
        // A clock is never scaled into illegibility, however narrow the family.
        #expect(settings.scaledHeadlineSize(forWidgetWidth: 10) >= 40 * 0.6)
    }
}

/// The calendar and weather the widgets draw: the month grid's arithmetic, the
/// event list's cut-off, and the temperature conversion. All pure, so none of
/// it waits for a particular month, a particular region or the weather.
struct PhotoWidgetDataTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: Month grid

    /// The grid follows the region's own first weekday unless the user asked
    /// for Monday, so this is measured in a Sunday-first region.
    @Test func monthGridPadsToWholeWeeksAndMarksToday() throws {
        // September 2026 starts on a Tuesday and has 30 days.
        let layout = MonthGrid.layout(
            for: date(2026, 9, 20),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        #expect(layout.days.count % 7 == 0)
        #expect(layout.weekdaySymbols.count == 7)
        // Two leading blanks: Sunday and Monday before Tuesday the 1st.
        #expect(layout.days.prefix(2).allSatisfy { $0 == nil })
        #expect(layout.days[2] == 1)
        let todayIndex = try #require(layout.todayIndex)
        #expect(layout.days[todayIndex] == 20)
        #expect(layout.days.compactMap { $0 }.count == 30)
    }

    @Test func aMondayFirstGridShiftsEveryColumn() throws {
        let sundayFirst = MonthGrid.layout(
            for: date(2026, 9, 20),
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            weekStartsOnMonday: false
        )
        let mondayFirst = MonthGrid.layout(
            for: date(2026, 9, 20),
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            weekStartsOnMonday: true
        )
        #expect(sundayFirst.weekdaySymbols != mondayFirst.weekdaySymbols)
        // One fewer leading blank when the week starts on Monday and the month
        // starts on Tuesday.
        let sundayBlanks = sundayFirst.days.prefix { $0 == nil }.count
        let mondayBlanks = mondayFirst.days.prefix { $0 == nil }.count
        #expect(mondayBlanks == sundayBlanks - 1)
        let todayIndex = try #require(mondayFirst.todayIndex)
        #expect(mondayFirst.days[todayIndex] == 20)
    }

    @Test func februaryInALeapYearFillsTwentyNineDays() {
        let layout = MonthGrid.layout(
            for: date(2028, 2, 10),
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        #expect(layout.days.compactMap { $0 }.count == 29)
    }

    // MARK: Events

    @Test func theEventListCutsOffAndCountsWhatIsLeft() {
        let events = (0..<5).map { index in
            CalendarSnapshot.Event(
                id: "\(index)",
                title: "Event \(index)",
                startDate: date(2026, 9, 20, hour: 9 + index),
                endDate: date(2026, 9, 20, hour: 10 + index),
                isAllDay: false,
                colorHex: nil
            )
        }
        let visible = CalendarFormat.visibleEvents(events, limit: 3)
        #expect(visible.shown.count == 3)
        #expect(visible.remaining == 2)
        #expect(CalendarFormat.visibleEvents(events, limit: 9).remaining == 0)
    }

    /// A small widget gives up rows for the month grid and for nothing else:
    /// on its own the event list has the whole widget.
    @Test func onlyTheGridCostsASmallWidgetItsEventRows() {
        #expect(CalendarFormat.eventLimit(isCompact: true, showsGrid: true, maximum: 5) == 2)
        #expect(CalendarFormat.eventLimit(isCompact: true, showsGrid: false, maximum: 5) == 5)
        #expect(CalendarFormat.eventLimit(isCompact: false, showsGrid: true, maximum: 5) == 5)
        // A user who asked for one event gets one, grid or no grid.
        #expect(CalendarFormat.eventLimit(isCompact: true, showsGrid: true, maximum: 1) == 1)
    }

    /// The Lock Screen strip has room for one event, so which one it picks is
    /// the whole design: what is running or still to come, and an all-day
    /// entry only when nothing timed is left.
    @Test func theLockScreenPicksTheEventStillToCome() throws {
        let allDay = CalendarSnapshot.Event(
            id: "all", title: "Film scans due",
            startDate: date(2026, 9, 21, hour: 0), endDate: date(2026, 9, 22, hour: 0),
            isAllDay: true, colorHex: nil
        )
        let morning = CalendarSnapshot.Event(
            id: "am", title: "Client shoot",
            startDate: date(2026, 9, 21, hour: 9), endDate: date(2026, 9, 21, hour: 11),
            isAllDay: false, colorHex: nil
        )
        let afternoon = CalendarSnapshot.Event(
            id: "pm", title: "Lens pickup",
            startDate: date(2026, 9, 21, hour: 14), endDate: date(2026, 9, 21, hour: 15),
            isAllDay: false, colorHex: nil
        )
        let events = [allDay, morning, afternoon]

        // Before anything starts: the first timed event.
        #expect(CalendarFormat.nextEvent(in: events, at: date(2026, 9, 21, hour: 8))?.id == "am")
        // While one is running: that one, not the next.
        #expect(CalendarFormat.nextEvent(in: events, at: date(2026, 9, 21, hour: 10))?.id == "am")
        // After it ends: the next one.
        #expect(CalendarFormat.nextEvent(in: events, at: date(2026, 9, 21, hour: 12))?.id == "pm")
        // Once the timed ones are over, the all-day entry is what is left.
        #expect(CalendarFormat.nextEvent(in: events, at: date(2026, 9, 21, hour: 20))?.id == "all")
        // A day with only an all-day entry shows it at any hour.
        #expect(CalendarFormat.nextEvent(in: [allDay], at: date(2026, 9, 21, hour: 8))?.id == "all")
        #expect(CalendarFormat.nextEvent(in: [], at: date(2026, 9, 21)) == nil)
    }

    /// The anchor is a fraction of the space the text block can occupy, and
    /// the offset is measured from the alignment stop it rounds to — that is
    /// what keeps a block dragged to an edge inside the widget.
    @Test func theAnchorPlacesTheTextInsideTheWidget() {
        let size = CGSize(width: 300, height: 150)
        let content = CGSize(width: 100, height: 40)
        let inset: CGFloat = 4
        // Top-left: sits at the stop, so no offset.
        let topLeading = PhotoWidgetSettings.Anchor(x: 0, y: 0)
        #expect(topLeading.offset(in: size, contentSize: content, inset: inset) == .zero)
        #expect(topLeading.alignment == .topLeading)
        // Bottom-right: also at a stop, and the alignment carries it.
        let bottomTrailing = PhotoWidgetSettings.Anchor(x: 1, y: 1)
        #expect(bottomTrailing.offset(in: size, contentSize: content, inset: inset) == .zero)
        #expect(bottomTrailing.alignment == .bottomTrailing)
        // A point between stops is offset from the nearest one, and never
        // past the free space.
        let middle = PhotoWidgetSettings.Anchor(x: 0.5, y: 0.5)
        #expect(middle.offset(in: size, contentSize: content, inset: inset) == .zero)
        let quarter = PhotoWidgetSettings.Anchor(x: 0.25, y: 0.25)
        let offset = quarter.offset(in: size, contentSize: content, inset: inset)
        #expect(offset.width > 0)
        #expect(offset.height > 0)
        #expect(offset.width <= size.width - content.width - inset * 2)
    }

    @Test func anchorsAreClampedAndReadAsAlignments() {
        #expect(PhotoWidgetSettings.Anchor(x: -3, y: 9) == PhotoWidgetSettings.Anchor(x: 0, y: 1))
        #expect(PhotoWidgetSettings.Anchor(x: 0.1, y: 0.5).isLeading)
        #expect(PhotoWidgetSettings.Anchor(x: 0.9, y: 0.5).isTrailing)
        #expect(!PhotoWidgetSettings.Anchor(x: 0.5, y: 0.5).isLeading)
    }

    /// A settings file from the version whose text sat in a corner opens where
    /// that corner was, instead of jumping to the middle.
    @Test func theOldCornerPlacementBecomesAnAnchor() throws {
        let legacy = """
        {"placement":"bottomLeading","showsTime":true,"timeSize":34}
        """
        let decoded = try JSONDecoder().decode(
            PhotoWidgetSettings.self, from: Data(legacy.utf8)
        )
        #expect(decoded.anchor == .bottomLeading)
        #expect(decoded.timeSize == 34)
        // Fields the old file never had fall back to their defaults.
        #expect(decoded.photoScale == 1)

        #expect(PhotoWidgetSettings.anchor(forLegacyPlacement: "center") == .center)
        #expect(PhotoWidgetSettings.anchor(forLegacyPlacement: "nonsense") == nil)
    }

    // MARK: Home Screen configuration

    /// What the Home Screen's menu says wins where it said something, and says
    /// nothing by default — the widget then shows what ShotDex is set to.
    @Test func theHomeScreenMenuOverridesOnlyWhatItAnswers() {
        var stored = PhotoWidgetSettings.default(for: .clock)
        stored.rotation = .daily
        stored.photoDimming = 0.1
        stored.source = .photo(assetId: "ABC/L0/001")

        let untouched = PhotoWidgetResolvedConfiguration.resolve(
            kind: .clock, settings: stored,
            albumId: nil, albumTitle: nil, rotation: nil, dimming: nil,
            frameCount: { _ in 3 }
        )
        #expect(untouched.settings.rotation == .daily)
        #expect(untouched.settings.photoDimming == 0.1)
        #expect(untouched.frameDirectoryName == PhotoWidgetKind.clock.directoryName)
        #expect(untouched.pendingAlbum == nil)

        let configured = PhotoWidgetResolvedConfiguration.resolve(
            kind: .clock, settings: stored,
            albumId: "9F98/L0/040", albumTitle: "Iceland",
            rotation: .hourly, dimming: 0.3,
            frameCount: { _ in 5 }
        )
        #expect(configured.settings.rotation == .hourly)
        #expect(configured.settings.photoDimming == 0.3)
        #expect(configured.settings.source == .album(collectionId: "9F98/L0/040", title: "Iceland"))
        #expect(configured.frameDirectoryName == PhotoWidgetSnapshot.albumDirectoryName(albumId: "9F98/L0/040"))
        #expect(configured.pendingAlbum == nil)
    }

    /// An album with no frames yet is reported as pending, which is what makes
    /// the widget ask the app for it instead of drawing black.
    @Test func anAlbumWithoutPicturesIsPending() throws {
        let resolved = PhotoWidgetResolvedConfiguration.resolve(
            kind: .weather, settings: .default(for: .weather),
            albumId: "AAA/L0/001", albumTitle: "Trips",
            rotation: nil, dimming: nil,
            frameCount: { _ in 0 }
        )
        let pending = try #require(resolved.pendingAlbum)
        #expect(pending.id == "AAA/L0/001")
        #expect(pending.title == "Trips")
    }

    /// PhotoKit identifiers carry slashes, which are path separators.
    /// One photo is the more specific answer, so it wins over an album set on
    /// the same widget.
    @Test func aChosenPhotoBeatsAChosenAlbum() throws {
        let resolved = PhotoWidgetResolvedConfiguration.resolve(
            kind: .clock,
            settings: .default(for: .clock),
            photoId: "PIC/L0/001",
            photoLabel: "Sep 21, 2026 at 09:30",
            albumId: "ALB/L0/040",
            albumTitle: "Iceland",
            rotation: nil,
            dimming: nil,
            frameCount: { _ in 1 }
        )
        #expect(resolved.settings.source == .photo(assetId: "PIC/L0/001"))
        #expect(resolved.frameDirectoryName == PhotoWidgetSnapshot.assetDirectoryName(assetId: "PIC/L0/001"))
        #expect(resolved.pendingAlbum == nil)
    }

    @Test func aChosenPhotoWithoutAFrameAsksForOne() throws {
        let resolved = PhotoWidgetResolvedConfiguration.resolve(
            kind: .weather,
            settings: .default(for: .weather),
            photoId: "PIC/L0/002",
            photoLabel: "Yesterday",
            albumId: nil,
            albumTitle: nil,
            rotation: nil,
            dimming: nil,
            frameCount: { _ in 0 }
        )
        let pending = try #require(resolved.pendingAlbum)
        #expect(pending.id == "PIC/L0/002")
        #expect(resolved.pendingSourceKind == .photo)
    }

    /// A photo's folder and an album's folder never collide, even when the two
    /// identifiers slug to the same thing.
    @Test func aPhotoFolderIsNotAnAlbumFolder() {
        let identifier = "9F98-3C/L0/040"
        let album = PhotoWidgetSnapshot.albumDirectoryName(albumId: identifier)
        let asset = PhotoWidgetSnapshot.assetDirectoryName(assetId: identifier)
        #expect(album != asset)
        #expect(!asset.contains("/"))
    }

    /// The queue was album-only before single photos existed, and a queue
    /// written by that build still decodes.
    @Test func anOlderQueueEntryIsReadAsAnAlbumAsk() throws {
        let legacy = """
        {"requests":[{"albumId":"A/L0/1","title":"Trips","requestedAt":0}]}
        """
        let decoded = try JSONDecoder().decode(
            PhotoWidgetFrameRequests.self, from: Data(legacy.utf8)
        )
        #expect(decoded.requests.first?.source == .album)
        #expect(decoded.requests.first?.frameDirectoryName.hasPrefix("photo-widget-album-") == true)
    }

    /// Frames from the build that rendered at 1000 px are marked for redoing;
    /// the ones written since are left alone.
    @Test func framesRenderedSmallerThanTodayAreStale() {
        let old = PhotoWidgetSnapshot(frames: [], generatedAt: .now, renderedPixels: nil)
        #expect(old.isBelow(pixels: 1_600))
        let smaller = PhotoWidgetSnapshot(frames: [], generatedAt: .now, renderedPixels: 1_000)
        #expect(smaller.isBelow(pixels: 1_600))
        let current = PhotoWidgetSnapshot(frames: [], generatedAt: .now, renderedPixels: 1_600)
        #expect(!current.isBelow(pixels: 1_600))
    }

    @Test func thePhotoCatalogSearchesItsLabels() {
        let catalog = WidgetPhotoCatalog(
            photos: [
                .init(id: "1", label: "Sep 21, 2026 at 09:30", thumbnailFileName: "a.jpg"),
                .init(id: "2", label: "Aug 8, 2012 at 23:55", thumbnailFileName: "b.jpg"),
            ],
            generatedAt: .now
        )
        #expect(catalog.matching("sep").map(\.id) == ["1"])
        #expect(catalog.matching("2012").map(\.id) == ["2"])
        #expect(catalog.matching("").count == 2)
        #expect(catalog.photo(id: "2")?.label.hasPrefix("Aug") == true)
    }

    @Test func anAlbumFolderNameIsSafeToPutOnDisk() {
        let name = PhotoWidgetSnapshot.albumDirectoryName(albumId: "9F98-3C/L0/040")
        #expect(!name.contains("/"))
        #expect(name.hasPrefix("photo-widget-album-"))
        // Two albums never collide into one folder.
        #expect(name != PhotoWidgetSnapshot.albumDirectoryName(albumId: "9F98-3C/L0/041"))
    }

    @Test func theRenderQueueKeepsTheNewestAsksAndNoDuplicates() {
        let first = PhotoWidgetFrameRequest(albumId: "a", title: "A", requestedAt: date(2026, 9, 21, hour: 1))
        let second = PhotoWidgetFrameRequest(albumId: "b", title: "B", requestedAt: date(2026, 9, 21, hour: 2))
        let againA = PhotoWidgetFrameRequest(albumId: "a", title: "A renamed", requestedAt: date(2026, 9, 21, hour: 3))

        var queue = PhotoWidgetFrameRequests.merged([], adding: first)
        queue = PhotoWidgetFrameRequests.merged(queue, adding: second)
        #expect(queue.map(\.albumId) == ["b", "a"])

        queue = PhotoWidgetFrameRequests.merged(queue, adding: againA)
        #expect(queue.map(\.albumId) == ["a", "b"])
        #expect(queue.first?.title == "A renamed")

        // The queue is capped, oldest first out.
        var long: [PhotoWidgetFrameRequest] = []
        for index in 0..<12 {
            long = PhotoWidgetFrameRequests.merged(
                long,
                adding: PhotoWidgetFrameRequest(
                    albumId: "album-\(index)", title: "\(index)",
                    requestedAt: date(2026, 9, 21, hour: 1)
                ),
                limit: 8
            )
        }
        #expect(long.count == 8)
        #expect(long.first?.albumId == "album-11")
    }

    @Test func theAlbumCatalogFindsNamesWithoutAccentsOrCase() {
        let catalog = WidgetAlbumCatalog(
            albums: [
                .init(id: "1", title: "Đà Lạt", count: 40),
                .init(id: "2", title: "Iceland", count: 12),
            ],
            generatedAt: .now
        )
        #expect(catalog.matching("da lat").map(\.id) == ["1"])
        #expect(catalog.matching("ICE").map(\.id) == ["2"])
        #expect(catalog.matching("").count == 2)
        #expect(catalog.album(id: "2")?.title == "Iceland")
        #expect(catalog.album(id: "nope") == nil)
    }

    @Test func onlyTheWeatherAndCalendarReachTheLockScreen() {
        #expect(PhotoWidgetKind.allCases.filter(\.hasAccessoryFamilies) == [.calendar, .weather])
    }

    /// A widget left unrefreshed overnight must not show yesterday's meetings
    /// as today's.
    @Test func eventsAreOnlyOfferedForTheDayTheyWereReadFor() {
        let snapshot = CalendarSnapshot(
            dayKey: WidgetSharedContainer.dayKey(for: date(2026, 9, 20), calendar: calendar),
            events: [],
            hasAccess: true,
            generatedAt: date(2026, 9, 20)
        )
        #expect(snapshot.events(on: date(2026, 9, 20), calendar: calendar) != nil)
        #expect(snapshot.events(on: date(2026, 9, 21), calendar: calendar) == nil)
    }

    @Test func anAllDayEventSaysSoInsteadOfATime() {
        let allDay = CalendarSnapshot.Event(
            id: "1", title: "Trip", startDate: date(2026, 9, 20, hour: 0),
            endDate: date(2026, 9, 21, hour: 0), isAllDay: true, colorHex: nil
        )
        #expect(CalendarFormat.timeString(for: allDay) == "All day")
    }

    // MARK: Weather

    @Test func temperatureFollowsTheUnitAsked() {
        let us = Locale(identifier: "en_US")
        let gb = Locale(identifier: "en_GB")
        #expect(WeatherFormat.temperatureString(celsius: 21.4, unit: .celsius, locale: us) == "21°")
        #expect(WeatherFormat.temperatureString(celsius: 100, unit: .fahrenheit, locale: gb) == "212°")
        // System follows the region, not the setting.
        #expect(WeatherFormat.temperatureString(celsius: 0, unit: .system, locale: gb) == "0°")
        #expect(WeatherFormat.temperatureString(celsius: 0, unit: .system, locale: us) == "32°")
    }

    @Test func highAndLowNeedBothEnds() {
        #expect(
            WeatherFormat.highLowString(
                highCelsius: 30, lowCelsius: 22, unit: .celsius
            ) == "H 30°  L 22°"
        )
        #expect(WeatherFormat.highLowString(highCelsius: 30, lowCelsius: nil, unit: .celsius) == nil)
    }

    @Test func conditionCodesBecomeWordsAndNightSymbols() {
        #expect(WeatherFormat.conditionName(code: 0) == "Clear")
        #expect(WeatherFormat.conditionName(code: 95) == "Thunderstorms")
        #expect(WeatherFormat.conditionName(code: 4242) == "—")
        #expect(WeatherFormat.symbolName(code: 0, isNight: false) == "sun.max.fill")
        #expect(WeatherFormat.symbolName(code: 0, isNight: true) == "moon.stars.fill")
    }

    @Test func aReadingGoesStaleRatherThanLying() {
        let reading = WeatherSnapshot(
            temperatureCelsius: 20, highCelsius: nil, lowCelsius: nil,
            conditionCode: 0, placeName: nil, isNight: false,
            updatedAt: date(2026, 9, 20, hour: 6)
        )
        #expect(!reading.isStale(at: date(2026, 9, 20, hour: 8)))
        #expect(reading.isStale(at: date(2026, 9, 20, hour: 12)))
    }

    // MARK: Settings per widget

    @Test func everyWidgetOpensOnTheRowsItIsNamedAfter() {
        #expect(PhotoWidgetSettings.default(for: .clock).showsTime)
        #expect(!PhotoWidgetSettings.default(for: .calendar).showsTime)
        #expect(!PhotoWidgetSettings.default(for: .weather).showsTime)
        #expect(PhotoWidgetSettings.default(for: .combined).showsTime)
        #expect(PhotoWidgetKind.allCases.filter(\.needsWeather) == [.weather, .combined])
        #expect(PhotoWidgetKind.allCases.filter(\.needsCalendarEvents) == [.calendar, .combined])
        // The kinds are the identifiers WidgetKit stores against a placed
        // widget: changing one orphans it.
        #expect(PhotoWidgetKind.clock.widgetKind == "ShotDexClock")
        #expect(Set(PhotoWidgetKind.allCases.map(\.widgetKind)).count == PhotoWidgetKind.allCases.count)
    }

    @Test func theSettingsFileKeepsOneEntryPerKind() {
        var file = PhotoWidgetSettingsFile.default
        #expect(file[.weather].showsHighLow)
        file[.weather].showsHighLow = false
        #expect(!file[.weather].showsHighLow)
        // Other widgets are untouched by one widget's edit.
        #expect(file[.combined].showsHighLow)
    }
}
