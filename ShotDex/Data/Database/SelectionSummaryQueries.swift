import Foundation
import GRDB

/// What a selection of photos holds, for the Mac inspector's summary
/// (board `MAC_LibrarySelected`, FS-18.02 §8): dates, size, formats, where
/// they live, gear, exposure ranges, keywords and marks. One read per 900
/// ids, folded here — a select-all of 55k is a few hundred milliseconds off
/// the main actor.
struct SelectionSummaryQueries: Sendable {
    let database: AppDatabase

    struct Count: Equatable, Sendable {
        let name: String
        let count: Int
    }

    struct SourceCount: Equatable, Sendable {
        let name: String
        let kind: String
        let count: Int
    }

    struct Summary: Equatable, Sendable {
        var count = 0
        var videoCount = 0
        var firstDate: Date?
        var lastDate: Date?
        var totalBytes: Int64 = 0
        /// RAW, HEIC, JPG…, most first.
        var formats: [Count] = []
        /// By the source a photo was first added from, most first.
        var sources: [SourceCount] = []
        var cameras: [Count] = []
        var lenses: [Count] = []
        var iso: ClosedRange<Int>?
        var focalLength: ClosedRange<Double>?
        var aperture: ClosedRange<Double>?
        /// Seconds.
        var shutter: ClosedRange<Double>?
        /// Every keyword with how many of the photos carry it, most first.
        var keywords: [Count] = []
        /// The stars the app shows (a pending change, a file's own, Photos').
        var ratings: ClosedRange<Int>?
        var picks = 0
        var rejects = 0
        var favorites = 0
    }

    /// One read per 900 ids, so a select-all left behind (the user clicked
    /// one photo) stops between reads instead of holding a reader to the end.
    func summary(ids: [String]) async throws -> Summary {
        var tally = Tally()
        for start in stride(from: 0, to: ids.count, by: 900) {
            try Task.checkCancellation()
            let chunk = Array(ids[start..<min(ids.count, start + 900)])
            let part = try await database.reader.read { db in try Tally.read(db, chunk) }
            tally.merge(part)
        }
        return tally.finished()
    }

    static func summary(_ db: Database, ids: [String]) throws -> Summary {
        var tally = Tally()
        for start in stride(from: 0, to: ids.count, by: 900) {
            tally.merge(try Tally.read(db, Array(ids[start..<min(ids.count, start + 900)])))
        }
        return tally.finished()
    }

    /// The counts of some photos, merged chunk by chunk (chunks are disjoint).
    private struct Tally: Sendable {
        var summary = Summary()
        var formats: [String: Int] = [:], cameras: [String: Int] = [:], lenses: [String: Int] = [:]
        // By source id: two drives may share a name.
        var sources: [String: (name: String, kind: String, count: Int)] = [:]
        /// By `caseKey`: photos carrying it, and how many use each spelling.
        var keywords: [String: (count: Int, spellings: [String: Int])] = [:]

        static func widen<T: Comparable>(_ range: inout ClosedRange<T>?, _ value: T?) {
            guard let value else { return }
            range = range.map { min($0.lowerBound, value)...max($0.upperBound, value) } ?? value...value
        }

        static func widen<T: Comparable>(_ range: inout ClosedRange<T>?, _ other: ClosedRange<T>?) {
            guard let other else { return }
            widen(&range, other.lowerBound)
            widen(&range, other.upperBound)
        }

        mutating func merge(_ other: Tally) {
            summary.count += other.summary.count
            summary.videoCount += other.summary.videoCount
            if let date = other.summary.firstDate { summary.firstDate = min(summary.firstDate ?? date, date) }
            if let date = other.summary.lastDate { summary.lastDate = max(summary.lastDate ?? date, date) }
            summary.totalBytes += other.summary.totalBytes
            Self.widen(&summary.iso, other.summary.iso)
            Self.widen(&summary.focalLength, other.summary.focalLength)
            Self.widen(&summary.aperture, other.summary.aperture)
            Self.widen(&summary.shutter, other.summary.shutter)
            Self.widen(&summary.ratings, other.summary.ratings)
            summary.picks += other.summary.picks
            summary.rejects += other.summary.rejects
            summary.favorites += other.summary.favorites
            formats.merge(other.formats, uniquingKeysWith: +)
            cameras.merge(other.cameras, uniquingKeysWith: +)
            lenses.merge(other.lenses, uniquingKeysWith: +)
            sources.merge(other.sources) { ($0.name, $0.kind, $0.count + $1.count) }
            keywords.merge(other.keywords) { ($0.count + $1.count, $0.spellings.merging($1.spellings, uniquingKeysWith: +)) }
        }

