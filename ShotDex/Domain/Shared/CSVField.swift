import Foundation

/// One field of a CSV file the user opens in Numbers or Excel.
enum CSVField {
    /// RFC-4180 escaping: wrap in quotes when the field holds a comma, quote or
    /// newline, doubling any embedded quotes.
    static func escape(_ field: String) -> String {
        // By scalar: "\r\n" is one Character, equal to neither.
        guard field.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// One line of fields, escaped and joined.
    static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }
}
