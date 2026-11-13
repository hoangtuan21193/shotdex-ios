import CoreGraphics
import Foundation
import GRDB

/// One row of `duplicate_quality`: what the scoring pass measured on a
/// grouped photo, plus the EXIF it read on the way (FS-06.06 §5–§6). A scan
/// result — Clear Index drops it and the next scan measures again.
struct DuplicateQualityRecord: Equatable, Sendable {
    var assetId: String
    /// The photo's `modificationDate` when scored; a mismatch re-queues it.
    var modificationDate: Int?
    var score: DuplicateQualityScore
    var exposureBias: Double?
    var software: String?
    var scoredAt: Int
    /// Archived Vision feature print of the 512px rendition — what confirms
    /// a look-alike the hash only nominated. `nil` when it could not be read.
    var featurePrint: Data? = nil
}

struct DuplicateQualityStore: Sendable {
    let database: AppDatabase

    /// Scores of `assetIds` that have one, measured or not.
    func scores(for assetIds: some Collection<String>) throws -> [String: DuplicateQualityScore] {
        let ids = Array(Set(assetIds))
        guard !ids.isEmpty else { return [:] }
        return try database.reader.read { db in
            var result: [String: DuplicateQualityScore] = [:]
            for start in stride(from: 0, to: ids.count, by: 500) {
                let chunk = Array(ids[start..<min(start + 500, ids.count)])
                let rows = try Row.fetchCursor(db, sql: """
                    SELECT assetId, sharpness, eyesOpen, eyeConfidence, highlightClip, shadowClip, faceRect
                    FROM duplicate_quality WHERE assetId IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments(chunk))
                while let row = try rows.next() {
                    result[row["assetId"]] = DuplicateQualityScore(
                        sharpness: row["sharpness"],
                        eyesOpen: row["eyesOpen"],
                        eyeConfidence: row["eyeConfidence"],
                        highlightClip: row["highlightClip"] ?? 0,
                        shadowClip: row["shadowClip"] ?? 0,
                        faceRect: Self.rect(row["faceRect"])
                    )
                }
            }
            return result
        }
    }

    /// Grouped photos with no row, or a row from before the photo was last
    /// edited. Rows whose thumbnail could not be read (`sharpness IS NULL`)
    /// are retried only when the network is allowed this run.
    /// - Parameter retryingEmptyPrints: this device reads feature prints, so
    ///   a print stored empty (Vision refused, or a device that could not
    ///   read them) is asked for again.
    func pendingAssetIds(among assetIds: some Collection<String>, retryingFailed: Bool,
                         retryingEmptyPrints: Bool = false) throws -> [String] {
        let ids = Array(Set(assetIds))
        guard !ids.isEmpty else { return [] }
        return try database.reader.read { db in
            var pending: [String] = []
            for start in stride(from: 0, to: ids.count, by: 500) {
                let chunk = Array(ids[start..<min(start + 500, ids.count)])
                pending += try String.fetchAll(db, sql: """
                    SELECT p.assetId FROM photo_metadata p
                    LEFT JOIN duplicate_quality q ON q.assetId = p.assetId
                    WHERE p.assetId IN (\(databaseQuestionMarks(count: chunk.count)))
                      AND (q.assetId IS NULL OR q.modificationDate IS NOT p.modificationDate
                           OR (q.sharpness IS NULL AND ?)
                           OR (q.sharpness IS NOT NULL AND q.featurePrint IS NULL)
                           OR (q.sharpness IS NOT NULL AND length(q.featurePrint) = 0 AND ?))
                    ORDER BY p.creationDate DESC
                    """, arguments: StatementArguments(chunk) + [retryingFailed, retryingEmptyPrints])
            }
            return pending
        }
    }

    /// Archived feature prints of `assetIds` that have one.
    func featurePrints(for assetIds: some Collection<String>) throws -> [String: Data] {
        let ids = Array(Set(assetIds))
        guard !ids.isEmpty else { return [:] }
        return try database.reader.read { db in
            var result: [String: Data] = [:]
            for start in stride(from: 0, to: ids.count, by: 500) {
                let chunk = Array(ids[start..<min(start + 500, ids.count)])
                let rows = try Row.fetchCursor(db, sql: """
                    SELECT assetId, featurePrint FROM duplicate_quality
                    WHERE featurePrint IS NOT NULL AND assetId IN (\(databaseQuestionMarks(count: chunk.count)))
                    """, arguments: StatementArguments(chunk))
                while let row = try rows.next() {
                    if let data: Data = row["featurePrint"], !data.isEmpty { result[row["assetId"]] = data }
                }
            }
            return result
        }
    }

    func upsert(_ records: [DuplicateQualityRecord]) throws {
        guard !records.isEmpty else { return }
        try database.writer.write { db in
            for record in records {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO duplicate_quality
                        (assetId, modificationDate, sharpness, eyesOpen, eyeConfidence, highlightClip, shadowClip,
                         faceRect, exposureBias, software, scoredAt, featurePrint)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        record.assetId, record.modificationDate, record.score.sharpness, record.score.eyesOpen,
                        record.score.eyeConfidence, record.score.highlightClip, record.score.shadowClip,
                        record.score.faceRect.map(Self.text), record.exposureBias, record.software, record.scoredAt,
                        record.featurePrint,
                    ])
            }
        }
    }

    /// Rows of photos that left the index. A scan result, so a sweep against
    /// `photo_metadata` is safe here (unlike `duplicate_review`).
    @discardableResult
    func pruneOrphans() throws -> Int {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM duplicate_quality WHERE assetId NOT IN (SELECT assetId FROM photo_metadata)")
            return db.changesCount
        }
    }

    private static func text(_ rect: CGRect) -> String {
        [rect.minX, rect.minY, rect.width, rect.height].map { String(format: "%.4f", Double($0)) }.joined(separator: ",")
    }

    /// Lossy: an unreadable rectangle is no rectangle, not a failed read.
    private static func rect(_ text: String?) -> CGRect? {
        let parts = (text ?? "").split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }
}
