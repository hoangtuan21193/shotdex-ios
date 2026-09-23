import Foundation

/// The order a focus bracket was shot in (FS-01.10 §4).
///
/// Alignment registers each frame to its neighbour, so neighbours have to be
/// neighbours in focus distance — and that is the order the camera took them
/// in, not the order they sit in the grid or were tapped. A camera's focus
/// bracketing fires several frames a second, so two frames often share a
/// capture second; the file name (DSC_0412, DSC_0413 …) breaks the tie.
enum FocusStackOrder {
    struct Frame<ID: Hashable>: Hashable {
        var id: ID
        var captureDate: Date?
        var fileName: String?
    }

    /// Frames sorted into shooting order. Frames with no date keep their
    /// relative order after the dated ones.
    static func sorted<ID: Hashable>(_ frames: [Frame<ID>]) -> [ID] {
        frames.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            switch (a.captureDate, b.captureDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if let x = a.fileName, let y = b.fileName, x != y {
                    return x.localizedStandardCompare(y) == .orderedAscending
                }
                return lhs.offset < rhs.offset
            }
        }.map(\.element.id)
    }
}
