import Foundation

/// Formats a chart's Y value for display, honoring the metric's field so an
/// aperture average reads "f/2.8", a file-size total "1.2 GB", etc.
enum ChartValueFormatter {
    static func string(_ value: Double, metric: ChartMetric) -> String {
        if metric.aggregation == .slowShutterShare {
            return (value / 100).formatted(.percent.precision(.fractionLength(0)))
        }
        guard metric.aggregation != .count, let field = metric.field else {
            return "\(Int(value.rounded()))"
        }
        switch field {
        case .iso: return "ISO \(Int(value.rounded()))"
        case .aperture: return MetadataFormatter.aperture(value) ?? Self.plain(value)
        case .shutter: return MetadataFormatter.shutterSpeed(value) ?? Self.plain(value)
        case .focalLength, .equivalentFocalLength: return MetadataFormatter.focalLength(value) ?? Self.plain(value)
        case .fileSize: return MetadataFormatter.fileSize(Int(value.rounded())) ?? Self.plain(value)
        case .megapixels: return MetadataFormatter.megapixels(value) ?? Self.plain(value)
        }
    }

    private static func plain(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
