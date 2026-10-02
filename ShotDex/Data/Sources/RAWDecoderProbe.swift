import CoreImage
import Foundation
import Photos
import ShotDexKit
import UniformTypeIdentifiers

/// What the verdict pass asks of the system (FS-03.04b §2), behind a
/// protocol so tests can play a decoder that refuses everything.
protocol RAWDecoderProbing: Sendable {
    /// `CIRAWFilter.supportedCameraModels`: 930 entries on iOS 26.5.
    func supportedCameraModels() -> [String]
    /// Tries one photo's RAW file if it is on the device: `true` decoded,
    /// `false` refused, `nil` when the file is only in iCloud. Never
    /// downloads (AC-12).
    func localFileDecodes(assetId: String) async -> Bool?
    /// Which of these RAW-named photos also carry a JPEG or HEIC — a pair
    /// kept with its RAW as the original (M3), never marked.
    func renderedTwinIds(among assetIds: [String]) async -> Set<String>
}

/// The decoder of this device, tried on files Photos already has here.
struct SystemRAWDecoderProbe: RAWDecoderProbing {
    let temporaryRoot: URL

    init(temporaryRoot: URL = FileManager.default.temporaryDirectory) {
        self.temporaryRoot = temporaryRoot
    }

    func supportedCameraModels() -> [String] { CIRAWFilter.supportedCameraModels }

    /// Never the network: a file only in iCloud answers "not here", and the
    /// camera stays unknown rather than costing the user a download (AC-12).
    static func resourceRequestOptions() -> PHAssetResourceRequestOptions {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        return options
    }

    func localFileDecodes(assetId: String) async -> Bool? {
        guard let resource = await MainActor.run(body: { Self.rawResource(of: assetId) }) else { return nil }
        let folder = temporaryRoot.appendingPathComponent("RAWProbe-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(resource.originalFilename)
            try await PHAssetResourceManager.default().writeData(
                for: resource, toFile: url, options: Self.resourceRequestOptions()
            )
            return PhotoRenderService.canDecodeRAW(at: url)
        } catch {
            return nil
        }
    }

    func renderedTwinIds(among assetIds: [String]) async -> Set<String> {
        guard !assetIds.isEmpty else { return [] }
        return await MainActor.run {
            var twins = Set<String>()
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
            assets.enumerateObjects { asset, _, _ in
                let images = PHAssetResource.assetResources(for: asset).filter {
                    [.photo, .alternatePhoto, .fullSizePhoto].contains($0.type)
                }
                if images.contains(where: { !Self.isRAW($0) }) { twins.insert(asset.localIdentifier) }
            }
            return twins
        }
    }

    /// The photo's RAW file: its original, or the RAW of a pair.
    @MainActor
    private static func rawResource(of assetId: String) -> PHAssetResource? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else { return nil }
        return PHAssetResource.assetResources(for: asset).first {
            [.photo, .alternatePhoto].contains($0.type) && Self.isRAW($0)
        }
    }

    static func isRAW(_ resource: PHAssetResource) -> Bool {
        UTType(resource.uniformTypeIdentifier)?.conforms(to: .rawImage)
            ?? FileTypeBadge.isRAW(filename: resource.originalFilename)
    }
}
