import Foundation
import GRDB

/// The decoder verdicts of FS-03.04b §5: one row per camera × iOS build.
struct RAWVerdictStore: Sendable {
    let database: AppDatabase

    /// A camera with RAW-only photos in the index, as EXIF and the index
    /// name it.
    struct IndexedCamera: Hashable, Sendable {
        let camera: RAWCamera
        let exifMake: String?
        let exifModel: String?
    }

    /// `originalFilename` ends in one of the RAW extensions — the same
    /// table as the tile's badge (FS-03.04b §2).
    static let rawFilenameSQL: String = {
        let ors = FileTypeBadge.rawExtensions.sorted().map { "originalFilename LIKE '%.\($0)' COLLATE NOCASE" }
        return "(" + ors.joined(separator: " OR ") + ")"
    }()

    /// The index's camera as the verdict table's key (`RAWCamera.key`).
    static let cameraKeySQL = "COALESCE(normalizedCameraManufacturer, '') || '|' || normalizedCameraModel"

    /// The Unsupported RAW filter's test (AC-13): the same rows as
    /// `unreadableAssetIds`, as a condition on `photo_metadata`. The build
    /// is the system's ("23F77"), kept to letters and digits before it goes
    /// in.
    static func unreadableSQL(build: String) -> String {
        let safe = String(build.filter { $0.isLetter || $0.isNumber || $0 == "." })
        return """
            (normalizedCameraModel IS NOT NULL AND \(rawFilenameSQL) \
            AND \(cameraKeySQL) IN (SELECT camera FROM raw_decoder_verdicts \
            WHERE osBuild = '\(safe)' AND verdict = 'unreadable') \
            AND assetId NOT IN (SELECT assetId FROM raw_pair_assets))
            """
    }

    func verdict(for camera: RAWCamera, build: String) throws -> RAWDecoderVerdict? {
        try database.reader.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT verdict FROM raw_decoder_verdicts WHERE camera = ? AND osBuild = ?",
                arguments: [camera.key, build]
            ).flatMap(RAWDecoderVerdict.init(rawValue:))
        }
    }

    /// Every verdict for this build, by camera key.
    func verdicts(build: String) throws -> [String: RAWDecoderVerdict] {
        try database.reader.read { db in
            let rows = try Row.fetchAll(
                db, sql: "SELECT camera, verdict FROM raw_decoder_verdicts WHERE osBuild = ?", arguments: [build]
            )
            var result: [String: RAWDecoderVerdict] = [:]
            for row in rows {
                if let verdict = RAWDecoderVerdict(rawValue: row["verdict"]) { result[row["camera"]] = verdict }
            }
            return result
        }
    }

    func record(
        _ verdict: RAWDecoderVerdict,
        source: RAWVerdictSource?,
        for camera: RAWCamera,
        build: String,
        at date: Date = Date()
    ) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO raw_decoder_verdicts (camera, osBuild, verdict, source, judgedAt)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(camera, osBuild) DO UPDATE SET
                    verdict = excluded.verdict, source = excluded.source, judgedAt = excluded.judgedAt
                """,
                arguments: [camera.key, build, verdict.rawValue, source?.rawValue, Int(date.timeIntervalSince1970)]
            )
        }
    }

    /// The camera's photos whose indexed file is a RAW, newest first, less
    /// those known to carry a rendered twin.
    func rawAssetIds(of camera: RAWCamera) throws -> [String] {
        try database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT assetId FROM photo_metadata
                WHERE \(Self.cameraKeySQL) = ? AND \(Self.rawFilenameSQL)
                  AND assetId NOT IN (SELECT assetId FROM raw_pair_assets)
                ORDER BY creationDate DESC
                """, arguments: [camera.key])
        }
    }

    /// RAW-named photos of cameras this build can't read, less pairs: the
    /// tiles that carry the glyph and what Unsupported RAW shows (AC-2,
    /// AC-13). Unknown cameras are not in it.
    func unreadableAssetIds(build: String) throws -> Set<String> {
        try database.reader.read { db in
            Set(try String.fetchAll(db, sql: """
                SELECT assetId FROM photo_metadata WHERE \(Self.unreadableSQL(build: build))
                """))
        }
    }

    /// The indexed camera and file name of one photo — what the message
    /// names before anything is downloaded (AC-3, AC-4).
    func cameraAndFilename(of assetId: String) throws -> (camera: RAWCamera?, filename: String?) {
        try database.reader.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT normalizedCameraManufacturer AS make, normalizedCameraModel AS model, originalFilename
                FROM photo_metadata WHERE assetId = ?
                """, arguments: [assetId]) else { return (nil, nil) }
            return (RAWCamera(manufacturer: row["make"], model: row["model"]), row["originalFilename"])
        }
    }

    /// Records RAW-named photos found to carry a rendered twin. Returns how
    /// many were new.
    @discardableResult
    func addPairs(_ assetIds: Set<String>) throws -> Int {
        guard !assetIds.isEmpty else { return 0 }
        return try database.writer.write { db in
            var added = 0
            for id in assetIds {
                try db.execute(sql: "INSERT OR IGNORE INTO raw_pair_assets (assetId) VALUES (?)", arguments: [id])
                added += db.changesCount
            }
            return added
        }
    }

    /// Cameras with photos whose indexed file is a RAW; a row with no model
    /// has no camera to judge (AC-6).
    func indexedRAWCameras() throws -> [IndexedCamera] {
        try database.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT normalizedCameraManufacturer AS make, normalizedCameraModel AS model,
                       MIN(cameraManufacturer) AS exifMake, MIN(cameraModel) AS exifModel
                FROM photo_metadata
                WHERE normalizedCameraModel IS NOT NULL AND \(Self.rawFilenameSQL)
                GROUP BY normalizedCameraManufacturer, normalizedCameraModel
                """)
            return rows.compactMap { row in
                RAWCamera(manufacturer: row["make"], model: row["model"]).map {
                    IndexedCamera(camera: $0, exifMake: row["exifMake"], exifModel: row["exifModel"])
                }
            }
        }
    }
}
