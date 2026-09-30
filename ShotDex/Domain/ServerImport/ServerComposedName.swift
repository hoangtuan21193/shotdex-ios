import Foundation

/// The name of one file made from several photos — a collage, a combined
/// photo, a video — before the user edits it in the sheet (FS-17.06 §6b).
enum ServerComposedName {
    /// The tool that made the file, and the suffix it adds to the first
    /// photo's name.
    enum Tool: String, Sendable, CaseIterable {
        case collage
        case focusStack = "focus-stack"
        case panorama
        case stack
        case video

        var suffix: String { rawValue }

        /// What the sheet calls the file: `Collage · JPEG`.
        var title: String {
            switch self {
            case .collage: String(localized: "Collage", comment: "Server export: kind of the one file a tool made")
            case .focusStack: String(localized: "Focus Stack", comment: "Server export: kind of the one file a tool made")
            case .panorama: String(localized: "Panorama", comment: "Server export: kind of the one file a tool made")
            case .stack: String(localized: "Stacked Photo", comment: "Server export: kind of the one file a tool made")
            case .video: String(localized: "Video", comment: "Server export: kind of the one file a tool made")
            }
        }
    }

    /// `DSCF1000_collage` for a collage whose first photo is `DSCF1000.JPG`.
    static func defaultBase(firstFilename: String, tool: Tool) -> String {
        let base = (firstFilename as NSString).deletingPathExtension
        let cleaned = sanitized(base) ?? "ShotDex"
        return "\(cleaned)_\(tool.suffix)"
    }

    /// The typed name made safe for a server path: no separators, no leading
    /// dot that would hide the file, no surrounding space. Nil when nothing
    /// is left — the sheet then has nothing to export under.
    static func sanitized(_ raw: String) -> String? {
        var name = raw.filter { !"/:\\".contains($0) }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return String(name.prefix(200))
    }

    /// The name with the file's own extension, or nil when the typed name
    /// leaves nothing.
    static func filename(typed: String, fileExtension: String) -> String? {
        sanitized(typed).map { fileExtension.isEmpty ? $0 : "\($0).\(fileExtension)" }
    }
}
