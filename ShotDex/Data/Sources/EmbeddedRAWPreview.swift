import Foundation
import ImageIO
import Photos

/// The JPEG preview a camera embeds in its RAW — what Convert to JPEG uses
/// for a RAW this iOS build can't decode (FS-03.04b §4). Read with ImageIO
/// from the original file: Photos itself returns nothing for such a RAW
/// (measured, M3).
enum EmbeddedRAWPreview {
    /// The preview at its own size (or `maxPixelSize`, if smaller), upright.
    /// `allowNetwork` lets an original only in iCloud come down first.
    static func image(for asset: PHAsset, maxPixelSize: Int? = nil, allowNetwork: Bool = true) async -> CGImage? {
        guard let url = await copyRAW(of: asset, allowNetwork: allowNetwork) else { return nil }
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return image(at: url, maxPixelSize: maxPixelSize)
    }

    static func image(at url: URL, maxPixelSize: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        var options: [CFString: Any] = [
            // The embedded preview only — never a decode of the RAW itself.
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let maxPixelSize { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The smallest preview among these photos, for the question — only the
    /// files already on the device are read.
    static func smallestSize(of assets: [PHAsset]) async -> PixelSize? {
        var smallest: PixelSize?
        for asset in assets {
            guard let image = await image(for: asset, allowNetwork: false) else { continue }
            let size = PixelSize(width: image.width, height: image.height)
            if smallest.map({ size.width * size.height < $0.width * $0.height }) ?? true { smallest = size }
        }
        return smallest
    }

    private static func copyRAW(of asset: PHAsset, allowNetwork: Bool) async -> URL? {
        let resource = await MainActor.run {
            PHAssetResource.assetResources(for: asset).first {
                [.photo, .alternatePhoto].contains($0.type) && SystemRAWDecoderProbe.isRAW($0)
            }
        }
        guard let resource else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RAWPreview-\(UUID().uuidString)", isDirectory: true)
        let url = folder.appendingPathComponent(resource.originalFilename)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }
}
