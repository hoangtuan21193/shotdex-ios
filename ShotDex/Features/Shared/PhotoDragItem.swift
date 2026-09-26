import Photos
import UIKit
import UniformTypeIdentifiers

/// Turns library assets into drag items, and reads them back on the other end.
///
/// Two payloads on one provider, because a drag has two audiences. Another app
/// gets the picture itself, as a file of its original type. ShotDex gets the
/// asset's local identifier, which is all an album needs and costs nothing to
/// carry — dropping forty photos into an album must not first export forty
/// files.
enum PhotoDragItem {
    /// Private type for the identifier payload. Deliberately not a public one:
    /// a local identifier means nothing outside this device, so no other app
    /// should be offered it.
    static let assetIdentifierType = "com.hoangtuan.shotdex.asset-identifier"

    static func provider(for asset: PHAsset) -> NSItemProvider {
        let provider = NSItemProvider()
        let id = asset.localIdentifier

        provider.registerDataRepresentation(
            forTypeIdentifier: assetIdentifierType,
            visibility: .ownProcess
        ) { completion in
            completion(Data(id.utf8), nil)
            return nil
        }

        let type = exportType(for: asset)
        provider.suggestedName = PHAssetResource.assetResources(for: asset)
            .first?.originalFilename
        provider.registerFileRepresentation(
            forTypeIdentifier: type.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            // The whole file, not a rendition: a photo dropped into another app
            // should be the photo, EXIF and all. iCloud-only assets download
            // first, which is why this is the slow half of the provider and the
            // identifier payload above exists at all.
            let progress = Progress(totalUnitCount: 100)
            Task {
                if let url = await fileURL(for: asset, type: type) {
                    progress.completedUnitCount = 100
                    // `false` keeps the temporary file alive until UIKit has
                    // read it; it lives in this process's temp directory and
                    // goes with the app.
                    completion(url, false, nil)
                } else {
                    completion(nil, false, PhotoDragError.unavailable)
                }
            }
            return progress
        }
        return provider
    }

    /// Asset ids carried by a drop that came from inside ShotDex, in drop
    /// order. Empty for a drag from another app, which is how a caller tells
    /// the two apart. Main actor because UIKit's drop session is.
    @MainActor
    static func assetIdentifiers(in session: any UIDropSession) async -> [String] {
        let providers = session.items.map(\.itemProvider)
            .filter { $0.hasItemConformingToTypeIdentifier(assetIdentifierType) }
        guard !providers.isEmpty else { return [] }
        var ids: [String] = []
        for provider in providers {
            let data: Data? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(
                    forTypeIdentifier: assetIdentifierType
                ) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            guard let data, let id = String(data: data, encoding: .utf8) else { continue }
            ids.append(id)
        }
        return ids
    }

    static func canAcceptAssets(_ session: any UIDropSession) -> Bool {
        session.hasItemsConforming(toTypeIdentifiers: [assetIdentifierType])
    }

    // MARK: Files

    private static func exportType(for asset: PHAsset) -> UTType {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: PHAssetResourceType = asset.mediaType == .video ? .video : .photo
        let resource = resources.first { $0.type == preferred } ?? resources.first
        if let identifier = resource?.uniformTypeIdentifier,
           let type = UTType(identifier) {
            return type
        }
        return asset.mediaType == .video ? .quickTimeMovie : .jpeg
    }

    private static func fileURL(for asset: PHAsset, type: UTType) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred: PHAssetResourceType = asset.mediaType == .video ? .video : .photo
        guard let resource = resources.first(where: { $0.type == preferred })
            ?? resources.first
        else { return nil }

        let name = resource.originalFilename
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexDrag-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )) != nil else { return nil }
        let url = directory.appendingPathComponent(name)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
            return url
        } catch {
            return nil
        }
    }
}

enum PhotoDragError: Error {
    case unavailable
}
