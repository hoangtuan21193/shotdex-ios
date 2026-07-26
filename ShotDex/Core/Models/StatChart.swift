import Foundation
import GRDB

/// A persisted dashboard chart: a `ChartSpec` plus its display `position`.
/// Stored in `stat_charts` with the spec JSON-encoded into the `config` text
/// column. As with `SmartAlbum`, we encode/decode that JSON *string* ourselves
/// rather than leaning on GRDB's implicit nested-Codable handling — GRDB would
/// otherwise hand the whole DB row to `ChartSpec.init(from:)`, which would
/// fail to find its keys and silently yield a broken spec.
struct StatChart: Codable, Identifiable, Equatable, Sendable {
    var spec: ChartSpec
    /// Display order (ascending). Reassigned on reorder.
    var position: Int

    var id: String { spec.id }

    init(spec: ChartSpec, position: Int) {
        self.spec = spec
        self.position = position
    }

    private enum CodingKeys: String, CodingKey {
        case id, config, position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedId = try container.decode(String.self, forKey: .id)
        position = try container.decode(Int.self, forKey: .position)
        let json = try container.decode(String.self, forKey: .config)
        if let decoded = try? JSONDecoder().decode(ChartSpec.self, from: Data(json.utf8)) {
            spec = decoded
        } else {
            // Corrupt config: fall back to a harmless placeholder keyed by the
            // stored id so the row still round-trips instead of crashing.
            spec = ChartSpec(id: storedId, title: "Chart", kind: .bar, dimension: .cameraBody)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spec.id, forKey: .id)
        try container.encode(position, forKey: .position)
        let data = try JSONEncoder().encode(spec)
        try container.encode(String(decoding: data, as: UTF8.self), forKey: .config)
    }
}

extension StatChart: FetchableRecord, PersistableRecord {
    static let databaseTableName = "stat_charts"
}
