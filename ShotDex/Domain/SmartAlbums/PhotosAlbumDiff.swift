import Foundation

/// What one Keep in Photos pass changes in the album (FS-06.12 §4): the
/// album becomes exactly the smart album's Photos items — the missing ones
/// added, every other one taken out, whoever put it there.
struct PhotosAlbumDiff: Equatable, Sendable {
    var add: [String]
    var remove: [String]

    /// No more than this many assets in one `performChanges` (§6).
    static let batchSize = 500

    /// `target` keeps its order (the smart album's), `current` is the album
    /// as Photos reports it.
    init(target: [String], current: [String]) {
        let have = Set(current)
        let want = Set(target)
        var seen = Set<String>()
        add = target.filter { !have.contains($0) && seen.insert($0).inserted }
        remove = current.filter { !want.contains($0) }
    }

    var isEmpty: Bool { add.isEmpty && remove.isEmpty }

    /// `ids` in runs of `batchSize`.
    static func batches(_ ids: [String], size: Int = batchSize) -> [[String]] {
        stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
    }
}
