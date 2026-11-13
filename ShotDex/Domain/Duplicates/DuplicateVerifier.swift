import Foundation

/// Second opinion on the grouper's look-alikes and bursts (2026-11-10).
///
/// The 64-bit difference hash only sees left-to-right brightness: a bright
/// centre, a horizon or a document layout puts unrelated photos a few bits
/// apart. So the hash only *nominates*; a Vision feature print of each photo
/// (read by the scoring pass) has to agree before two photos stay together.
/// Exact copies are already proven by size, second and file name, and a
/// bracket or focus stack is meant to look different — both pass through.
///
/// Complete linkage: every member of a look-alike group is close to every
/// other member, not merely chained through a neighbour.
enum DuplicateVerifier {
    /// Feature-print distance (Vision revision 2, 0…2) still "the same
    /// picture". Measured 2026-11-10 on the simulator set: re-saves and
    /// 1280px copies 0.08–0.15, a 6% reframe with +0.25 EV 0.16–0.23,
    /// unrelated photos 0.64 and up — and two unrelated patterns whose
    /// hashes were *identical* 0.74.
    static let similarMaxDistance: Float = 0.4
    /// Consecutive frames of one moment: the subject is supposed to move.
    static let burstMaxDistance: Float = 0.55

    /// - Parameter distance: feature-print distance of two photos, `nil`
    ///   when either has no print.
    static func verify(_ groups: [DuplicateGroup], distance: (String, String) -> Float?) -> [DuplicateGroup] {
        groups.flatMap { group -> [DuplicateGroup] in
            guard group.kind != .exact, group.sourceSet == nil else { return [group] }
            let parts: [[HashedPhoto]]
            switch group.kind {
            case .burst: parts = runs(group.members, distance: distance)
            default: parts = clusters(group.members, distance: distance)
            }
            // A cut burst is still held to what makes a run a burst.
            let minimum = group.kind == .burst ? DuplicateGrouper.seriesMinCount : 2
            return parts.filter { $0.count >= minimum }.map {
                DuplicateGroup(members: $0, kind: group.kind, sourceSet: nil)
            }
        }
    }

    /// No print for one of the two (not compared yet, or only in iCloud
    /// with the network off) proves nothing: identical hashes were measured
    /// on unrelated pictures. Such a pair waits for its prints.
    static func isSamePicture(_ a: HashedPhoto, _ b: HashedPhoto, limit: Float, distance: (String, String) -> Float?) -> Bool {
        guard let d = distance(a.assetId, b.assetId) else { return false }
        return d <= limit
    }

    /// Members in their group order, each joining the first cluster whose
    /// every member it matches.
    static func clusters(_ members: [HashedPhoto], distance: (String, String) -> Float?) -> [[HashedPhoto]] {
        var clusters: [[HashedPhoto]] = []
        for member in members {
            if let slot = clusters.firstIndex(where: { cluster in
                cluster.allSatisfy { isSamePicture($0, member, limit: similarMaxDistance, distance: distance) }
            }) {
                clusters[slot].append(member)
            } else {
                clusters.append([member])
            }
        }
        return clusters
    }

    /// A burst in capture order, cut wherever a frame does not match the one
    /// before it.
    static func runs(_ members: [HashedPhoto], distance: (String, String) -> Float?) -> [[HashedPhoto]] {
        var runs: [[HashedPhoto]] = []
        for member in members {
            if let last = runs.last?.last,
               isSamePicture(last, member, limit: burstMaxDistance, distance: distance) {
                runs[runs.count - 1].append(member)
            } else {
                runs.append([member])
            }
        }
        return runs
    }
}
