import Foundation

/// One hashed photo as the duplicate finder sees it: the hash plus the facts
/// that order members inside a group (larger and favourited first).
struct HashedPhoto: Hashable, Sendable, Identifiable {
    var assetId: String
    var hash: PerceptualHash
    var width: Int?
    var height: Int?
    var fileSize: Int?
    var creationDate: Int?
    var isFavorite: Bool

    var id: String { assetId }

    var pixelCount: Int {
        guard let width, let height else { return 0 }
        return width * height
    }
}

/// What the Duplicates screen is looking for.
///
/// The first two are thresholds on the same question — how alike are these two
/// pictures. `series` asks a different one, and answers it with time as well as
/// likeness, so it is not simply a third notch on the same dial.
enum DuplicateStrictness: String, CaseIterable, Sendable, Identifiable {
    /// Same hash and same pixel dimensions — byte-for-byte copies and
    /// re-saves of the same frame.
    case exact
    /// Hashes within `similarMaxDistance` bits — resizes, re-exports, crops
    /// of a few percent, burst neighbours.
    case similar
    /// A run of frames of one moment: shot close together in time, of a scene
    /// that stayed recognisably the same. The pictures are *not* copies of each
    /// other — the point is the pose that changed between them — so this mode
    /// finds what the other two are built to ignore.
    case series

    var id: String { rawValue }

    /// Picker label. Driven off `allCases`, so a mode added here cannot be
    /// forgotten in the segmented control.
    var title: String {
        switch self {
        case .exact: "Exact"
        case .similar: "Similar"
        case .series: "Series"
        }
    }

    /// Largest Hamming distance still treated as "the same picture" in the
    /// `similar` mode. 10 of 64 bits is the usual dHash working threshold:
    /// well under the ~32 two unrelated pictures average, above the 2–6 a
    /// JPEG re-encode or a modest resize costs.
    static let similarMaxDistance = 10

    /// Seconds allowed between one frame and the next before the run is over.
    /// 30 covers the pause where somebody changes pose or the photographer
    /// says something, without letting a whole afternoon in one place collapse
    /// into a single group.
    static let seriesMaxGap = 30

    /// How far apart two *consecutive* frames of a series may be. Looser than
    /// `similarMaxDistance` on purpose: the subject is supposed to have moved.
    /// 20 of 64 bits still sits well below the ~32 two unrelated pictures
    /// average, and the 30-second gap is doing most of the work anyway.
    static let seriesMaxDistance = 20

    /// Two frames 20 seconds apart is an ordinary thing to shoot; listing every
    /// such pair would bury the runs that are actually a series.
    static let seriesMinCount = 3

    var maxDistance: Int {
        switch self {
        case .exact: 0
        case .similar: Self.similarMaxDistance
        case .series: Self.seriesMaxDistance
        }
    }

    var minimumGroupSize: Int {
        self == .series ? Self.seriesMinCount : 2
    }
}

/// A set of photos judged to be the same picture, best candidate to keep first.
struct DuplicateGroup: Identifiable, Equatable, Sendable {
    /// Stable across regroups as long as the same best member leads the group.
    var id: String { members[0].assetId }
    var members: [HashedPhoto]

    var count: Int { members.count }

    /// Bytes freed by keeping only the largest member.
    var reclaimableBytes: Int {
        let sizes = members.compactMap(\.fileSize)
        guard let largest = sizes.max() else { return 0 }
        return sizes.reduce(0, +) - largest
    }
}

