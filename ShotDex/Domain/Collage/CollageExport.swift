import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Output size choices on the Export screen (§12).
enum CollageExportSize: String, CaseIterable, Identifiable, Sendable {
    case fit, k2, k4, max
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: "Fit"
        case .k2: "2K"
        case .k4: "4K"
        case .max: "Max"
        }
    }

    /// Long-edge cap in pixels.
    var longEdge: CGFloat {
        switch self {
        case .fit: 1600
        case .k2: 2048
        case .k4: 4096
        case .max: 8192
        }
    }
}

enum CollageExportFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, heic
    var id: String { rawValue }
    var displayName: String { self == .jpeg ? "JPEG" : "HEIC" }
    var fileExtension: String { self == .jpeg ? "jpg" : "heic" }
    var utType: UTType { self == .jpeg ? .jpeg : .heic }
}

/// The five Export-screen decisions, in one payload (§12).
struct CollageExportOptions: Equatable, Sendable {
    var size: CollageExportSize = .k2
    /// 0…100.
    var quality: Double = 90
    var format: CollageExportFormat = .jpeg
    var keepFirstPhotoEXIF: Bool = false
}

/// Encodes the composited collage bitmap to JPEG/HEIC at a quality, optionally
/// carrying the first photo's metadata forward (§12). Pure ImageIO so it stays
/// off the main actor and testable.
enum CollageImageEncoder {
    static func encode(
        _ image: CGImage,
        format: CollageExportFormat,
        quality: Double,
        metadata: [CFString: Any]? = nil
    ) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, format.utType.identifier as CFString, 1, nil
        ) else { return nil }
        var options: [CFString: Any] = metadata ?? [:]
        options[kCGImageDestinationLossyCompressionQuality] = max(0, min(1, quality / 100))
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A rough byte estimate for the "Estimated size" readout, without encoding —
    /// good enough for a `~` figure that tracks the sliders (§12).
    static func estimatedBytes(pixelSize: CGSize, format: CollageExportFormat, quality: Double) -> Int {
        let pixels = Double(pixelSize.width * pixelSize.height)
        let q = max(0, min(1, quality / 100))
        // JPEG bytes-per-pixel climbs steeply near q=1; HEIC is roughly half.
        let jpegBPP = 0.05 + q * q * 0.9
        let bpp = format == .heic ? jpegBPP * 0.55 : jpegBPP
        return Int(pixels * bpp)
    }
}
