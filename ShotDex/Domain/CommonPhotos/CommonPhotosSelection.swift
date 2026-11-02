import Foundation

/// The folders a common-photos run compares and where it saves (FS-19.08
/// §4): what makes a choice impossible, checked before anything is listed.
/// A folder inside another would match its own photos; a destination inside
/// a source would be listed, and moved from, as a source.
enum CommonPhotosSelection {
    enum Problem: Equatable, Sendable {
        case tooFewFolders
        case nested(outer: String, inner: String)
        case destinationInsideSource(source: String)
    }

    /// The first thing wrong with the choice, or nil when it can run. Paths
    /// are server paths; case is ignored, as on an SMB share.
    static func problem(folders: [String], destination: String?) -> Problem? {
        let folders = folders.map(ServerUploadPath.normalizedFolder)
        guard Set(folders.map(comparable)).count >= 2 else { return .tooFewFolders }
        for (outerIndex, outer) in folders.enumerated() {
            for (innerIndex, inner) in folders.enumerated() where innerIndex != outerIndex && contains(outer, inner) {
                return .nested(outer: outer, inner: inner)
            }
        }
        if let destination = destination.map(ServerUploadPath.normalizedFolder),
           let source = folders.first(where: { contains($0, destination) }) {
            return .destinationInsideSource(source: source)
        }
        return nil
    }

    /// Whether `inner` is `outer` or below it.
    static func contains(_ outer: String, _ inner: String) -> Bool {
        let outer = comparable(outer)
        let inner = comparable(inner)
        return outer.isEmpty || inner == outer || inner.hasPrefix(outer + "/")
    }

    private static func comparable(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }
}
