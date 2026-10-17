import Photos
import SwiftUI

/// The Bursts tab's list (FS-06.06 §7b): every burst the app can see,
/// newest first, straight from PhotoKit. A row's frame and suggestion counts
/// load when it shows, never for the whole library at once (NF-01 rule 1).
@MainActor
@Observable
final class BurstListModel {
    enum Phase: Equatable { case loading, ready }

    private(set) var rows: [BurstSummary] = []
    private(set) var phase: Phase = .loading
    @ObservationIgnored private let library: any BurstLibrary
    @ObservationIgnored private var counting: Set<String> = []

    init(library: any BurstLibrary) {
        self.library = library
    }

    /// Bursts still listed — a burst left with one frame drops out.
    var listed: [BurstSummary] { rows.filter(\.isListed) }

    func reload() async {
        let fresh = BurstSummary.sorted(await library.bursts())
        // Keep counts already read for bursts that are still here, so a
        // library change does not blank every row; they are re-read below.
        let known = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        rows = fresh.map { row in
            var row = row
            row.frameCount = known[row.id]?.frameCount
            row.suggestedCount = known[row.id]?.suggestedCount
            return row
        }
        phase = .ready
        for row in rows where row.frameCount != nil {
            await count(row.id, force: true)
        }
    }

    /// Reads one row's counts the first time it shows.
    func count(_ id: String, force: Bool = false) async {
        guard force || rows.first(where: { $0.id == id })?.frameCount == nil, !counting.contains(id) else { return }
        counting.insert(id)
        defer { counting.remove(id) }
        let frames = await library.frames(ofBurst: id)
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].frameCount = frames.count
        rows[index].suggestedCount = frames.filter(\.isSuggested).count
    }

    func asset(for id: String) -> PHAsset? { library.asset(for: id) }
}
