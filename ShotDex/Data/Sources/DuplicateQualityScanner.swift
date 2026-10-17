import CoreGraphics
import Foundation
import Photos
import UIKit
import Vision

/// Measures one grouped photo for the scoring pass (FS-06.06 §5–§6): a 512px
/// rendition for sharpness, clipping and faces, plus the EXIF block of a
/// local rendition for exposure compensation and Software. A protocol so the
/// pass can be driven by a stub in tests.
protocol DuplicateQualityReading: Sendable {
    /// `nil` when the photo is no longer in the library.
    func measure(assetId: String, allowNetwork: Bool) async -> DuplicateQualityRecord?
}

struct DuplicateQualityReader: DuplicateQualityReading {
    func measure(assetId: String, allowNetwork: Bool) async -> DuplicateQualityRecord? {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetId]).first else { return nil }
        return await measure(asset, allowNetwork: allowNetwork)
    }

    func measure(_ asset: PHAsset, allowNetwork: Bool) async -> DuplicateQualityRecord {
        async let exif = ExifReader().readExifFromLocalDerivative(for: asset)
        var score = DuplicateQualityScore(sharpness: nil)
        if let image = await Self.rendition(for: asset, allowNetwork: allowNetwork), let cgImage = image.cgImage {
            score = Self.score(cgImage)
        }
        var raw: RawExif?
        if case .success(let read) = await exif { raw = read }
        return DuplicateQualityRecord(
            assetId: asset.localIdentifier,
            modificationDate: asset.modificationDate.map { Int($0.timeIntervalSince1970) },
            score: score,
            exposureBias: raw?.exposureBias,
            software: raw?.software,
            scoredAt: Int(Date().timeIntervalSince1970)
        )
    }

    /// Luma measures plus faces. Runs off the main actor; no pixels kept.
    static func score(_ image: CGImage) -> DuplicateQualityScore {
        let width = image.width, height = image.height
        var luma = [UInt8](repeating: 0, count: width * height)
        let drawn = luma.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return DuplicateQualityScore(sharpness: nil) }
        var score = DuplicateQuality.measure(luma: luma, width: width, height: height)
        let faces = Self.faces(in: image)
        score.eyesOpen = faces.eyesOpen
        score.eyeConfidence = faces.confidence
        score.faceRect = faces.largest
        return score
    }

    /// A face smaller than this share of the image width is a bystander:
    /// its eyes say nothing about the shot.
    static let minimumFaceWidth = 0.08

    /// Eye openness from Vision's landmarks: the eye outline's height over
    /// its width, mapped so a closed eye is ~0 and an open one ~1. Vision has
    /// no "eyes closed" classifier; the landmark confidence is the gate, and
    /// the threshold (`DuplicateQuality.eyeConfidenceThreshold`) is set on
    /// the safe side until the device spike (§12) measures it.
    private static func faces(in image: CGImage) -> (eyesOpen: Double?, confidence: Double?, largest: CGRect?) {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let observations = request.results, !observations.isEmpty else {
            return (nil, nil, nil)
        }
        let subjects = observations.filter { $0.boundingBox.width >= minimumFaceWidth }
        var openness: [Double] = [], confidences: [Double] = []
        for face in subjects {
            guard let landmarks = face.landmarks,
                  let left = landmarks.leftEye.map(eyeRatio), let right = landmarks.rightEye.map(eyeRatio)
            else { continue }
            openness.append(min(1, max(0, (min(left, right) - 0.10) / 0.18)))
            confidences.append(Double(landmarks.confidence) * Double(face.confidence))
        }
        // Vision's box is bottom-left origin; the stored rect is top-left.
        let largest = observations.max { $0.boundingBox.width < $1.boundingBox.width }.map { face in
            CGRect(x: face.boundingBox.minX, y: 1 - face.boundingBox.maxY,
                   width: face.boundingBox.width, height: face.boundingBox.height)
        }
        guard let worst = openness.min(), let sure = confidences.min() else { return (nil, nil, largest) }
        return (worst, sure, largest)
    }

    private static func eyeRatio(_ region: VNFaceLandmarkRegion2D) -> Double {
        let points = region.normalizedPoints
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), maxX > minX
        else { return 0 }
        return Double((maxY - minY) / (maxX - minX))
    }

    private static func rendition(for asset: PHAsset, allowNetwork: Bool) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // One callback, so the continuation resumes exactly once.
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowNetwork
            options.version = .current
            let edge = CGFloat(DuplicateQuality.thumbnailEdge)
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: edge, height: edge), contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// Progress of the scoring pass, for "Checking sharpness…".
struct DuplicateScoringProgress: Equatable, Sendable {
    var processed: Int
    var total: Int
}

/// The scoring pass (FS-06.06 §3 step 5): only photos already in a group,
/// written in small batches so a cancel keeps what was scored, one photo at
/// a time while the user is scrolling or the device is warm (NF-01 rule 5).
actor DuplicateQualityPass {
    static let batchSize = 24

    private let store: DuplicateQualityStore
    private let reader: any DuplicateQualityReading
    private let shouldPause: @Sendable () -> Bool
    private var isRunning = false

    init(store: DuplicateQualityStore, reader: any DuplicateQualityReading, shouldPause: @escaping @Sendable () -> Bool) {
        self.store = store
        self.reader = reader
        self.shouldPause = shouldPause
    }

    /// Scores what `groups` still lacks. Cancel by cancelling the calling
    /// task; the photo in flight finishes, its batch is written, and the run
    /// returns. `onBatch` hands over each written batch.
    func run(
        groups: [DuplicateGroup],
        allowNetwork: Bool,
        onBatch: @escaping @Sendable ([DuplicateQualityRecord], DuplicateScoringProgress) -> Void
    ) async throws {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        try store.pruneOrphans()
        let ids = groups.filter { $0.kind != .screenshots }.flatMap { $0.members.map(\.assetId) }
        let pending = try store.pendingAssetIds(among: ids, retryingFailed: allowNetwork)
        var processed = 0
        for start in stride(from: 0, to: pending.count, by: Self.batchSize) {
            if Task.isCancelled { return }
            let batch = Array(pending[start..<min(start + Self.batchSize, pending.count)])
            var records: [DuplicateQualityRecord] = []
            for assetId in batch {
                if Task.isCancelled { break }
                while shouldPause() || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                    try? await Task.sleep(for: .milliseconds(300))
                    if Task.isCancelled { break }
                }
                if Task.isCancelled { break }
                if let record = await reader.measure(assetId: assetId, allowNetwork: allowNetwork) {
                    records.append(record)
                }
            }
            try store.upsert(records)
            processed += records.count
            onBatch(records, DuplicateScoringProgress(processed: processed, total: pending.count))
        }
    }
}
