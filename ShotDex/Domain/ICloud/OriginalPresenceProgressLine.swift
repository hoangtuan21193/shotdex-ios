import Foundation

/// The line under a smart album's conditions while the original-on-device
/// check runs (FS-06.10 §3): `Checking originals · 12,400 of 55,000`, or
/// `Originals checked 3 min ago` once a pass is through.
enum OriginalPresenceProgressLine {
    static func text(checked: Int, total: Int, finishedAt: Date?, now: Date = Date()) -> String {
        if checked >= total, let finishedAt {
            let ago = finishedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            return String(localized: "Originals checked \(ago)",
                          comment: "Original check: done, and when; e.g. Originals checked 3 min ago")
        }
        return String(localized: "Checking originals · \(checked.formatted()) of \(total.formatted())",
                      comment: "Original check: running; e.g. Checking originals · 12,400 of 55,000")
    }
}
