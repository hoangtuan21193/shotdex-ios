import Foundation

/// Adding photos to a Collage or a Video Studio project when some are RAWs
/// this iOS build can't read (FS-03.04b §4): ask once for the whole batch —
/// never fall back to the embedded preview silently.
struct UnsupportedRAWGate: Equatable, Sendable {
    /// The batch, in order.
    let ids: [String]
    /// Which of them the decoder can't read.
    let unreadable: [String]
    /// The smallest embedded preview among those, when it could be read
    /// without a download — what Convert to JPEG would give.
    let smallestPreview: PixelSize?

    init(ids: [String], unreadableSet: Set<String>, smallestPreview: PixelSize? = nil) {
        self.ids = ids
        self.unreadable = ids.filter { unreadableSet.contains($0) }
        self.smallestPreview = smallestPreview
    }

    /// Nothing to ask: every photo in the batch reads.
    var asks: Bool { !unreadable.isEmpty }

    enum Answer: Equatable, Sendable {
        /// Use each RAW's embedded preview at its own size; nothing is
        /// written to the library.
        case convertToJPEG
        /// Add the rest.
        case skip
        /// Add nothing.
        case cancel
    }

    /// What goes in, in order; nil for Cancel.
    func ids(after answer: Answer) -> [String]? {
        switch answer {
        case .convertToJPEG: ids
        case .skip: ids.filter { !unreadable.contains($0) }
        case .cancel: nil
        }
    }

    var title: String {
        unreadable.count == 1
            ? String(localized: "1 RAW photo can't be read on this iOS", comment: "Collage / Video Studio: one RAW iOS can't decode")
            : String(localized: "\(unreadable.count) RAW photos can't be read on this iOS", comment: "Collage / Video Studio: several RAWs iOS can't decode")
    }

    var message: String {
        let size = smallestPreview.map { " (\($0.width) × \($0.height))" } ?? ""
        return unreadable.count == 1
            ? String(localized: "Convert it to JPEG first? ShotDex uses the JPEG preview inside the RAW\(size).", comment: "Collage / Video Studio: what converting one unreadable RAW does; the preview's size in pixels follows")
            : String(localized: "Convert them to JPEG first? ShotDex uses the JPEG preview inside the RAW\(size).", comment: "Collage / Video Studio: what converting unreadable RAWs does; the smallest preview's size follows")
    }

    var convertTitle: String { String(localized: "Convert to JPEG", comment: "Use the RAW's embedded JPEG preview") }

    var skipTitle: String {
        String(localized: "Skip These \(unreadable.count)", comment: "Leave out the RAW photos iOS can't read")
    }
}
