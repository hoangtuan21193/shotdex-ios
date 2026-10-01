import Photos
import ShotDexKit
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

        // The same file a share would hand over, at the Settings level
        // (FS-08.06 AC-19): the edited version of an edited photo, without
        // what the level removes. A file that cannot be cleaned fails the
        // drag; it is never handed over as it was.
        let level = MetadataLevel.sharingDefault()
        let source = ShareSource(asset: asset)
        let plan = ShareDragPlan(source: source, level: level)
        provider.suggestedName = (source.filename as NSString).deletingPathExtension
        provider.registerFileRepresentation(
            forTypeIdentifier: plan.type.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            // iCloud-only assets download first, which is why this is the
            // slow half of the provider and the identifier payload above
            // exists at all.
            let progress = Progress(totalUnitCount: 100)
            Task {
                if let url = await fileURL(for: source, level: level, rawChoice: plan.rawChoice) {
                    progress.completedUnitCount = 100
                    // `false` keeps the temporary file alive until UIKit has
                    // read it; the launch sweep removes the folder.
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

    private static func fileURL(for source: ShareSource, level: MetadataLevel, rawChoice: RAWChoice) async -> URL? {
        guard let folder = try? ShareExportPipeline.makeFolder() else { return nil }
        var pipeline = ShareExportPipeline(reader: PhotoKitShareReader(), folder: folder, level: level)
        pipeline.rawChoice = rawChoice
        let result = await pipeline.export([source])
        return result.files.first
    }
}

enum PhotoDragError: Error {
    case unavailable
}
