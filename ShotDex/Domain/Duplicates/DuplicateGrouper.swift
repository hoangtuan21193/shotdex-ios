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
    var modificationDate: Int? = nil
    /// EXIF focal length in mm; two photos more than 10% apart never group.
    var focalLength: Double? = nil
    /// The system's screenshot subtype.
    var isScreenshot = false
    /// The file carries a camera's EXIF (a camera model). A copy sent through
    /// WhatsApp or Zalo has it stripped, and its date is the day it arrived.
    var hasCameraEXIF = true
    /// Exposure compensation in EV, from the scoring pass's EXIF read
    /// (`duplicate_quality`). `nil` until read, or when the file has none.
    var exposureBias: Double? = nil
    /// TIFF Software of the file, from the same read.
    var software: String? = nil
    var originalFilename: String? = nil
    /// "1/60 s" — for the caption when shutter speeds differ in a group.
    var shutterDisplay: String? = nil

    /// Software that writes an *edit*: a file it saved is an export of an
    /// edit, which counts as edited when picking the keeper (FS-06.06 §7.4).
    static let editorSoftware = ["lightroom", "photoshop", "capture one", "snapseed", "darkroom", "vsco",
                                 "pixelmator", "affinity", "dxo", "luminar", "on1", "afterlight", "shotdex"]

    var isExportOfEdit: Bool {
        guard let software = software?.lowercased() else { return false }
        return Self.editorSoftware.contains { software.contains($0) }
    }

    var id: String { assetId }

    var pixelCount: Int {
        guard let width, let height else { return 0 }
        return width * height
    }

    var longEdge: Int? {
        guard let width, let height else { return nil }
        return max(width, height)
    }

    /// The second the photo was taken, or — with no capture date — the
    /// second it was last saved.
    var captureSecond: Int? { creationDate ?? modificationDate }
}

/// What kind of near-identical set a group is (FS-06.06 §4). Grouping runs
/// once and every photo lands in at most one kind — v3 replaced the three
/// Exact · Similar · Series levels and the Bursts tab with this.
enum DuplicateKind: String, CaseIterable, Sendable, Identifiable {
    /// Same picture, same pixel size, same capture second.
    case copies
    /// Copies plus at least one smaller re-save of them (WhatsApp, an export).
    case smallerCopies
    /// Frames of one moment: a burst, or a run shot seconds apart.
    case sameMoment
    /// Near the same picture, none of the above.
    case lookAlikes
    /// Every member is a screenshot.
    case screenshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copies: String(localized: "Copies", comment: "Duplicates: kind of group — identical copies")
        case .smallerCopies: String(localized: "Smaller copies", comment: "Duplicates: kind of group — copies with smaller re-saves")
        case .sameMoment: String(localized: "Same moment", comment: "Duplicates: kind of group — frames shot seconds apart")
        case .lookAlikes: String(localized: "Look-alikes", comment: "Duplicates: kind of group — near-identical photos")
        case .screenshots: String(localized: "Screenshots", comment: "Duplicates: kind of group — screenshots")
        }
    }

    /// Copies and smaller copies are the same picture: removing them loses
    /// nothing, so they are what Quick clean offers (§7.2).
    var isCopy: Bool { self == .copies || self == .smallerCopies }
}

/// A set of photos judged to be the same picture or the same moment.
/// Copies, smaller copies, look-alikes and screenshots are ordered best
/// first by the keeper rule; a same-moment run in the order it was shot.
struct DuplicateGroup: Identifiable, Equatable, Sendable {
    /// Stable across regroups as long as the same member leads the group.
    var id: String { members[0].assetId }
    var members: [HashedPhoto]
    var kind: DuplicateKind
    /// A bracket or focus stack: material for a merge, not junk (§5).
    var sourceSet: DuplicateSourceSet? = nil

    var count: Int { members.count }
    var memberIds: Set<String> { Set(members.map(\.assetId)) }

    /// Bytes freed by keeping only the largest member.
    var reclaimableBytes: Int {
        let sizes = members.compactMap(\.fileSize)
        guard let largest = sizes.max() else { return 0 }
        return sizes.reduce(0, +) - largest
    }
}

