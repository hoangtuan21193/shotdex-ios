import CoreImage
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// One frame of an HDR series as a file on this device (FS-01.11 §5).
struct HDRFrameFile: Equatable, Sendable {
    var url: URL
    var isRAW: Bool
    var shutterSeconds: Double?
    var iso: Double?
    var aperture: Double?
    var exposureBias: Double?
}

/// Reads the frames of an HDR series linear: a RAW through the decoder with
/// no tone curve, a JPEG or HEIC with its sRGB curve undone — the latter is
/// what Core Image's colour management does on the way in.
enum HDRFrameSource {
    /// Long edge of a preview frame, as for Focus Stack.
    static let previewEdge = 1600

    // MARK: Files

    /// The file a frame merges from, written into `folder`: a server photo's
    /// RAW companion when it has one, a library photo's RAW resource when it
    /// has one (a RAW+JPEG pair merges from the RAW), otherwise the photo's
    /// current rendition.
    static func file(for photo: PhotoEditOrigin, in folder: URL, index: Int) async throws -> HDRFrameFile? {
        switch photo {
        case .serverFile(let server):
            return frameFile(at: server.rawURL ?? server.primaryURL)
        case .asset(let asset):
            let resources = PHAssetResource.assetResources(for: asset)
            if let raw = resources.first(where: { isRAW($0) && [.photo, .alternatePhoto].contains($0.type) }) {
                let url = folder.appendingPathComponent(String(format: "hdr-%04d.%@", index,
                                                               (raw.originalFilename as NSString).pathExtension))
                try await write(resource: raw, to: url)
                return frameFile(at: url)
            }
            guard let data = await PhotoStackModel.originalData(for: asset) else { return nil }
            let url = folder.appendingPathComponent(String(format: "hdr-%04d", index))
            try data.write(to: url)
            return frameFile(at: url)
        }
    }

    /// Kind and exposure of a file on disk, from its own metadata.
    static func frameFile(at url: URL) -> HDRFrameFile? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let type = (CGImageSourceGetType(source) as String?).flatMap(UTType.init) ?? .image
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        func number(_ key: CFString) -> Double? {
            if let value = exif[key] as? Double { return value }
            if let values = exif[key] as? [Double] { return values.first }
            return nil
        }
        return HDRFrameFile(
            url: url,
            isRAW: type.conforms(to: .rawImage),
            shutterSeconds: number(kCGImagePropertyExifExposureTime),
            // Canon's CR3 leaves ISOSpeedRatings out and writes ISOSpeed and
            // RecommendedExposureIndex (sensitivity type 2).
            iso: number(kCGImagePropertyExifISOSpeedRatings) ?? number(kCGImagePropertyExifISOSpeed)
                ?? number(kCGImagePropertyExifRecommendedExposureIndex)
                ?? number(kCGImagePropertyExifStandardOutputSensitivity),
            aperture: number(kCGImagePropertyExifFNumber),
            exposureBias: number(kCGImagePropertyExifExposureBiasValue)
        )
    }

    // MARK: Decoding

    /// A frame as linear light in Core Image's working space, clipping at 1,
    /// at most `maxPixelSize` on the long edge (nil for full size), with its
    /// orientation applied. `fromRAW` false reads a RAW like a processed
    /// photo — through the decoder's own tone curve — for a series that is
    /// not all RAW (FS-01.11 §5).
    static func linearImage(of file: HDRFrameFile, fromRAW: Bool, maxPixelSize: Int?) -> CIImage? {
        if file.isRAW {
            guard let raw = CIRAWFilter(imageURL: file.url) else { return nil }
            if fromRAW { raw.boostAmount = 0 }
            if let maxPixelSize {
                let native = raw.nativeSize
                let edge = max(native.width, native.height)
                if edge > CGFloat(maxPixelSize) { raw.scaleFactor = Float(CGFloat(maxPixelSize) / edge) }
            }
            return raw.outputImage.map(atOrigin)
        }
        if let maxPixelSize {
            guard let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  ] as CFDictionary)
            else { return nil }
            return CIImage(cgImage: thumbnail)
        }
        return CIImage(contentsOf: file.url, options: [.applyOrientationProperty: true]).map(atOrigin)
    }

    /// Frame pixels per sensor pixel for a preview of this file.
    static func pixelScale(of file: HDRFrameFile, image: CIImage) -> Double {
        let native: CGSize
        if file.isRAW, let raw = CIRAWFilter(imageURL: file.url) {
            native = raw.nativeSize
        } else if let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Double,
                  let height = properties[kCGImagePropertyPixelHeight] as? Double {
            native = CGSize(width: width, height: height)
        } else {
            return 1
        }
        let edge = max(native.width, native.height)
        guard edge > 0 else { return 1 }
        return min(1, max(image.extent.width, image.extent.height) / edge)
    }

    /// log₂ of a frame's median luminance, for a series whose EXIF says
    /// nothing about exposure (FS-01.11 §4).
    static func medianLog2Luminance(of image: CIImage, context: CIContext) -> Double? {
        let side = 64
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let small = image.transformed(by: CGAffineTransform(scaleX: CGFloat(side) / extent.width,
                                                            y: CGFloat(side) / extent.height))
        var pixels = [Float](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(small, toBitmap: bytes.baseAddress!, rowBytes: side * 16,
                           bounds: CGRect(x: small.extent.minX, y: small.extent.minY, width: CGFloat(side), height: CGFloat(side)),
                           format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        }
        let luma = (0..<(side * side)).map { i in
            0.2126 * Double(pixels[i * 4]) + 0.7152 * Double(pixels[i * 4 + 1]) + 0.0722 * Double(pixels[i * 4 + 2])
        }.sorted()
        return log2(max(luma[luma.count / 2], 1e-6))
    }

    // MARK: Pieces

    private static func atOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    private static func isRAW(_ resource: PHAssetResource) -> Bool {
        let type = UTType(resource.uniformTypeIdentifier)
            ?? UTType(filenameExtension: (resource.originalFilename as NSString).pathExtension)
        return type?.conforms(to: .rawImage) ?? false
    }

    private static func write(resource: PHAssetResource, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}

extension HDRFrameFile {
    /// What the bracket order reads of this frame.
    func orderFrame<ID: Hashable>(id: ID, measuredLog2Brightness: Double? = nil) -> HDRBracketOrder.Frame<ID> {
        HDRBracketOrder.Frame(id: id, shutterSeconds: shutterSeconds, iso: iso, aperture: aperture,
                              exposureBias: exposureBias, isRAW: isRAW, measuredLog2Brightness: measuredLog2Brightness)
    }
}
