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

    /// One landing per photo, in run order.
    static func landings(_ photos: [Photo], in destination: [Existing]) -> [Landing] {
        let byName = Dictionary(destination.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var names = Set(destination.map(\.name))
        return photos.map { photo in
            if let there = byName[photo.name.lowercased()], there.size == photo.size, there.sha256 == photo.sha256 {
                return .alreadyThere(there.name)
            }
            let free = ServerUploadPath.nextFreeName(for: photo.name, existing: names)
            names.insert(free)
            return .name(free)
        }
    }
}
