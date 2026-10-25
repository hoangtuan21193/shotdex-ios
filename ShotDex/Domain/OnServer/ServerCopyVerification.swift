import Foundation

/// The last look at a server file before its Photos twin is deleted
/// (FS-19.07 §9): the file must still be at its path with the size and the
/// write time the listing saw. Nothing is hashed again.
enum ServerCopyVerification {
    enum Result: Equatable, Sendable {
        case same
        /// Not at its path any more — deleted, or moved.
        case gone
        /// There, but rewritten: another size or another write time.
        case changed
    }

    static func compare(size: Int64?, modifiedAt: Int?, entry: RemoteEntry?) -> Result {
        guard let entry, !entry.isDirectory else { return .gone }
        if let size, entry.size != size { return .changed }
        if let modifiedAt, let modified = entry.modified, Int(modified.timeIntervalSince1970) != modifiedAt { return .changed }
        return .same
    }
}