/// Pure grouping of hashed photos into duplicate sets.
///
/// Identical hashes are merged first (a dictionary pass), and the near-match
/// search then runs over the *distinct* hashes only — so a thousand blank
/// screenshots sharing one hash cost one representative, not a million pair
/// checks. Near matches are found with byte buckets: two 64-bit hashes within
/// 10 bits of each other must agree to within 1 bit on at least one of their
/// 8 bytes (pigeonhole), so each hash probes its 8 bytes × 9 one-bit variants
/// and verifies the full distance only on those candidates. Groups are the
/// connected components of the match graph (union-find).
enum DuplicateGrouper {
    static func groups(from photos: [HashedPhoto], strictness: DuplicateStrictness) -> [DuplicateGroup] {
        guard photos.count > 1 else { return [] }
        if strictness == .series { return seriesGroups(from: photos) }

        var parent = Array(0..<photos.count)
        func find(_ index: Int) -> Int {
            var root = index
            while parent[root] != root { root = parent[root] }
            var current = index
            while parent[current] != root {
                let next = parent[current]
                parent[current] = root
                current = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let rootA = find(a), rootB = find(b)
            if rootA != rootB { parent[max(rootA, rootB)] = min(rootA, rootB) }
        }

        // Pass 1 — identical hashes. In exact mode the dimensions are part of
        // the key so a 2000px re-export never merges with its 6000px original.
        struct ExactKey: Hashable {
            var bits: UInt64
            var width: Int?
            var height: Int?
        }
        var representativeByHash: [UInt64: Int] = [:]
        var firstByExactKey: [ExactKey: Int] = [:]
        for (index, photo) in photos.enumerated() {
            // `.series` never reaches this pass — it returned above.
            let key = switch strictness {
            case .exact: ExactKey(bits: photo.hash.bits, width: photo.width, height: photo.height)
            case .similar, .series: ExactKey(bits: photo.hash.bits, width: nil, height: nil)
            }
            if let first = firstByExactKey[key] {
                union(first, index)
            } else {
                firstByExactKey[key] = index
            }
            if representativeByHash[photo.hash.bits] == nil {
                representativeByHash[photo.hash.bits] = index
            }
        }

        // Pass 2 — near matches between distinct hashes.
        if strictness.maxDistance > 0 {
            let representatives = representativeByHash.sorted { $0.value < $1.value }
            var buckets: [BucketKey: [Int]] = [:]
            for (position, entry) in representatives.enumerated() {
                for byteIndex in 0..<8 {
                    let byte = UInt8(truncatingIfNeeded: entry.key >> UInt64(byteIndex * 8))
                    buckets[BucketKey(byteIndex: byteIndex, value: byte), default: []].append(position)
                }
            }
            for (position, entry) in representatives.enumerated() {
                var seen = Set<Int>()
                for byteIndex in 0..<8 {
                    let byte = UInt8(truncatingIfNeeded: entry.key >> UInt64(byteIndex * 8))
                    for variant in oneBitVariants(of: byte) {
                        guard let candidates = buckets[BucketKey(byteIndex: byteIndex, value: variant)] else { continue }
                        for candidate in candidates where candidate > position && !seen.contains(candidate) {
                            seen.insert(candidate)
                            let other = representatives[candidate]
                            if (entry.key ^ other.key).nonzeroBitCount <= strictness.maxDistance {
                                union(entry.value, other.value)
                            }
                        }
                    }
                }
            }
        }

        var membersByRoot: [Int: [HashedPhoto]] = [:]
        for index in photos.indices {
            membersByRoot[find(index), default: []].append(photos[index])
        }
        return assemble(Array(membersByRoot.values), strictness: strictness)
    }

    /// Runs of frames of one moment, in the order they were taken.
    ///
    /// Sorted by capture time and cut wherever the next frame is too late or
    /// too different from **the one before it**. Chaining neighbour to
    /// neighbour rather than everything to a group representative is what lets
    /// a series drift: the first pose and the last may share very little, and
    /// they still belong to the same run as long as every step between them was
    /// small. That is also why this cannot reuse the union-find pass above,
    /// which would happily join two runs that merely look alike hours apart.
    ///
    /// A photo with no capture date is left out rather than guessed at — with
    /// no time there is nothing to chain it to.
    static func seriesGroups(from photos: [HashedPhoto]) -> [DuplicateGroup] {
        let timed = photos
            .filter { $0.creationDate != nil }
            .sorted { lhs, rhs in
                let left = lhs.creationDate ?? 0, right = rhs.creationDate ?? 0
                return left == right ? lhs.assetId < rhs.assetId : left < right
            }
        guard timed.count >= DuplicateStrictness.seriesMinCount else { return [] }

        var runs: [[HashedPhoto]] = []
        var current: [HashedPhoto] = [timed[0]]
        for photo in timed.dropFirst() {
            let previous = current[current.count - 1]
            let gap = (photo.creationDate ?? 0) - (previous.creationDate ?? 0)
            let distance = (photo.hash.bits ^ previous.hash.bits).nonzeroBitCount
            if gap <= DuplicateStrictness.seriesMaxGap,
               distance <= DuplicateStrictness.seriesMaxDistance {
                current.append(photo)
            } else {
                runs.append(current)
                current = [photo]
            }
        }
        runs.append(current)
        return assemble(runs, strictness: .series)
    }

    /// Turns raw member sets into ordered groups: sets too small for the mode
    /// dropped, members ordered the way that mode is read, groups newest-first.
    /// Shared by the grouping pass and by the cache read-back, so a cached
    /// group is ordered exactly like a fresh one.
    ///
    /// A duplicate group is read best-first — the copy worth keeping leads it.
    /// A series is read **in the order it was shot**, because the thing being
    /// judged is how the pose changed from one frame to the next, and a run
    /// sorted by file size is not a run any more.
    static func assemble(
        _ memberSets: [[HashedPhoto]],
        strictness: DuplicateStrictness
    ) -> [DuplicateGroup] {
        let order: (HashedPhoto, HashedPhoto) -> Bool =
            strictness == .series ? oldestFirst : keepFirst
        return memberSets
            .filter { $0.count >= strictness.minimumGroupSize }
            .map { DuplicateGroup(members: $0.sorted(by: order)) }
            .sorted(by: groupOrder)
    }

    /// Capture order, for a series.
    static func oldestFirst(_ a: HashedPhoto, _ b: HashedPhoto) -> Bool {
        let left = a.creationDate ?? .max, right = b.creationDate ?? .max
        return left == right ? a.assetId < b.assetId : left < right
    }

    private struct BucketKey: Hashable {
        var byteIndex: Int
        var value: UInt8
    }

    /// The byte itself plus its eight single-bit flips.
    private static func oneBitVariants(of byte: UInt8) -> [UInt8] {
        var variants = [byte]
        variants.reserveCapacity(9)
        for bit in 0..<8 {
            variants.append(byte ^ (1 << UInt8(bit)))
        }
        return variants
    }

    /// Best candidate to keep first: most pixels, then largest file, then a
    /// favourite, then the oldest (the original usually predates its copies).
    static func keepFirst(_ a: HashedPhoto, _ b: HashedPhoto) -> Bool {
        if a.pixelCount != b.pixelCount { return a.pixelCount > b.pixelCount }
        if (a.fileSize ?? 0) != (b.fileSize ?? 0) { return (a.fileSize ?? 0) > (b.fileSize ?? 0) }
        if a.isFavorite != b.isFavorite { return a.isFavorite }
        if (a.creationDate ?? .max) != (b.creationDate ?? .max) {
            return (a.creationDate ?? .max) < (b.creationDate ?? .max)
        }
        return a.assetId < b.assetId
    }

    /// Newest groups first, so what the user just shot or imported is at the top.
    private static func groupOrder(_ a: DuplicateGroup, _ b: DuplicateGroup) -> Bool {
        let newestA = a.members.compactMap(\.creationDate).max() ?? 0
        let newestB = b.members.compactMap(\.creationDate).max() ?? 0
        if newestA != newestB { return newestA > newestB }
        return a.id < b.id
    }
}