/// Pure grouping of hashed photos into duplicate sets, one pass, one kind
/// per photo (FS-06.06 §4).
///
/// Identical hashes are bucketed first, and the near-match search runs over
/// the *distinct* hashes only — so a thousand blank screenshots sharing one
/// hash cost one representative, not a million pair checks. Near matches are
/// found with byte buckets: two 64-bit hashes within 10 bits of each other
/// must agree to within 1 bit on at least one of their 8 bytes (pigeonhole),
/// so each hash probes its 8 bytes × 9 one-bit variants and verifies the full
/// distance only on those candidates.
///
/// Kinds are taken in priority order — copies, then same moment, then
/// look-alikes — and a photo taken by one is not offered to the next.
enum DuplicateGrouper {
    /// Largest Hamming distance still "the same picture". 10 of 64 bits is
    /// the usual dHash working threshold: well under the ~32 two unrelated
    /// pictures average, above the 2–6 a re-encode or a modest resize costs.
    static let lookAlikeMaxDistance = 10
    /// Seconds allowed between one frame of a moment and the next.
    static let seriesMaxGap = 30
    /// How far apart two *consecutive* frames of a moment may be. Looser than
    /// a look-alike: the subject is supposed to have moved.
    static let seriesMaxDistance = 20
    /// Two frames 20 seconds apart is an ordinary thing to shoot.
    static let seriesMinCount = 3
    /// A smaller copy's long edge is at most this share of the bigger one's.
    static let smallerEdgeRatio = 0.75
    /// Focal lengths further apart than this are two framings, not copies.
    static let focalTolerance = 0.10

    /// - Parameter bursts: PhotoKit burst id per asset id — frames of a burst
    ///   always form a same-moment group.
    static func groups(from photos: [HashedPhoto], bursts: [String: String] = [:]) -> [DuplicateGroup] {
        guard photos.count > 1 else { return [] }
        var photosByHash: [UInt64: [Int]] = [:]
        for (index, photo) in photos.enumerated() {
            photosByHash[photo.hash.bits, default: []].append(index)
        }
        let nearPairs = nearHashPairs(Array(photosByHash.keys), maxDistance: lookAlikeMaxDistance)
        var taken = Set<Int>()
        var sets: [(DuplicateKind, [Int])] = []

        // 1 — Copies and smaller copies: components of "copy" (same hash, same
        // size, same second) and "smaller copy" (≤ 10 bits, long edge ≤ 75%,
        // same second or the small one has lost its camera EXIF).
        var copies = UnionFind(count: photos.count)
        for indices in photosByHash.values where indices.count > 1 {
            var first: [CopyKey: Int] = [:]
            for index in indices {
                let photo = photos[index]
                guard let second = photo.captureSecond else { continue }
                let key = CopyKey(width: photo.width, height: photo.height, second: second)
                if let lead = first[key] {
                    if focalCompatible(photos[lead], photo) { copies.union(lead, index) }
                } else {
                    first[key] = index
                }
            }
        }
        for (left, right) in nearPairs + photosByHash.keys.map({ ($0, $0) }) {
            let pool = left == right ? photosByHash[left]! : photosByHash[left]! + photosByHash[right]!
            linkSmallerCopies(pool, photos: photos, into: &copies)
        }
        for members in copies.components() where members.count > 1 {
            let sizes = Set(members.map { SizeKey(width: photos[$0].width, height: photos[$0].height) })
            sets.append((sizes.count > 1 ? .smallerCopies : .copies, members))
            taken.formUnion(members)
        }

        // 2 — Same moment: bursts, then runs shot seconds apart.
        var byBurst: [String: [Int]] = [:]
        for index in photos.indices where !taken.contains(index) {
            if let burst = bursts[photos[index].assetId] { byBurst[burst, default: []].append(index) }
        }
        for members in byBurst.values where members.count > 1 {
            sets.append((.sameMoment, members))
            taken.formUnion(members)
        }
        for run in seriesRuns(photos.indices.filter { !taken.contains($0) }, photos: photos) {
            sets.append((.sameMoment, run))
            taken.formUnion(run)
        }

        // 3 — Look-alikes among what is left.
        var alike = UnionFind(count: photos.count)
        func free(_ hash: UInt64) -> [Int] { photosByHash[hash]!.filter { !taken.contains($0) } }
        for hash in photosByHash.keys {
            linkCompatible(free(hash), photos: photos, into: &alike)
        }
        for (left, right) in nearPairs {
            let a = free(left), b = free(right)
            for index in a {
                if let other = b.first(where: { focalCompatible(photos[index], photos[$0]) }) {
                    alike.union(index, other)
                }
            }
        }
        for members in alike.components() where members.count > 1 && !taken.contains(members[0]) {
            sets.append((.lookAlikes, members))
        }

        return assemble(sets.map { kind, members in (kind, members.map { photos[$0] }) })
    }

