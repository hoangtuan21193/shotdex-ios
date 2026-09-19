import Foundation
import Photos
import UIKit
import Vision

/// What one photo was found to contain.
struct SubjectObservation: Equatable, Sendable {
    let assetId: String
    /// Faces found. Zero is a real answer, not "unknown" — the row records
    /// that the photo was looked at.
    let faceCount: Int
    /// Cats or dogs found.
    let animalCount: Int
    /// False when no rendition could be obtained at all; the row is left
    /// pending so a later scan retries it.
    let didRead: Bool
}

/// Reads one photo, named by asset id rather than by `PHAsset`, so the
/// pipeline above it can be driven from a test — `PHAsset` cannot be
/// constructed, only fetched from a real library.
protocol SubjectVisionReading: Sendable {
    func observe(assetId: String, allowNetwork: Bool) async -> SubjectObservation
}

/// Counts faces and animals in a photo, from a small PhotoKit rendition.
///
/// Faces only, never identities: Vision has no public face-embedding request,
/// so an app cannot tell one person from another, let alone name them. This
/// answers "does this photo have people in it", which is what the API allows
/// and what the Collections tab promises.
struct SubjectVisionReader: SubjectVisionReading {
    /// Rendition edge. Faces below roughly 20px are missed either way, and a
    /// bigger rendition would mean decoding originals for a whole library.
    static let renditionEdge: CGFloat = 512

    func observe(assetId: String, allowNetwork: Bool) async -> SubjectObservation {
        // One fetch per photo, not per batch: it costs microseconds beside the
        // decode and the two Vision requests that follow it.
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetId]).first,
              asset.mediaType == .image,
              let image = await Self.rendition(for: asset, allowNetwork: allowNetwork),
              let cgImage = image.cgImage
        else {
            return SubjectObservation(
                assetId: assetId,
                faceCount: 0,
                animalCount: 0,
                didRead: false
            )
        }

        let faces = VNDetectFaceRectanglesRequest()
        let animals = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        // One handler, both requests: the image is decoded and prepared once.
        try? handler.perform([faces, animals])

        return SubjectObservation(
            assetId: assetId,
            faceCount: faces.results?.count ?? 0,
            animalCount: animals.results?.count ?? 0,
            didRead: true
        )
    }

    private static func rendition(for asset: PHAsset, allowNetwork: Bool) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // One callback, never a degraded-then-final pair, so the
            // continuation resumes exactly once.
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowNetwork
            options.version = .current
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: renditionEdge, height: renditionEdge),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
