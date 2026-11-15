import Foundation

/// The second way a look-alike is found (FS-06.06 §14.1, after Immich, who
/// asks a vector index for the nearest CLIP embeddings): photos the hash did
/// not pair — a crop, a strong edit, a re-export — are nominated in buckets of
/// **one capture second and one camera** (an export or a crop keeps the
/// capture time of its original); the scoring pass reads each member's Vision
/// print and the verifier (§4a, every pair ≤ 0.4) keeps only real look-alikes.
/// A bucket with no prints shows nothing.
///
/// Review 2026-11-16: the spec's day × camera bucket put most of a library in
/// a bucket — hours of scoring and every print unarchived on each load. One
/// second keeps the scored set to the photos that can be a copy of another.
enum FeaturePrintCandidates {
    /// Members a bucket may hold — the verifier compares every pair.
    static let bucketCap = 60

    private struct Key: Hashable {
        var second: Int
        var camera: String
        var isScreenshot: Bool
    }

    /// Look-alike groups to verify, from photos not already in a group and
    /// with a capture date.
    static func nominate(_ photos: [HashedPhoto], grouped: Set<String>) -> [DuplicateGroup] {
        var buckets: [Key: [HashedPhoto]] = [:]
        for photo in photos where !grouped.contains(photo.assetId) {
            guard let second = photo.creationDate else { continue }
            buckets[Key(second: second, camera: photo.cameraModel ?? "", isScreenshot: photo.isScreenshot), default: []]
                .append(photo)
        }
        var groups: [DuplicateGroup] = []
        for members in buckets.values where members.count > 1 {
            let sorted = members.sorted { $0.assetId < $1.assetId }
            for start in stride(from: 0, to: sorted.count, by: bucketCap) {
                let slice = Array(sorted[start..<min(start + bucketCap, sorted.count)])
                // Frames shot in one second at different exposures or focus
                // are material for a merge (§5), not look-alikes; they would
                // also skip the print check as a source set.
                guard slice.count > 1, DuplicateSourceSet.detect(slice) == nil else { continue }
                groups.append(DuplicateGroup(members: slice, kind: .similar))
            }
        }
        return groups.sorted { $0.id < $1.id }
    }
}