    /// Runs of frames of one moment, in the order they were taken.
    ///
    /// Sorted by capture time and cut wherever the next frame is too late,
    /// too different, or at another focal length than **the one before it**.
    /// Chaining neighbour to neighbour is what lets a run drift: the first
    /// pose and the last may share little, and they still belong together as
    /// long as every step between them was small.
    ///
    /// A photo with no capture date is left out rather than guessed at.
    static func seriesRuns(_ indices: [Int], photos: [HashedPhoto]) -> [[Int]] {
        let timed = indices
            .filter { photos[$0].creationDate != nil }
            .sorted { oldestFirst(photos[$0], photos[$1]) }
        guard timed.count >= seriesMinCount else { return [] }
        var runs: [[Int]] = []
        var current = [timed[0]]
        for index in timed.dropFirst() {
            let previous = photos[current[current.count - 1]], photo = photos[index]
            let gap = (photo.creationDate ?? 0) - (previous.creationDate ?? 0)
            let distance = (photo.hash.bits ^ previous.hash.bits).nonzeroBitCount
            if gap <= seriesMaxGap, distance <= seriesMaxDistance, focalCompatible(previous, photo) {
                current.append(index)
            } else {
                runs.append(current)
                current = [index]
            }
        }
        runs.append(current)
        return runs.filter { $0.count >= seriesMinCount }
    }

    /// Turns member sets into ordered groups: sets under two members
    /// dropped, an all-screenshot set relabelled, brackets and focus stacks
    /// recognised (§5), members ordered the way
    /// their kind is read, groups newest first. Shared by the grouping pass
    /// and by the cache read-back, so a cached group reads like a fresh one.
    static func assemble(_ memberSets: [(DuplicateKind, [HashedPhoto])]) -> [DuplicateGroup] {
        memberSets
            .filter { $0.1.count >= 2 }
            .map { kind, members in
                let kind = members.allSatisfy(\.isScreenshot) ? .screenshots : kind
                let sourceSet = DuplicateSourceSet.detect(members)
                // A run and a source set are read in the order they were shot.
                let order: (HashedPhoto, HashedPhoto) -> Bool =
                    kind == .sameMoment || sourceSet != nil ? oldestFirst : bestFirst
                return DuplicateGroup(members: members.sorted(by: order), kind: kind, sourceSet: sourceSet)
            }
            .sorted(by: groupOrder)
    }

    /// Capture order, for a same-moment run.
    static func oldestFirst(_ a: HashedPhoto, _ b: HashedPhoto) -> Bool {
        let left = a.creationDate ?? .max, right = b.creationDate ?? .max
        return left == right ? a.assetId < b.assetId : left < right
    }

    /// The keeper rule (`DuplicateReview.ranks`) with nothing but the hash
    /// row to go on, then the oldest (the original predates its copies).
    static func bestFirst(_ a: HashedPhoto, _ b: HashedPhoto) -> Bool {
        if DuplicateReview.ranks(a, above: b, traits: [:]) { return true }
        if DuplicateReview.ranks(b, above: a, traits: [:]) { return false }
        let left = a.creationDate ?? .max, right = b.creationDate ?? .max
        return left == right ? a.assetId < b.assetId : left < right
    }

