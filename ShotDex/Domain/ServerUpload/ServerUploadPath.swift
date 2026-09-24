import Foundation

/// Where a file lands on the server, and the names the upload writes on the
/// way there (FS-15.02 §3–§5).
enum ServerUploadPath {
    /// The suffix a file carries until its checksum has been read back and
    /// matched. Nothing under its real name is ever unverified.
    static let partSuffix = ".shotdex-part"

    /// `<folder>/<yyyy>/<yyyy-MM-dd>/<filename>`, the day in the device's
    /// time zone — the day the photographer remembers shooting.
    static func remotePath(
        folder: String,
        captureDate: Date,
        filename: String,
        timeZone: TimeZone = .current
    ) -> String {
        join(dayFolder(folder: folder, captureDate: captureDate, timeZone: timeZone), filename)
    }

    static func dayFolder(folder: String, captureDate: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: captureDate)
        let year = String(format: "%04d", parts.year ?? 0)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return join(join(normalizedFolder(folder), year), day)
    }

    /// The name the edited render goes up under: the original's base name,
    /// `_edited`, and the extension of the render itself (an edited RAW comes
    /// back from Photos as a JPEG or HEIC).
    static func editedFilename(original: String, rendered: String) -> String {
        let base = (original as NSString).deletingPathExtension
        let ext = (rendered as NSString).pathExtension
        return ext.isEmpty ? "\(base)_edited" : "\(base)_edited.\(ext)"
    }

    /// Keep Both: `IMG_1 (2).CR3`, then `(3)`, … — the first name `existing`
    /// does not hold. Compared case-insensitively, because SMB shares are.
    static func nextFreeName(for filename: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(filename.lowercased()) else { return filename }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            n += 1
        }
    }

    static func partPath(for path: String) -> String { path + partSuffix }

    static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    static func lastComponent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// No leading, trailing or doubled slashes: the folder field is typed by
    /// hand, and `/Photos/` and `Photos` are the same place.
    static func normalizedFolder(_ folder: String) -> String {
        folder.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    static func join(_ lhs: String, _ rhs: String) -> String {
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }
        return lhs + "/" + rhs
    }
}
