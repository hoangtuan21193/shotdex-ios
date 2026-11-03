import Foundation

/// Which server sources a common-photos run touches (FS-19.08 §6): the ones
/// whose folder holds a run folder or the destination are rescanned after
/// it; a destination no source holds gets a warning in the sheet, since the
/// photos moved there leave ShotDex until it is added. Pure.
enum CommonPhotosSources {
    /// A server source as the run sees it: its connection, and the folder it
    /// indexes, as a path from the server's root.
    struct Source: Equatable, Sendable {
        let sourceId: String
        let connection: FileServer
        var folder: String { connection.folder }
    }

    static func sameFiles(_ a: FileServer, _ b: FileServer) -> Bool { ServerIdentity.sameFiles(a, b) }

    /// The sources a run on `server` over `paths` (its folders and its
    /// destination, server paths) has to rescan, in `sources` order: a
    /// source holding one of the paths, or held by one — the photos moved
    /// out of a run folder leave every source inside it too.
    static func toRescan(paths: [String], on server: FileServer, sources: [Source]) -> [String] {
        sources.filter { source in
            sameFiles(source.connection, server) && paths.contains {
                CommonPhotosSelection.contains(source.folder, $0) || CommonPhotosSelection.contains($0, source.folder)
            }
        }.map(\.sourceId)
    }

    /// Whether some source on the same files holds `destination` — shows
    /// what lands there.
    static func isIndexed(_ destination: String, on server: FileServer, sources: [Source]) -> Bool {
        sources.contains { sameFiles($0.connection, server) && CommonPhotosSelection.contains($0.folder, destination) }
    }
}
