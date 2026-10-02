import Foundation
import ShotDexKit

/// Which file of a photo Edit opens (FS-03.04b §3). Every RAW+JPEG pair asks
/// first — *Edit which version?* — whether or not the decoder reads the RAW;
/// a RAW it can't read is offered dimmed, with the reason. Never remembered:
/// the next Edit asks again.
struct EditSourceChoice: Equatable, Sendable {
    /// The photo's own files, as PhotoKit lists them (`.photo` and
    /// `.alternatePhoto`), whichever order they come in.
    enum Resource: Equatable, Sendable { case raw, rendered }

    /// The photo has both a RAW and a JPEG/HEIC of its own.
    let isPair: Bool
    /// The decoder reads this camera's RAW on this iOS build.
    let rawIsReadable: Bool

    init(resources: [Resource], rawIsReadable: Bool) {
        isPair = resources.contains(.raw) && resources.contains(.rendered)
        self.rawIsReadable = rawIsReadable
    }

    /// Edit RAW is offered but dimmed when the decoder can't read it.
    var offersRAW: Bool { rawIsReadable }

    /// The line under the dimmed Edit RAW.
    var rawReason: String? {
        rawIsReadable ? nil : String(localized: "iOS can't read this RAW yet", comment: "Why Edit RAW is dimmed for a RAW + JPEG pair")
    }

    /// The edit the editor starts from when it opens `source` of a pair
    /// whose saved ShotDex edit was made on the other file (AC-16):
    /// - RAW → JPEG: the edit comes along, less the five settings only the
    ///   RAW decoder has (and an imported look's absolute white balance) — Q1;
    /// - JPEG → RAW: nothing comes along; the RAW opens as shot — Q9;
    /// - the same file: the saved edit as it is.
    static func startingRecipe(saved: PhotoEditRecipe?, opening source: PhotoEditSource) -> PhotoEditRecipe? {
        guard let saved else { return nil }
        let savedOnRAW = saved.source == .raw
            || (saved.source == .automatic && FileTypeBadge.isRAW(filename: saved.sourceFilename ?? ""))
        switch (savedOnRAW, source) {
        case (true, .rendered):
            var carried = saved
            for kind in PhotoAdjustmentKind.allCases where kind.isRAWOnly {
                carried.adjustments[kind] = 0
            }
            carried.adjustments.rawWhiteBalanceKelvin = nil
            carried.adjustments.rawWhiteBalanceTint = nil
            return carried
        case (false, .raw):
            return nil
        default:
            return saved
        }
    }

    var title: String {
        String(localized: "Edit which version?", comment: "Action sheet title: a photo has a RAW and a JPEG")
    }
}