        static func read(_ db: Database, _ chunk: [String]) throws -> Tally {
            var tally = Tally()
            let marks = databaseQuestionMarks(count: chunk.count)
            let rows = try Row.fetchCursor(db, sql: """
                WITH firstCopy AS (
                    SELECT c.photoId, s.id, s.name, s.kind,
                           ROW_NUMBER() OVER (PARTITION BY c.photoId ORDER BY s.createdAt, s.id) AS place
                    FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                    WHERE c.missingSince IS NULL AND c.photoId IN (\(marks))
                )
                SELECT m.mediaType, m.creationDate, m.fileSize, m.originalFilename,
                       COALESCE(m.normalizedCameraModel, m.cameraModel),
                       COALESCE(m.normalizedLensModel, m.lensModel),
                       m.iso, m.focalLength, m.aperture, m.shutterSpeedSeconds,
                       COALESCE(p.rating, u.rating, m.rating, 0),
                       f.flag, (m.isFavorite = 1 OR u.isFavorite = 1),
                       c.id, c.name, c.kind
                FROM photo_metadata m
                LEFT JOIN pending_photo_rating p ON p.assetId = m.assetId
                LEFT JOIN photo_user_marks u ON u.photoId = m.assetId
                LEFT JOIN photo_flag f ON f.assetId = m.assetId
                LEFT JOIN firstCopy c ON c.photoId = m.assetId AND c.place = 1
                WHERE m.assetId IN (\(marks))
                """, arguments: StatementArguments(chunk + chunk))
            while let row = try rows.next() {
                tally.summary.count += 1
                if row[0] as Int == 2 { tally.summary.videoCount += 1 }
                if let seconds: Int = row[1] {
                    let date = Date(timeIntervalSince1970: TimeInterval(seconds))
                    tally.summary.firstDate = min(tally.summary.firstDate ?? date, date)
                    tally.summary.lastDate = max(tally.summary.lastDate ?? date, date)
                }
                tally.summary.totalBytes += Int64(row[2] as Int? ?? 0)
                let filename: String? = row[3]
                if let format = filename.flatMap({ FileTypeBadge.text(forExtension: ($0 as NSString).pathExtension) }) {
                    tally.formats[format, default: 0] += 1
                }
                if let camera: String = row[4], !camera.isEmpty { tally.cameras[camera, default: 0] += 1 }
                if let lens: String = row[5], !lens.isEmpty { tally.lenses[lens, default: 0] += 1 }
                Self.widen(&tally.summary.iso, row[6] as Int?)
                Self.widen(&tally.summary.focalLength, row[7] as Double?)
                Self.widen(&tally.summary.aperture, row[8] as Double?)
                Self.widen(&tally.summary.shutter, row[9] as Double?)
                Self.widen(&tally.summary.ratings, row[10] as Int?)
                switch row[11] as String? {
                case PhotoFlag.pick.rawValue: tally.summary.picks += 1
                case PhotoFlag.reject.rawValue: tally.summary.rejects += 1
                default: break
                }
                if row[12] as Bool? == true { tally.summary.favorites += 1 }
                if let sourceId: String = row[13] {
                    tally.sources[sourceId, default: (row[14] as String? ?? "", row[15] as String? ?? "", 0)].count += 1
                }
            }
            // One chip per case (as `KeywordInput.caseKey` matches a remove),
            // named by the spelling most of these photos use.
            let words = try Row.fetchCursor(db, sql: """
                SELECT caseKey, keyword, COUNT(DISTINCT assetId) FROM (\(PhotoKeywordStore.everyKeywordSQL))
                WHERE assetId IN (\(marks)) GROUP BY caseKey, keyword
                """, arguments: StatementArguments(chunk))
            while let row = try words.next() {
                tally.keywords[row[0], default: (0, [:])].spellings[row[1], default: 0] += row[2] as Int
            }
            let photos = try Row.fetchCursor(db, sql: """
                SELECT caseKey, COUNT(DISTINCT assetId) FROM (\(PhotoKeywordStore.everyKeywordSQL))
                WHERE assetId IN (\(marks)) GROUP BY caseKey
                """, arguments: StatementArguments(chunk))
            while let row = try photos.next() {
                tally.keywords[row[0], default: (0, [:])].count += row[1] as Int
            }
            return tally
        }

        func finished() -> Summary {
            var summary = summary
            func sorted(_ counts: [String: Int]) -> [Count] {
                counts.map { Count(name: $0.key, count: $0.value) }
                    .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            summary.formats = sorted(formats)
            summary.cameras = sorted(cameras)
            summary.lenses = sorted(lenses)
            summary.keywords = keywords.values.map { entry in
                let name = entry.spellings.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? ""
                return Count(name: name, count: entry.count)
            }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            summary.sources = sources.values.map { SourceCount(name: $0.name, kind: $0.kind, count: $0.count) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            return summary
        }
    }
}
