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
