import Foundation

/// Builds a CSV of the indexed EXIF metadata for a set of photos and writes it to
/// a temporary file for sharing. Videos carry no metadata row (the index is
/// image-only), so the caller passes the resolved `PhotoMetadata` rows and the
/// exporter simply lays out one line per row in the order given (pick order).
enum ExifCSVExporter {
    /// Column headers, in output order.
    private static let headers = [
        "Filename", "Date", "Camera Make", "Camera Model", "Lens",
        "Focal Length (mm)", "Equivalent Focal (mm)", "Aperture", "Shutter",
        "ISO", "Width", "Height", "Megapixels", "File Size (MB)",
        "Sensor Format", "Latitude", "Longitude", "Favorite",
    ]

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// The full CSV text for the given rows (header line + one line per row).
    static func makeCSV(_ rows: [PhotoMetadata]) -> String {
        var lines = [headers.map(escape).joined(separator: ",")]
        for row in rows {
            lines.append(fields(for: row).map(escape).joined(separator: ","))
        }
        // Trailing newline so appenders and `wc -l` agree on the row count.
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the CSV to a uniquely-named temporary file and returns its URL.
    /// The name is stable per export (`ShotDex EXIF.csv`) so the share sheet and
    /// receiving apps show a friendly filename; a per-export subfolder keeps
    /// concurrent exports from colliding.
    static func writeTemporaryFile(_ rows: [PhotoMetadata]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotdex-exif-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ShotDex EXIF.csv")
        try makeCSV(rows).data(using: .utf8)?.write(to: url)
        return url
    }

    private static func fields(for row: PhotoMetadata) -> [String] {
        // Built with typed locals and appends rather than one big literal: the
        // mixed `Optional.map { … } ?? ""` chain in a single array literal blows
        // past the Swift type-checker's time budget.
        var out: [String] = []
        out.append(row.originalFilename ?? "")
        if let date = row.creationDateValue { out.append(dateFormatter.string(from: date)) } else { out.append("") }
        out.append(row.cameraManufacturer ?? "")
        out.append(row.cameraModel ?? "")
        out.append(row.lensModel ?? "")
        out.append(optionalNumber(row.focalLength))
        out.append(optionalNumber(row.equivalentFocalLength))
        if let aperture = row.aperture { out.append("f/" + trim(aperture)) } else { out.append("") }
        out.append(shutter(for: row))
        if let iso = row.iso { out.append(String(iso)) } else { out.append("") }
        if let width = row.width { out.append(String(width)) } else { out.append("") }
        if let height = row.height { out.append(String(height)) } else { out.append("") }
        if let mp = row.megapixels { out.append(String(format: "%.1f", mp)) } else { out.append("") }
        if let bytes = row.fileSize { out.append(String(format: "%.1f", Double(bytes) / 1_048_576)) } else { out.append("") }
        out.append(row.resolvedSensorFormat == .unknown ? "" : row.resolvedSensorFormat.rawValue)
        if let latitude = row.latitude { out.append(String(latitude)) } else { out.append("") }
        if let longitude = row.longitude { out.append(String(longitude)) } else { out.append("") }
        out.append(row.isFavorite ? "Yes" : "No")
        return out
    }

    private static func optionalNumber(_ value: Double?) -> String {
        value.map(trim) ?? ""
    }

    private static func shutter(for row: PhotoMetadata) -> String {
        if let display = row.shutterSpeedDisplay { return display }
        if let seconds = row.shutterSpeedSeconds { return trim(seconds) + "s" }
        return ""
    }

    /// Drops a trailing ".0" so whole numbers print as "85", not "85.0".
    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// RFC-4180 escaping: wrap in quotes when the field holds a comma, quote or
    /// newline, doubling any embedded quotes.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
