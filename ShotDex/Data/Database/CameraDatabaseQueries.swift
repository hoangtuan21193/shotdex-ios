import Foundation
import GRDB

/// Settings › Cameras (Mac, board `MAC_CameraDatabase`, FS-18.04 §3 AC-79):
/// every camera the index has seen, how many photos, its sensor format and
/// where that came from.
struct CameraDatabaseQueries: Sendable {
    let database: AppDatabase

    struct Camera: Identifiable, Equatable, Sendable {
        enum Origin: Equatable, Sendable { case builtIn, custom, unknown }

        let model: String
        let photoCount: Int
        let format: SensorFormat
        let cropFactor: Double?
        let origin: Origin

        var id: String { model }
    }

    enum Filter: String, CaseIterable, Sendable { case all, needsFormat, custom }

    /// Unknown first (what to fix), then by photo count. A camera's format is
    /// the one most of its photos carry, Unknown only when none has one; its
    /// crop factor comes with that format. A mapping with no photo indexed
    /// yet is listed too, so Reset can reach it.
    func cameras() throws -> [Camera] {
        try database.reader.read { db in
            let custom = Set(try String.fetchAll(db, sql: "SELECT normalizedCameraModel FROM custom_camera_mappings"))
            let rows = try Row.fetchAll(db, sql: """
                SELECT normalizedCameraModel AS model, sensorFormat AS format, cropFactor AS crop, COUNT(*) AS photos
                FROM photo_metadata WHERE normalizedCameraModel IS NOT NULL
                GROUP BY normalizedCameraModel, sensorFormat, cropFactor
                """)
            var byModel: [String: [(format: SensorFormat, crop: Double?, photos: Int)]] = [:]
            for row in rows {
                let format = (row["format"] as String?).flatMap(SensorFormat.init(rawValue:)) ?? .unknown
                byModel[row["model"], default: []].append((format, row["crop"], row["photos"]))
            }
            var cameras = byModel.map { model, groups -> Camera in
                let total = groups.reduce(0) { $0 + $1.photos }
                let known = groups.filter { $0.format != .unknown }.max { $0.photos < $1.photos }
                let origin: Camera.Origin = known == nil ? .unknown : custom.contains(model) ? .custom : .builtIn
                return Camera(model: model, photoCount: total, format: known?.format ?? .unknown, cropFactor: known?.crop, origin: origin)
            }
            let mappings = try CustomCameraMapping.fetchAll(db)
            for mapping in mappings where byModel[mapping.normalizedCameraModel] == nil {
                cameras.append(Camera(model: mapping.normalizedCameraModel, photoCount: 0,
                                      format: SensorFormat(rawValue: mapping.sensorFormat) ?? .unknown,
                                      cropFactor: mapping.cropFactor, origin: .custom))
            }
            return cameras.sorted { lhs, rhs in
                if (lhs.origin == .unknown) != (rhs.origin == .unknown) { return lhs.origin == .unknown }
                if lhs.photoCount != rhs.photoCount { return lhs.photoCount > rhs.photoCount }
                return lhs.model < rhs.model
            }
        }
    }

    static func filtered(_ cameras: [Camera], filter: Filter, search: String) -> [Camera] {
        cameras.filter { camera in
            switch filter {
            case .all: true
            case .needsFormat: camera.origin == .unknown
            case .custom: camera.origin == .custom
            }
        }
        .filter { search.isEmpty || $0.model.localizedCaseInsensitiveContains(search) }
    }
}