    /// Same scene at 24mm and 35mm is two framings, not a copy (persona An).
    /// Unknown focal length vetoes nothing.
    static func focalCompatible(_ a: HashedPhoto, _ b: HashedPhoto) -> Bool {
        guard let left = a.focalLength, let right = b.focalLength, left > 0, right > 0 else { return true }
        return abs(left - right) / max(left, right) <= focalTolerance
    }

    // MARK: Private

    private struct CopyKey: Hashable {
        var width: Int?
        var height: Int?
        var second: Int
    }

    private struct SizeKey: Hashable {
        var width: Int?
        var height: Int?
    }

    /// Links each smaller photo of `pool` to a bigger one it is a re-save of.
    private static func linkSmallerCopies(_ pool: [Int], photos: [HashedPhoto], into sets: inout UnionFind) {
        let sized = pool.filter { photos[$0].longEdge != nil }
        let edges = Set(sized.map { photos[$0].longEdge! })
        guard edges.count > 1 else { return }
        for small in sized {
            let photo = photos[small]
            let edge = Double(photo.longEdge!)
            let bigger = sized.filter { edge <= Double(photos[$0].longEdge!) * smallerEdgeRatio
                && focalCompatible(photos[$0], photo) }
            let match = photo.hasCameraEXIF
                ? bigger.first { photos[$0].captureSecond != nil && photos[$0].captureSecond == photo.captureSecond }
                : bigger.first
            if let match { sets.union(small, match) }
        }
    }

    /// Links every photo of one hash bucket to the ones it is focal-compatible with.
    private static func linkCompatible(_ indices: [Int], photos: [HashedPhoto], into sets: inout UnionFind) {
        guard indices.count > 1 else { return }
        for (position, index) in indices.enumerated() {
            if let other = indices[(position + 1)...].first(where: { focalCompatible(photos[index], photos[$0]) }) {
                sets.union(index, other)
            }
        }
    }

    /// Distinct-hash pairs within `maxDistance` bits.
    private static func nearHashPairs(_ hashes: [UInt64], maxDistance: Int) -> [(UInt64, UInt64)] {
        var buckets: [BucketKey: [Int]] = [:]
        for (position, hash) in hashes.enumerated() {
            for byteIndex in 0..<8 {
                let byte = UInt8(truncatingIfNeeded: hash >> UInt64(byteIndex * 8))
                buckets[BucketKey(byteIndex: byteIndex, value: byte), default: []].append(position)
            }
        }
        var pairs: [(UInt64, UInt64)] = []
        for (position, hash) in hashes.enumerated() {
            var seen = Set<Int>()
            for byteIndex in 0..<8 {
                let byte = UInt8(truncatingIfNeeded: hash >> UInt64(byteIndex * 8))
                for variant in oneBitVariants(of: byte) {
                    guard let candidates = buckets[BucketKey(byteIndex: byteIndex, value: variant)] else { continue }
                    for candidate in candidates where candidate > position && seen.insert(candidate).inserted {
                        if (hash ^ hashes[candidate]).nonzeroBitCount <= maxDistance {
                            pairs.append((hash, hashes[candidate]))
                        }
                    }
                }
            }
        }
        return pairs
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

    /// Newest groups first, so what the user just shot or imported is at the top.
    private static func groupOrder(_ a: DuplicateGroup, _ b: DuplicateGroup) -> Bool {
        let newestA = a.members.compactMap(\.creationDate).max() ?? 0
        let newestB = b.members.compactMap(\.creationDate).max() ?? 0
        if newestA != newestB { return newestA > newestB }
        return a.id < b.id
    }
}

/// Union-find with path compression; components come back in index order.
private struct UnionFind {
    private var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    mutating func find(_ index: Int) -> Int {
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

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a), rootB = find(b)
        if rootA != rootB { parent[max(rootA, rootB)] = min(rootA, rootB) }
    }

    mutating func components() -> [[Int]] {
        var byRoot: [Int: [Int]] = [:]
        for index in parent.indices { byRoot[find(index), default: []].append(index) }
        return byRoot.values.sorted { $0[0] < $1[0] }
    }
}
