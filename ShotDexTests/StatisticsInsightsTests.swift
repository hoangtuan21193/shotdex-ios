import Foundation
import Testing
@testable import ShotDex

/// FS-07.02 Insights: the pure selection rules, the sentence copy, and the
/// SQL that feeds them (in-memory GRDB).
struct StatisticsInsightsTests {

    // MARK: Selector (AC-7 and the thresholds of §2–§5)

    /// The AC-7 numbers: focal 85% at 26mm, top pair 40%, 18% slow, August
    /// 2026 with 1,240 photos against a 300 median.
    private func ac7Inputs() -> InsightInputs {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.equivalentFocalCounts = [26: 850, 77: 150]
        inputs.focalAngleCounts = [.wide: 850, .portrait: 150]
        inputs.actualFocalCount = 1000
        inputs.topPairs = [
            .init(body: "EOS R6", lens: "RF 85mm F1.2 L USM", count: 400),
            .init(body: "iPhone 15 Pro", lens: "iPhone 15 Pro back triple camera 6.765mm f/1.78", count: 380),
        ]
        inputs.photosWithCameraAndLens = 1000
        inputs.slowShutterCount = 180
        inputs.shutterAndFocalCount = 1000
        inputs.monthCounts = [
            .init(year: 2026, month: 5, count: 300), .init(year: 2026, month: 6, count: 300),
            .init(year: 2026, month: 7, count: 280), .init(year: 2026, month: 8, count: 1240),
            .init(year: 2026, month: 9, count: 320),
        ]
        return inputs
    }

