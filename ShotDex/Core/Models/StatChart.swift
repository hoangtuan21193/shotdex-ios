import Foundation
import GRDB

/// A persisted dashboard chart: a `ChartWidget` plus its display `position`.
/// Stored in `stat_charts` with the widget JSON-encoded into the `config` text
/// column. As with `SmartAlbum`, we encode/decode that JSON *string* ourselves
/// rather than leaning on GRDB's implicit nested-Codable handling — GRDB would
/// otherwise hand the whole DB row to `ChartWidget.init(from:)`, which would
/// fail to find its keys and silently yield a broken widget.
struct StatChart: Codable, Identifiable, Equatable, Sendable {
    var widget: ChartWidget
    /// Display order (ascending). Reassigned on reorder.
    var position: Int

    var id: String { widget.id }

    init(widget: ChartWidget, position: Int) {
        self.widget = widget
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
        if let decoded = try? JSONDecoder().decode(ChartWidget.self, from: Data(json.utf8)) {
            widget = decoded
        } else {
            // Corrupt config: fall back to a harmless placeholder keyed by the
            // stored id so the row still round-trips instead of crashing.
            widget = ChartWidget(id: storedId, title: "Chart", kind: .bar, dimension: .cameraBody)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(widget.id, forKey: .id)
        try container.encode(position, forKey: .position)
        let data = try JSONEncoder().encode(widget)
        try container.encode(String(decoding: data, as: UTF8.self), forKey: .config)
    }
}

extension StatChart: FetchableRecord, PersistableRecord {
    static let databaseTableName = "stat_charts"
}
