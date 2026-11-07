#if DEBUG
import Foundation

/// `-ShotDexDemoLibrary -ShotDexSection ingest` (board `MAC_Ingest`): a
/// memory card that is a folder in the app's temporary folder — landscape
/// desktop pictures (no faces) as `IMG_58xx.HIF`, dated over three days —
/// and a folder source "T7 RAW Archive" beside it to import into. Both are
/// made fresh each launch, as the demo database is.
enum MacDemoCard {
    static let cardName = "EOS_DIGITAL"
    static let destinationName = "T7 RAW Archive"

    private static let pictures = ["Big Sur Coastline", "Big Sur Mountains", "Big Sur Road", "Catalina Coast",
                                   "Big Sur Waters Edge", "Catalina Clouds", "Big Sur Horizon", "Big Sur Shore Rocks"]
    private static let largePictures = ["Mac Blue", "Mac Pink", "Mac Purple"]
    /// (month, day, photos): a short day, a full one, a later one.
    private static let days: [(month: Int, day: Int, count: Int)] = [(9, 27, 3), (9, 28, 12), (10, 2, 8)]

    /// The card's id, once it is remembered and its destination added.
    @MainActor
    static func seed(_ dependencies: MacDependencies) async -> String? {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexDemoCard", isDirectory: true)
        let card = base.appendingPathComponent(cardName, isDirectory: true)
        let destination = base.appendingPathComponent(destinationName, isDirectory: true)
        await Task.detached { make(card: card, destination: destination) }.value
        await dependencies.sourcesModel.addFolder(destination, includesSubfolders: true, pairsRawAndJpeg: true)
        guard let remembered = try? dependencies.cards.store.remember(card) else { return nil }
        dependencies.cards.refresh()
        return remembered.id
    }

    private static func make(card: URL, destination: URL) {
        let files = FileManager.default
        try? files.removeItem(at: card)
        try? files.removeItem(at: destination)
        let folder = card.appendingPathComponent("DCIM/100CANON", isDirectory: true)
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        try? files.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails", isDirectory: true)
        var number = 5880
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for (month, day, count) in days {
            for index in 0..<count {
                let target = folder.appendingPathComponent("IMG_\(number).HIF")
                // The last day is full-size pictures (~9 MB, nine chunks): with
                // `-ShotDexSlowIngest` a run over it lasts long enough to stop.
                let picture = month == 10
                    ? URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)
                        .appendingPathComponent(largePictures[index % largePictures.count] + ".heic")
                    : source.appendingPathComponent(pictures[number % pictures.count] + ".heic")
                try? files.copyItem(at: picture, to: target)
                let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9, minute: index * 3))
                try? files.setAttributes([.modificationDate: date as Any], ofItemAtPath: target.path)
                number += 1
            }
        }
    }
}
#endif
