import Foundation

/// Loads the bundled `sensor_database.json`.
struct SensorDatabaseService: Sendable {
    struct SensorDatabaseFile: Codable {
        var version: Int
        var cameras: [SensorCameraRecord]
    }

    enum LoadError: Error {
        case fileNotFound
    }

    /// Decodes the camera records from a bundle (main bundle by default).
    func loadRecords(bundle: Bundle = .main) throws -> [SensorCameraRecord] {
        guard let url = bundle.url(forResource: "sensor_database", withExtension: "json") else {
            throw LoadError.fileNotFound
        }
        return try loadRecords(from: url)
    }

    func loadRecords(from url: URL) throws -> [SensorCameraRecord] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SensorDatabaseFile.self, from: data).cameras
    }
}
