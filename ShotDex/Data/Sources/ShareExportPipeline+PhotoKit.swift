import AVFoundation
import Photos
import UniformTypeIdentifiers

extension ShareSource {
    /// What kind of share item a library asset is. A Live Photo is an
    /// `.image` asset and shares as a photo: only its still leaves (spec §5).
    static func kind(mediaType: PHAssetMediaType, sharedType: String? = nil) -> Kind {
        if mediaType == .video { return .video }
        if let sharedType, UTType(sharedType)?.conforms(to: .rawImage) == true { return .raw }
        return .photo
    }

    /// The resource whose bytes a photo shares: the edited rendering when the
    /// photo has one, otherwise the photo itself. Never the paired video of a
    /// Live Photo, and never the RAW half of a RAW + JPEG pair — the same
    /// choice `requestImageDataAndOrientation` makes for the current version.
    static func sharedResourceType(among types: [PHAssetResourceType]) -> PHAssetResourceType? {
        if types.contains(.fullSizePhoto) { return .fullSizePhoto }
        if types.contains(.photo) { return .photo }
        return nil
    }

    /// The shared file's name: the photo's own name, with the extension of the
    /// bytes actually handed over (an edited HEIC renders as JPEG).
    static func filename(original: String, shared: String) -> String {
        let base = (original as NSString).deletingPathExtension
        let ext = (shared as NSString).pathExtension
        guard !base.isEmpty else { return shared }
        return ext.isEmpty ? original : "\(base).\(ext)"
    }

    init(asset: PHAsset) {
        let resources = PHAssetResource.assetResources(for: asset)
        let shared = Self.sharedResourceType(among: resources.map(\.type))
            .flatMap { type in resources.first { $0.type == type } }
        // An edited RAW shares its rendering, a JPEG or HEIC: only an
        // untouched RAW-only photo shares the RAW itself.
        let kind = Self.kind(mediaType: asset.mediaType, sharedType: shared?.uniformTypeIdentifier)
        let original = resources.first { $0.type == .photo || $0.type == .video }?.originalFilename ?? "Photo"
        var filename = original
        if kind != .video, let shared {
            filename = Self.filename(original: original, shared: shared.originalFilename)
        }
        let sharedType = kind == .video
            ? resources.first { $0.type == .video }?.uniformTypeIdentifier
            : shared?.uniformTypeIdentifier
        self.init(
            id: asset.localIdentifier, kind: kind, filename: filename,
            hasLocation: asset.location != nil, uniformType: sharedType
        )
    }
}

/// Reads shared items out of the photo library.
struct PhotoKitShareReader: ShareAssetReader {
    enum ReadError: Error { case missing, noPhotoResource, noVideoFile }

    func writePhoto(_ source: ShareSource, to url: URL) async throws {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [source.id], options: nil).firstObject
        else { throw ReadError.missing }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let type = ShareSource.sharedResourceType(among: resources.map(\.type)),
              let resource = resources.first(where: { $0.type == type })
        else { throw ReadError.noPhotoResource }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
    }

    func videoURL(for source: ShareSource) async throws -> URL {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [source.id], options: nil).firstObject
        else { throw ReadError.missing }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        let url: URL? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
        guard let url else { throw ReadError.noVideoFile }
        return url
    }
}
