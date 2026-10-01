import Foundation
import GRDB

extension StatisticsQueries {
    /// Everything the Insights card is chosen from (FS-07.02), grouped in SQL
    /// in one read: still photos only (`mediaType` = image), all time. Every
    /// query returns one row or a handful — the per-millimetre grouping is the
    /// longest, a few hundred rows at most.
    func insightInputs() throws -> InsightInputs {
        let image = MediaKind.photo.storedValue
        return try database.reader.read { db in
            var inputs = InsightInputs()

            inputs.photosWithCamera = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM photo_metadata
                WHERE mediaType = ? AND normalizedCameraModel IS NOT NULL AND normalizedCameraModel != ''
                """, arguments: [image]) ?? 0

            // Per rounded millimetre of the full-frame equivalent.
            for row in try Row.fetchAll(db, sql: """
                SELECT CAST(ROUND(equivalentFocalLength) AS INTEGER) AS mm, COUNT(*) AS count
                FROM photo_metadata
                WHERE mediaType = ? AND equivalentFocalLength IS NOT NULL AND equivalentFocalLength > 0
                GROUP BY mm
                """, arguments: [image]) {
                inputs.equivalentFocalCounts[row["mm"]] = row["count"]
            }

            // Per angle-of-view group, with the Library filter's own bounds
            // (>= lower, <= upper, as `LibraryQueries` writes a range) — so a
            // tapped group sentence and the grid count the same photos.
            let buckets = FocalAngleBucket.allCases
            var sums: [String] = []
            var bounds: [DatabaseValueConvertible] = []
            for bucket in buckets {
                var tests: [String] = []
                if let lower = bucket.range.lowerBound { tests.append("equivalentFocalLength >= ?"); bounds.append(lower) }
                if let upper = bucket.range.upperBound { tests.append("equivalentFocalLength <= ?"); bounds.append(upper) }
                sums.append("COALESCE(SUM(CASE WHEN \(tests.joined(separator: " AND ")) THEN 1 ELSE 0 END), 0)")
            }
            bounds.append(image)
            if let row = try Row.fetchOne(db, sql: """
                SELECT \(sums.joined(separator: ", "))
                FROM photo_metadata
                WHERE mediaType = ? AND equivalentFocalLength IS NOT NULL
                """, arguments: StatementArguments(bounds)) {
                for (index, bucket) in buckets.enumerated() {
                    inputs.focalAngleCounts[bucket] = row[index]
                }
            }

            // A real focal length, and how many of those have no equivalent.
            if let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS total,
                       COALESCE(SUM(CASE WHEN equivalentFocalLength IS NULL THEN 1 ELSE 0 END), 0) AS unknown
                FROM photo_metadata
                WHERE mediaType = ? AND focalLength IS NOT NULL AND focalLength > 0
                """, arguments: [image]) {
                inputs.actualFocalCount = row["total"]
                inputs.unknownSensorCount = row["unknown"]
            }

            // Body + lens: the top pairs (ties by name, a→z) and the total.
            let pairCondition = """
                mediaType = ? AND normalizedCameraModel IS NOT NULL AND normalizedCameraModel != ''
                AND normalizedLensModel IS NOT NULL AND normalizedLensModel != ''
                """
            inputs.topPairs = try Row.fetchAll(db, sql: """
                SELECT normalizedCameraModel AS body, normalizedLensModel AS lens, COUNT(*) AS count
                FROM photo_metadata
                WHERE \(pairCondition)
                GROUP BY normalizedCameraModel, normalizedLensModel
                ORDER BY count DESC, body, lens
                LIMIT 2
                """, arguments: [image]).map {
                InsightInputs.PairCount(body: $0["body"], lens: $0["lens"], count: $0["count"])
            }
            inputs.photosWithCameraAndLens = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM photo_metadata WHERE \(pairCondition)
                """, arguments: [image]) ?? 0

            // Slower than 1/equivalent focal length — the chart measure's rule.
            if let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS total,
                       COALESCE(SUM(CASE WHEN shutterSpeedSeconds > 1.0 / equivalentFocalLength THEN 1 ELSE 0 END), 0) AS slow
                FROM photo_metadata
                WHERE mediaType = ? AND \(MetricAggregation.slowShutterGuard)
                """, arguments: [image]) {
                inputs.shutterAndFocalCount = row["total"]
                inputs.slowShutterCount = row["slow"]
            }

            // Per calendar month in the device's local time (FS-07.01 §5).
            inputs.monthCounts = try Row.fetchAll(db, sql: """
                SELECT CAST(strftime('%Y', creationDate, 'unixepoch', 'localtime') AS INTEGER) AS year,
                       CAST(strftime('%m', creationDate, 'unixepoch', 'localtime') AS INTEGER) AS month,
                       COUNT(*) AS count
                FROM photo_metadata
                WHERE mediaType = ? AND creationDate IS NOT NULL
                GROUP BY year, month
                """, arguments: [image]).map {
                InsightInputs.MonthCount(year: $0["year"], month: $0["month"], count: $0["count"])
            }
            return inputs
        }
    }
}