    /// AC-7: three sentences, focal → pair → slow, the month dropped as the
    /// fourth; a second run gives the identical list.
    @Test func selectorKeepsFixedOrderAndDropsFourth() {
        let inputs = ac7Inputs()
        #expect(InsightSelector.median(inputs.monthCounts.map(\.count)) == 300)
        #expect(InsightSelector.busiestMonth(inputs) != nil, "the month qualifies on its own")

        let sentences = InsightSelector.select(inputs)
        #expect(sentences.count == 3)
        guard sentences.count == 3 else { return }
        #expect(sentences[0].kind == .focalValue(millimetres: 26, count: 850, denominator: 1000, namesDenominator: false))
        #expect(sentences[1].kind == .pair(
            body: "EOS R6", lens: "RF 85mm F1.2 L USM", count: 400, denominator: 1000, namesDenominator: false
        ))
        #expect(sentences[2].kind == .slowShutter(count: 180, denominator: 1000, namesDenominator: false))
        #expect(!sentences.contains { if case .busiestMonth = $0.kind { true } else { false } })
    }

    @Test func selectorIsDeterministic() {
        let inputs = ac7Inputs()
        let first = InsightSelector.select(inputs)
        for _ in 0..<5 { #expect(InsightSelector.select(inputs) == first) }
        #expect(InsightSelector.cardState(indexedRows: 1000, inputs: inputs)
            == InsightSelector.cardState(indexedRows: 1000, inputs: inputs))
    }

    @Test func sharedThresholdIsFiftyPhotosWithCamera() {
        var inputs = ac7Inputs()
        inputs.photosWithCamera = 49
        #expect(InsightSelector.select(inputs).isEmpty)
        #expect(InsightSelector.cardState(indexedRows: 279, inputs: inputs) == .belowThreshold(photosWithCamera: 49))
        inputs.photosWithCamera = 50
        #expect(!InsightSelector.select(inputs).isEmpty)
        #expect(InsightSelector.cardState(indexedRows: 0, inputs: inputs) == .hidden)
    }

    @Test func pairNeedsTwentyPercentTwoPairsAndFiftyPhotos() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.photosWithCameraAndLens = 1000
        inputs.topPairs = [.init(body: "A", lens: "x", count: 199), .init(body: "B", lens: "y", count: 150)]
        #expect(InsightSelector.pair(inputs) == nil, "19.9% stays out")
        inputs.topPairs[0].count = 200
        #expect(InsightSelector.pair(inputs) != nil, "20% is in")
        inputs.topPairs.removeLast()
        #expect(InsightSelector.pair(inputs) == nil, "one pair is not a habit")
        inputs.topPairs = [.init(body: "A", lens: "x", count: 30), .init(body: "B", lens: "y", count: 19)]
        inputs.photosWithCameraAndLens = 49
        #expect(InsightSelector.pair(inputs) == nil, "49 photos with both names")
    }

    @Test func pairTieGoesToNameOrder() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 100
        inputs.photosWithCameraAndLens = 100
        inputs.topPairs = [.init(body: "Z9", lens: "a", count: 50), .init(body: "A7", lens: "b", count: 50)]
        guard case .pair(let body, _, _, _, _) = InsightSelector.pair(inputs)?.kind else {
            Issue.record("no pair sentence"); return
        }
        #expect(body == "A7")
    }

    @Test func slowShutterNeedsFivePercent() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.shutterAndFocalCount = 1000
        inputs.slowShutterCount = 49
        #expect(InsightSelector.slowShutter(inputs) == nil, "4.9% stays out")
        inputs.slowShutterCount = 50
        #expect(InsightSelector.slowShutter(inputs) != nil, "5% is in")
        #expect(InsightSelector.slowShutter(inputs)?.filter == nil, "no filter can say it")
    }

    @Test func busiestMonthNeedsTwiceTheMedian() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.monthCounts = [
            .init(year: 2026, month: 1, count: 100), .init(year: 2026, month: 2, count: 100),
            .init(year: 2026, month: 3, count: 199),
        ]
        #expect(InsightSelector.busiestMonth(inputs) == nil, "1.99 × the median")
        inputs.monthCounts[2].count = 200
        #expect(InsightSelector.busiestMonth(inputs)?.kind == .busiestMonth(year: 2026, month: 3, count: 200))
        inputs.monthCounts.removeFirst()
        #expect(InsightSelector.busiestMonth(inputs) == nil, "two months are not enough")
    }

    @Test func busiestMonthTieGoesToTheRecentOne() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.monthCounts = [
            .init(year: 2025, month: 3, count: 400), .init(year: 2026, month: 1, count: 10),
            .init(year: 2026, month: 2, count: 10), .init(year: 2026, month: 3, count: 400),
            .init(year: 2026, month: 4, count: 10),
        ]
        #expect(InsightSelector.busiestMonth(inputs)?.kind == .busiestMonth(year: 2026, month: 3, count: 400))
        // An even number of months: the median is the mean of the middle two.
        #expect(InsightSelector.median([300, 280, 1240, 320]) == 310)
    }

    /// §5: a value with half → that value (shorter on a tie); else the
    /// fullest Library angle group; else that group with its fuller
    /// neighbour; else nothing.
    @Test func focalFallsBackFromValueToGroupToMergedGroups() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 100
        inputs.actualFocalCount = 100

        inputs.equivalentFocalCounts = [24: 50, 50: 50]
        inputs.focalAngleCounts = [.wide: 50, .standard: 50]
        #expect(InsightSelector.focal(inputs)?.kind
            == .focalValue(millimetres: 24, count: 50, denominator: 100, namesDenominator: false))

        inputs.equivalentFocalCounts = [24: 30, 28: 30, 85: 40]
        inputs.focalAngleCounts = [.wide: 60, .portrait: 40]
        let group = InsightSelector.focal(inputs)
        #expect(group?.kind == .focalGroup(buckets: [.wide], count: 60, denominator: 100, namesDenominator: false))
        #expect(group?.filter?.focalRange == FocalAngleBucket.wide.range)
        #expect(group?.filter?.focalLengthMode == .equivalent)

        inputs.equivalentFocalCounts = [16: 10, 24: 40, 50: 20, 85: 30]
        inputs.focalAngleCounts = [.ultraWide: 10, .wide: 40, .standard: 20, .portrait: 30]
        let merged = InsightSelector.focal(inputs)
        #expect(merged?.kind == .focalGroup(buckets: [.wide, .standard], count: 60, denominator: 100, namesDenominator: false))
        #expect(merged?.filter?.focalRange == NumericRangeFilter(lowerBound: 20, upperBound: 69.999))

        inputs.equivalentFocalCounts = [16: 25, 50: 25, 100: 25, 400: 25]
        inputs.focalAngleCounts = [.ultraWide: 25, .standard: 25, .portrait: 25, .superTelephoto: 25]
        #expect(InsightSelector.focal(inputs) == nil)
    }

    /// The value sentence's filter covers exactly the SQL ROUND() bucket.
    @Test func focalValueFilterIsTheRoundingBucket() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 1000
        inputs.actualFocalCount = 1000
        inputs.equivalentFocalCounts = [26: 850, 77: 150]
        let range = InsightSelector.focal(inputs)?.filter?.focalRange
        #expect(range?.contains(25.5) == true)
        #expect(range?.contains(26.4999) == true)
        #expect(range?.contains(26.5) == false)
        #expect(range?.contains(25.4999) == false)
    }

    @Test func unknownSensorHalfSuppressesFocalAndShowsFooter() {
        var inputs = InsightInputs()
        inputs.photosWithCamera = 200
        inputs.actualFocalCount = 200
        inputs.unknownSensorCount = 180
        inputs.equivalentFocalCounts = [50: 20]
        inputs.focalAngleCounts = [.standard: 20]
        #expect(InsightSelector.focal(inputs) == nil)
        #expect(InsightSelector.cardState(indexedRows: 200, inputs: inputs) == .insights([], unknownSensorCount: 180))

        inputs.unknownSensorCount = 99
        inputs.equivalentFocalCounts = [50: 101]
        #expect(InsightSelector.focal(inputs) != nil)
    }

    // MARK: Copy (AC-8)

    private let english = Locale(identifier: "en_US")

    /// Every sentence the card can say, each variant, with photo counts of 1
    /// and 2 and shares of 99.6% and 100%.
    private func everySentence() -> [String] {
        var kinds: [Insight.Kind] = []
        for (count, total) in [(1, 1), (2, 2), (996, 1000), (1000, 1000)] {
            for names in [false, true] {
                kinds.append(.focalValue(millimetres: 26, count: count, denominator: total, namesDenominator: names))
                kinds.append(.focalGroup(buckets: [.wide], count: count, denominator: total, namesDenominator: names))
                kinds.append(.focalGroup(buckets: [.ultraWide], count: count, denominator: total, namesDenominator: names))
                kinds.append(.focalGroup(buckets: [.telephoto, .superTelephoto], count: count, denominator: total, namesDenominator: names))
                kinds.append(.pair(body: "EOS R6", lens: "RF 85mm F1.2 L USM", count: count, denominator: total, namesDenominator: names))
                kinds.append(.slowShutter(count: count, denominator: total, namesDenominator: names))
            }
            kinds.append(.busiestMonth(year: 2026, month: 8, count: count))
        }
        var lines = kinds.map { InsightCopy.sentence(Insight(kind: $0, filter: nil), locale: english) }
        for count in [1, 2] {
            lines.append(InsightCopy.belowThreshold(count, locale: english))
            lines.append(InsightCopy.unknownSensorFooter(count, locale: english))
        }
        lines.append(InsightCopy.indexingFooter(locale: english))
        return lines
    }

    @Test func copyUsesPluralVariants() {
        let one = InsightCopy.sentence(Insight(kind: .busiestMonth(year: 2026, month: 8, count: 1), filter: nil), locale: english)
        let two = InsightCopy.sentence(Insight(kind: .busiestMonth(year: 2026, month: 8, count: 2), filter: nil), locale: english)
        let many = InsightCopy.sentence(Insight(kind: .busiestMonth(year: 2026, month: 8, count: 1240), filter: nil), locale: english)
        #expect(one == "August 2026 was your busiest month: 1 photo.")
        #expect(two == "August 2026 was your busiest month: 2 photos.")
        #expect(many == "August 2026 was your busiest month: 1,240 photos.")
        #expect(InsightCopy.unknownSensorFooter(1, locale: english) == "1 photo is from a camera with an unknown sensor size.")
        #expect(InsightCopy.unknownSensorFooter(2, locale: english) == "2 photos are from cameras with an unknown sensor size.")
    }

    @Test func percentNeverRoundsUpToHundred() {
        #expect(InsightCopy.percent(996, of: 1000, locale: english) == "99%")
        #expect(InsightCopy.percent(995, of: 1000, locale: english) == "99%")
        #expect(InsightCopy.percent(999_999, of: 1_000_000, locale: english) == "99%")
        #expect(InsightCopy.percent(1000, of: 1000, locale: english) == "100%")
        #expect(InsightCopy.percent(850, of: 1000, locale: english) == "85%")
        let nearlyAll = InsightCopy.sentence(
            Insight(kind: .slowShutter(count: 996, denominator: 1000, namesDenominator: false), filter: nil), locale: english
        )
        #expect(nearlyAll.hasPrefix("99% "))
    }

    /// §4: no verb that advises or judges, in any template or variant.
    @Test func noTemplateContainsBannedWords() throws {
        let banned = ["buy", "sell", "upgrade", "should", "try", "consider", "recommend", "need", "better", "worse"]
        let regex = try NSRegularExpression(pattern: "\\b(\(banned.joined(separator: "|")))\\b", options: .caseInsensitive)
        let lines = everySentence()
        #expect(lines.count > 50)
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            #expect(regex.firstMatch(in: line, range: range) == nil, "banned word in: \(line)")
            // A template that failed to resolve would show its raw specifiers.
            #expect(!line.contains("%@") && !line.contains("%lld") && !line.contains("#@"), "unformatted: \(line)")
        }
    }

    @Test func focalUsesAppFormatter() {
        let sentence = InsightCopy.sentence(
            Insight(kind: .focalValue(millimetres: 26, count: 850, denominator: 1000, namesDenominator: false), filter: nil),
            locale: english
        )
        #expect(sentence == "85% of your photos are at 26mm equivalent.")
        #expect(sentence.contains(MetadataFormatter.focalLength(26) ?? "–"))
        let group = InsightCopy.sentence(
            Insight(kind: .focalGroup(buckets: [.wide, .standard], count: 600, denominator: 1000, namesDenominator: false), filter: nil),
            locale: english
        )
        #expect(group == "60% of your photos are at 20–69mm equivalent (Wide and Standard).")
        #expect(InsightCopy.focalRange([.ultraWide]) == "under 20mm")
        #expect(InsightCopy.focalRange([.superTelephoto]) == "300mm and longer")
        #expect(InsightCopy.belowThreshold(49, locale: english)
            == "Insights appear once 50 photos have camera info — 49 so far.")
    }

    // MARK: SQL inputs and card state (AC-2, AC-1)

    /// One indexed row. `camera: nil` with no focal values is a screenshot;
    /// `mediaType: 2` a video.
    private func record(
        _ id: String,
        camera: String? = nil,
        lens: String? = nil,
        focal: Double? = nil,
        equivalent: Double? = nil,
        shutter: Double? = nil,
        creation: Int? = 1_780_000_000,
        mediaType: Int = 1
    ) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id, creationDate: creation, modificationDate: creation, mediaType: mediaType,
            cameraManufacturer: nil, cameraModel: camera, normalizedCameraModel: camera,
            normalizedCameraManufacturer: nil, lensManufacturer: nil, lensModel: lens, normalizedLensModel: lens,
            originalFilename: nil, iso: nil, aperture: nil, shutterSpeedSeconds: shutter,
            shutterSpeedDisplay: shutter.flatMap(MetadataFormatter.shutterSpeed),
            focalLength: focal, focalLengthIn35mm: nil, calculatedEquivalentFocalLength: equivalent,
            equivalentFocalLength: equivalent, sensorFormat: nil, cropFactor: nil, width: 4000, height: 3000,
            fileSize: 1_000_000, latitude: nil, longitude: nil, isFavorite: false, indexedAt: 1_780_000_000,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    private func save(_ records: [PhotoMetadata], into database: AppDatabase) throws {
        try MetadataStore(database: database).saveBatch(records, cursorAssetId: nil)
    }

    /// AC-2: 49 photos with a camera, 200 EXIF-less screenshots and 30
    /// videos (which carry a camera name too) — below the threshold at 49.
    @Test func belowThresholdCountsStillPhotosWithCameraOnly() throws {
        let database = try AppDatabase.makeEmpty()
        var rows = (0..<49).map { record("p\($0)", camera: "EOS R6", lens: "RF 50mm", focal: 50, equivalent: 50, shutter: 1.0 / 250) }
        rows += (0..<200).map { record("s\($0)") }
        rows += (0..<30).map { record("v\($0)", camera: "iPhone 15 Pro", mediaType: 2) }
        try save(rows, into: database)

        let queries = StatisticsQueries(database: database)
        let inputs = try queries.insightInputs()
        #expect(inputs.photosWithCamera == 49)
        #expect(InsightSelector.select(inputs).isEmpty)
        let state = InsightSelector.cardState(indexedRows: try queries.totalPhotos(scope: .allTime), inputs: inputs)
        #expect(state == .belowThreshold(photosWithCamera: 49))
        #expect(InsightCopy.belowThreshold(49, locale: english)
            == "Insights appear once 50 photos have camera info — 49 so far.")
    }

    /// AC-1: nothing indexed — no card at all.
    @Test func cardStateForEmptyLibraryIsHidden() throws {
        let database = try AppDatabase.makeEmpty()
        let queries = StatisticsQueries(database: database)
        let inputs = try queries.insightInputs()
        #expect(inputs.photosWithCamera == 0 && inputs.equivalentFocalTotal == 0 && inputs.monthCounts.isEmpty)
        #expect(InsightSelector.cardState(indexedRows: try queries.totalPhotos(scope: .allTime), inputs: inputs) == .hidden)
    }

    /// Every Insights query in one read returns few rows; a video never
    /// enters a count.
    @Test func insightInputsGroupInSQL() throws {
        let database = try AppDatabase.makeEmpty()
        var rows = (0..<60).map { record("a\($0)", camera: "X-T5", lens: "XF23mmF1.4 R", focal: 23, equivalent: 34.5, shutter: 1.0 / 15) }
        rows += (0..<40).map { record("b\($0)", camera: "X-T5", lens: "XF33mmF1.4 R", focal: 33, equivalent: 49.5, shutter: 1.0 / 250) }
        rows += (0..<10).map { record("v\($0)", camera: "X-T5", lens: "XF23mmF1.4 R", focal: 23, equivalent: 34.5, shutter: 1.0 / 15, mediaType: 2) }
        try save(rows, into: database)

        let inputs = try StatisticsQueries(database: database).insightInputs()
        #expect(inputs.photosWithCamera == 100)
        // ROUND(34.5) = 35, ROUND(49.5) = 50 — SQLite rounds halves away from zero.
        #expect(inputs.equivalentFocalCounts == [35: 60, 50: 40])
        #expect(inputs.focalAngleCounts[.standard] == 40)
        #expect(inputs.focalAngleCounts[.wide] == 60)
        #expect(inputs.topPairs.map(\.count) == [60, 40])
        #expect(inputs.photosWithCameraAndLens == 100)
        #expect(inputs.slowShutterCount == 60)
        #expect(inputs.shutterAndFocalCount == 100)
        #expect(inputs.monthCounts.reduce(0) { $0 + $1.count } == 100)
    }

    // MARK: Focal sentence on real rows (AC-3)

    /// AC-3: 1,000 iPhone 13 Pro photos, 850 on the main module (26mm
    /// equivalent), 150 on the tele (77mm): the value sentence, and a filter
    /// whose Library count is the sentence's 850.
    @Test func focalSentenceUsesEquivalentValue() throws {
        let database = try AppDatabase.makeEmpty()
        var rows = (0..<850).map {
            record("m\($0)", camera: "iPhone 13 Pro", lens: "iPhone 13 Pro back triple camera 5.7mm f/1.5",
                   focal: 5.7, equivalent: 26, shutter: 1.0 / 120)
        }
        rows += (0..<150).map {
            record("t\($0)", camera: "iPhone 13 Pro", lens: "iPhone 13 Pro back triple camera 9mm f/2.8",
                   focal: 9, equivalent: 77, shutter: 1.0 / 120)
        }
        try save(rows, into: database)

        let inputs = try StatisticsQueries(database: database).insightInputs()
        let first = try #require(InsightSelector.select(inputs).first)
        #expect(InsightCopy.sentence(first, locale: english) == "85% of your photos are at 26mm equivalent.")
        let filter = try #require(first.filter)
        #expect(filter.focalLengthMode == .equivalent)
        #expect(filter.focalRange.lowerBound == 25.5)
        #expect(filter.focalRange.upperBound.map { abs($0 - 26.5) < 0.001 && $0 < 26.5 } == true)
        #expect(try LibraryQueries(database: database).count(matching: filter) == 850)
    }

    /// No single focal length holds half, the Wide group does: the group
    /// sentence counts with the Library filter's bounds, so a photo at
    /// 19.999 or 35mm stays out and one at 20 or 34.999 is in — the same
    /// photos the grid shows after the tap.
    @Test func angleGroupSentenceCountEqualsFilterCount() throws {
        let database = try AppDatabase.makeEmpty()
        var rows: [PhotoMetadata] = []
        for (value, count) in [(19.999, 15), (20.0, 14), (25.0, 14), (34.999, 12), (35.0, 15)] {
            rows += (0..<count).map { record("f\(value)-\($0)", camera: "EOS R6", focal: value, equivalent: value) }
        }
        try save(rows, into: database)

        let inputs = try StatisticsQueries(database: database).insightInputs()
        #expect(inputs.focalAngleCounts[.ultraWide] == 15)
        #expect(inputs.focalAngleCounts[.wide] == 40)
        #expect(inputs.focalAngleCounts[.standard] == 15)
        let insight = try #require(InsightSelector.focal(inputs))
        #expect(insight.kind == .focalGroup(buckets: [.wide], count: 40, denominator: 70, namesDenominator: false))
        #expect(InsightCopy.sentence(insight, locale: english) == "57% of your photos are at 20–34mm equivalent (Wide).")
        let filter = try #require(insight.filter)
        #expect(try LibraryQueries(database: database).count(matching: filter) == 40)
    }

    /// AC-4: X-T5 (APS-C) 300 photos at 23mm real / 35mm equivalent and 100
    /// at 33 / 50, plus 100 at 23mm from a camera with an unknown sensor. The
    /// sentence says 35mm, never 23mm, at 75% of 400 — and names that
    /// denominator, since 400 of 500 photos with a camera is under 90%.
    @Test func focalSentenceNamesEquivalentAndDenominator() throws {
        let database = try AppDatabase.makeEmpty()
        var rows = (0..<300).map { record("a\($0)", camera: "X-T5", lens: "XF23mmF1.4 R", focal: 23, equivalent: 35) }
        rows += (0..<100).map { record("b\($0)", camera: "X-T5", lens: "XF33mmF1.4 R", focal: 33, equivalent: 50) }
        rows += (0..<100).map { record("c\($0)", camera: "Mystery X1", focal: 23, equivalent: nil) }
        try save(rows, into: database)

        let inputs = try StatisticsQueries(database: database).insightInputs()
        #expect(inputs.photosWithCamera == 500)
        #expect(inputs.unknownSensorCount == 100)
        let insight = try #require(InsightSelector.focal(inputs))
        #expect(insight.kind == .focalValue(millimetres: 35, count: 300, denominator: 400, namesDenominator: true))
        let sentence = InsightCopy.sentence(insight, locale: english)
        #expect(sentence == "75% of your photos with a known equivalent focal length are at 35mm equivalent.")
        #expect(!sentence.contains("23mm"))
        // 20% unknown is under half: no unknown-sensor footer.
        guard case .insights(_, let footer) = InsightSelector.cardState(indexedRows: 500, inputs: inputs) else {
            Issue.record("expected sentences"); return
        }
        #expect(footer == nil)
    }

    /// AC-10: 200 photos with a real focal length, 180 from a camera whose
    /// sensor is unknown — no focal sentence, the footer instead.
    @Test func unknownSensorSuppressesFocalSentence() throws {
        let database = try AppDatabase.makeEmpty()
        var rows = (0..<180).map { record("u\($0)", camera: "Mystery X1", focal: 23, equivalent: nil) }
        rows += (0..<20).map { record("k\($0)", camera: "EOS R6", lens: "RF 50mm", focal: 50, equivalent: 50) }
        try save(rows, into: database)

        let inputs = try StatisticsQueries(database: database).insightInputs()
        #expect(inputs.actualFocalCount == 200)
        #expect(inputs.unknownSensorCount == 180)
        #expect(InsightSelector.focal(inputs) == nil)
        let state = InsightSelector.cardState(indexedRows: 200, inputs: inputs)
        guard case .insights(let sentences, let footer) = state else {
            Issue.record("expected the card, got \(state)"); return
        }
        #expect(!sentences.contains { if case .focalValue = $0.kind { true } else if case .focalGroup = $0.kind { true } else { false } })
        #expect(footer == 180)
        #expect(InsightCopy.unknownSensorFooter(180, locale: english)
            == "180 photos are from cameras with an unknown sensor size.")
    }

    /// The footer's tap: Settings opens at the Unknown Cameras row, once.
    @MainActor @Test func unknownCamerasFooterOpensSettingsAtTheRow() {
        let navigation = AppNavigation()
        navigation.openSettings(at: .unknownCameras)
        #expect(navigation.isSettingsSheetPresented)
        #expect(navigation.consumePendingSettingsRow() == .unknownCameras)
        #expect(navigation.consumePendingSettingsRow() == nil)
        #expect(SettingsSearchIndex.entry(for: .unknownCameras).section == .cameraDatabase)
    }

    /// AC-5: 380 iPhone 15 Pro main-module photos, 220 on its 9mm module, 400
    /// EOS R6 + RF 85mm. Each module is its own pair, so the EOS R6 leads at
    /// 40% — merged, the iPhone would have read 60%.
    @Test func pairSentenceKeepsPhoneModulesApart() throws {
        let database = try AppDatabase.makeEmpty()
        var rows = (0..<380).map {
            record("m\($0)", camera: "iPhone 15 Pro", lens: "iPhone 15 Pro back triple camera 6.765mm f/1.78", focal: 6.765, equivalent: 24)
        }
        rows += (0..<220).map {
            record("t\($0)", camera: "iPhone 15 Pro", lens: "iPhone 15 Pro back triple camera 9mm f/2.8", focal: 9, equivalent: 77)
        }
        rows += (0..<400).map {
            record("r\($0)", camera: "EOS R6", lens: "RF 85mm F1.2 L USM", focal: 85, equivalent: 85)
        }
        try save(rows, into: database)

        let inputs = try StatisticsQueries(database: database).insightInputs()
        let pair = try #require(InsightSelector.pair(inputs))
        #expect(InsightCopy.sentence(pair, locale: english) == "EOS R6 with RF 85mm F1.2 L USM took 40% of your photos.")
        let filter = try #require(pair.filter)
        #expect(filter.cameraBodies == ["EOS R6"])
        #expect(filter.lenses == ["RF 85mm F1.2 L USM"])
        #expect(try LibraryQueries(database: database).count(matching: filter) == 400)
        // In the card it is the second sentence, after focal length.
        let sentences = InsightSelector.select(inputs)
        #expect(sentences.map(\.kind).contains(pair.kind))
    }
}
