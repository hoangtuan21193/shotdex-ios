import Foundation
import ImageIO
import Photos

/// What the editor opens: a photo in the library, or a server original
/// fetched to this device (FS-17.06 §5). Every type that holds "the photo
/// being edited" — the render session, the controller, the multi-photo run,
/// the batch saver, Resize — holds one of these, so a server photo takes the
/// same path from the first render on.
enum PhotoEditOrigin: Identifiable, Hashable {
    case asset(PHAsset)
    case serverFile(FetchedServerPhoto)

    /// Stable across a run: the asset's local identifier, or connection +
    /// server path.
    var id: String {
        switch self {
        case .asset(let asset): asset.localIdentifier
        case .serverFile(let photo): photo.id
        }
    }

    var asset: PHAsset? {
        if case .asset(let asset) = self { asset } else { nil }
    }

    var serverFile: FetchedServerPhoto? {
        if case .serverFile(let photo) = self { photo } else { nil }
    }

    /// True for a server photo: nothing in Photos to save to, revert or
    /// recall a recipe from.
    var isServerFile: Bool { serverFile != nil }

    /// The image's size as it is shown — orientation applied — for the
    /// panel's shape before the first render.
    var pixelSize: (width: Int, height: Int) {
        switch self {
        case .asset(let asset):
            return (asset.pixelWidth, asset.pixelHeight)
        case .serverFile(let photo):
            return Self.orientedPixelSize(of: photo.primaryURL) ?? (0, 0)
        }
    }

    /// Changes whenever the photo does — the preview cache's staleness key.
    var stamp: Double {
        switch self {
        case .asset(let asset):
            return asset.modificationDate?.timeIntervalSince1970 ?? 0
        case .serverFile(let photo):
            // Size + write time: a file replaced on the server within the
            // same second still differs in size nearly always.
            let modified = photo.photo.modified?.timeIntervalSince1970 ?? 0
            return modified + Double(photo.photo.totalBytes % 1_000_000) / 1_000_000
        }
    }

    static func orientedPixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    static func == (lhs: PhotoEditOrigin, rhs: PhotoEditOrigin) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
