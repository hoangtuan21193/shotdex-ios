import Foundation

/// FS-19.08 §6d: what each Same photo becomes in the destination, worked out
/// when the scan ends, by the rule the run applies (`CommonPhotosRunner`):
/// the first copy's name; the same bytes already under that name are
/// Already there; a name taken by other bytes, or by an earlier photo of the
/// run, gets the next free one (`ServerUploadPath.nextFreeName`).
///
/// A plan, not a promise: the run lists the destination again and names each
/// photo from what is there then (AC-180).
enum CommonPhotosDestinationPlan {
    enum Landing: Equatable, Sendable {
        /// Written under this name.
        case name(String)
        /// These bytes are already there under this name.
        case alreadyThere(String)

        var name: String {
            switch self {
            case .name(let name), .alreadyThere(let name): name
            }
        }
    }

    /// A Same photo as the plan needs it: the name its first copy carries,
    /// its size and SHA-256.
    struct Photo: Equatable, Sendable {
        let name: String
        let size: Int64
        let sha256: String
    }

    /// A file already in the destination; `sha256` once read.
    struct Existing: Equatable, Sendable {
        let name: String
        let size: Int64
        var sha256: String?
    }

    /// The destination files whose bytes decide a landing: same name and
    /// size as a photo, SHA-256 not known yet. Only these are read.
    static func toHash(_ photos: [Photo], in destination: [Existing]) -> [Existing] {
        let byName = Dictionary(destination.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return photos.compactMap { photo in
            guard let there = byName[photo.name.lowercased()], there.size == photo.size, there.sha256 == nil,
                  seen.insert(there.name.lowercased()).inserted else { return nil }
            return there
        }
    }

    /// One landing per photo, in run order. `motionOf` pairs a Live
    /// Photo's still (by position) with its motion (§6f): the still takes a
    /// name whose motion name is free too, and the motion takes the still's.
    static func landings(_ photos: [Photo], in destination: [Existing], motionOf: [Int: Int] = [:]) -> [Landing] {
        let byName = Dictionary(destination.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let stillOf = Dictionary(motionOf.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        var names = Set(destination.map(\.name))
        var out: [Landing] = []
        for (index, photo) in photos.enumerated() {
            // The motion follows the name its still got.
            var name = photo.name
            if let still = stillOf[index], still < out.count {
                name = CommonPhotosLive.motionName(for: out[still].name, motionExtension: (photo.name as NSString).pathExtension)
            }
            if let there = byName[name.lowercased()], there.size == photo.size, there.sha256 == photo.sha256 {
                out.append(.alreadyThere(there.name))
                continue
            }
            let free = if let motion = motionOf[index] {
                CommonPhotosLive.freeName(forStill: name, motionExtension: (photos[motion].name as NSString).pathExtension, existing: names)
            } else {
                ServerUploadPath.nextFreeName(for: name, existing: names)
            }
            names.insert(free)
            out.append(.name(free))
        }
        return out
    }
}
