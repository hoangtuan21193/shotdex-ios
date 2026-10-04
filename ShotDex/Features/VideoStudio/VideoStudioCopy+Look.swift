import Foundation

/// The Look panel's words (FS-12.06c), in the Video Studio's own table.
extension VideoStudioCopy {
    /// VoiceOver, after a clip with a look of its own: "Look Night Teal".
    static func lookNamed(_ name: String) -> String {
        String(localized: "Look \(name)", table: table, comment: "Video Studio: VoiceOver, after a timeline clip that has a look of its own — the look's name follows")
    }
}
