import Photos
import UIKit
import UniformTypeIdentifiers

/// The receiving end of a drag that came from **another app**.
///
/// ShotDex's tools address photos by `PHAsset` local identifier — a collage
/// slot, a video clip and an album row all store one — so an image dropped in
/// from Photos in Split View, from Files, or from a browser cannot be placed
/// until it exists in the library. This imports it and hands back the new
/// identifiers, in drop order.
///
/// It writes to the user's library, which is why the tools that use it say so
/// afterwards rather than silently: see each call site's message.
enum PhotoDropImport {
    /// What a drop may carry that this can turn into an asset. Paired with
    /// `PhotoDragItem.assetIdentifierType` at every call site, which is
    /// checked first — a drag from inside ShotDex must never round-trip
    /// through an import.
    static let acceptedTypes: [String] = [UTType.image.identifier, UTType.movie.identifier]

    static func canImport(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { provider in
            acceptedTypes.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }
    }

    /// Imports every image or video among the providers. Returns the new
    /// assets' local identifiers, and the count of items that could not be
    /// read — the caller decides how loudly to say so.
    static func importAssets(
        from providers: [NSItemProvider],
        into library: PhotoLibraryService
    ) async -> (ids: [String], failures: Int) {
        var ids: [String] = []
        var failures = 0
        for provider in providers {
            guard let type = acceptedTypes.first(where: {
                provider.hasItemConformingToTypeIdentifier($0)
            }) else { continue }
            guard let url = await copyToTemporary(provider: provider, type: type) else {
                failures += 1
                continue
            }
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let isVideo = UTType(type)?.conforms(to: .movie) == true
            if let id = try? await library.importFile(at: url, isVideo: isVideo) {
                ids.append(id)
            } else {
                failures += 1
            }
        }
        return (ids, failures)
    }

    /// What to tell the user after a drop, in one place rather than once per
    /// tool. Grammar agreement rather than a singular and a plural branch:
    /// Vietnamese and Japanese have no plural to pick between, and Polish and
    /// Russian have more forms than two — a hand-written `if` is wrong for
    /// all four.
    static func addedMessage(count: Int, destination: Destination) -> String {
        switch destination {
        case .library:
            String(
                localized: "^[\(count) photo](inflect: true) added to your library",
                comment: "Toast after importing photos dropped from another app"
            )
        case .libraryAndTimeline:
            String(
                localized: "^[\(count) item](inflect: true) added to your library and to the timeline",
                comment: "Toast after dropping media onto the Video Studio timeline from another app"
            )
        }
    }

    static func failureMessage(count: Int) -> String {
        String(
            localized: "^[\(count) item](inflect: true) couldn't be imported.",
            comment: "Toast when items dropped from another app could not be read"
        )
    }

    enum Destination {
        case library
        case libraryAndTimeline
    }

    /// `loadFileRepresentation` hands over a URL that is deleted the moment
    /// its completion returns, so the file has to be copied out before the
    /// import — which is asynchronous — can look at it.
    private static func copyToTemporary(provider: NSItemProvider, type: String) async -> URL? {
        let progress = Progress()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let load = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    guard let url else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ShotDexDrop-\(UUID().uuidString)", isDirectory: true)
                    let destination = directory.appendingPathComponent(url.lastPathComponent)
                    do {
                        try FileManager.default.createDirectory(
                            at: directory,
                            withIntermediateDirectories: true
                        )
                        try FileManager.default.copyItem(at: url, to: destination)
                        continuation.resume(returning: destination)
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
                progress.addChild(load, withPendingUnitCount: 1)
                progress.totalUnitCount = 1
            }
        } onCancel: {
            // Without this, cancelling the caller leaves the provider copying
            // a file nobody is waiting for and the continuation parked until
            // it finishes anyway.
            progress.cancel()
        }
    }
}
