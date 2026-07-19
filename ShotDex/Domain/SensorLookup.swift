import Foundation

/// One camera entry from the bundled sensor database.
struct SensorCameraRecord: Codable, Equatable, Sendable {
    var manufacturer: String
    var model: String
    var sensorFormat: String
    var cropFactor: Double
    var aliases: [String]?
}

/// Result of resolving a camera to a sensor format.
struct SensorInfo: Equatable, Sendable {
    var sensorFormat: SensorFormat
    var cropFactor: Double?

    static let unknown = SensorInfo(sensorFormat: .unknown, cropFactor: nil)
}

/// Resolves a normalized camera model to its sensor format and crop factor.
/// Custom user mappings take precedence over the bundled database.
/// Pure Swift — built once from the database records, then queried.
struct SensorLookup: Sendable {
    private let byKey: [String: SensorInfo]
    private let customByKey: [String: SensorInfo]

    init(records: [SensorCameraRecord], customMappings: [CustomCameraMapping] = []) {
        var byKey: [String: SensorInfo] = [:]
        for record in records {
            let info = SensorInfo(
                sensorFormat: SensorFormat(rawValue: record.sensorFormat) ?? .unknown,
                cropFactor: record.cropFactor
            )
            byKey[CameraNormalizer.lookupKey(record.model)] = info
            // Also match "manufacturer + model" in case normalization keeps the prefix.
            byKey[CameraNormalizer.lookupKey("\(record.manufacturer) \(record.model)")] = info
            for alias in record.aliases ?? [] {
                byKey[CameraNormalizer.lookupKey(alias)] = info
            }
        }
        self.byKey = byKey

        var customByKey: [String: SensorInfo] = [:]
        for mapping in customMappings {
            customByKey[CameraNormalizer.lookupKey(mapping.normalizedCameraModel)] = SensorInfo(
                sensorFormat: SensorFormat(rawValue: mapping.sensorFormat) ?? .unknown,
                cropFactor: mapping.cropFactor
            )
        }
        self.customByKey = customByKey
    }

    /// Looks up sensor info for a normalized camera model.
    func lookup(normalizedModel: String?) -> SensorInfo {
        guard let normalizedModel, !normalizedModel.isEmpty else { return .unknown }
        let key = CameraNormalizer.lookupKey(normalizedModel)
        return customByKey[key] ?? byKey[key] ?? .unknown
    }
}
