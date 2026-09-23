import CoreImage
import Foundation
import ImageIO

/// One distortion calibration of a lens at one focal length, as Lensfun
/// records it.
public struct LensDistortionTerm: Codable, Equatable, Sendable {
    public enum Model: String, Codable, Sendable {
        case poly3
        case poly5
        case ptlens
    }

    public var model: Model
    public var focal: Double
    public var k1: Double?
    public var k2: Double?
    public var a: Double?
    public var b: Double?
    public var c: Double?

    public init(model: Model, focal: Double, k1: Double? = nil, k2: Double? = nil, a: Double? = nil, b: Double? = nil, c: Double? = nil) {
        self.model = model
        self.focal = focal
        self.k1 = k1
        self.k2 = k2
        self.a = a
        self.b = b
        self.c = c
    }

    /// `r_d / r_u` at undistorted radius `r` — the Lensfun formulas, in the
    /// PTLens convention where r = 1 is half the calibration frame's short side.
    public func scale(at r: Double) -> Double {
        switch model {
        case .poly3:
            let k1 = k1 ?? 0
            return 1 - k1 + k1 * r * r
        case .poly5:
            return 1 + (k1 ?? 0) * r * r + (k2 ?? 0) * r * r * r * r
        case .ptlens:
            let a = a ?? 0, b = b ?? 0, c = c ?? 0
            return a * r * r * r + b * r * r + c * r + 1 - a - b - c
        }
    }
}

/// A lens in the embedded Lensfun table. Strings are Lensfun's own, unchanged.
public struct LensfunLens: Codable, Equatable, Identifiable, Sendable {
    public var maker: String
    public var model: String
    public var aliases: [String]
    public var mounts: [String]
    public var cropFactor: Double
    public var aspectRatio: String?
    public var distortion: [LensDistortionTerm]

    /// Stable across table rebuilds as long as Lensfun keeps the name. The
    /// crop factor is part of it because Lensfun lists the same lens once per
    /// calibration body (a DX and an FX measurement of one Nikkor).
    public var id: String { "\(maker)|\(model)|\(cropFactor)" }

    /// The name to show: Lensfun's model string, with the maker in front when
    /// the model does not already start with it ("XF23mmF1.4 R" is a Fujifilm).
    public var displayName: String {
        model.lowercased().hasPrefix(maker.lowercased()) ? model : "\(maker) \(model)"
    }

    /// Long side over short side of the frame the lens was calibrated on —
    /// Lensfun's `<aspect-ratio>`, 3:2 when the database does not say.
    public var calibrationAspect: Double {
        guard let aspectRatio else { return 1.5 }
        let parts = aspectRatio.split(separator: ":").compactMap { Double($0) }
        if parts.count == 2, parts[0] > 0, parts[1] > 0 {
            return max(parts[0], parts[1]) / min(parts[0], parts[1])
        }
        return Double(aspectRatio).map { max($0, 1 / $0) } ?? 1.5
    }

    /// The calibration for `focal`, interpolated linearly between the two
    /// nearest measured focal lengths of the same model — a zoom is rarely
    /// calibrated at the exact millimetre a photo was taken at.
    public func distortion(atFocal focal: Double) -> LensDistortionTerm? {
        guard let first = distortion.first else { return nil }
        let sorted = distortion.sorted { $0.focal < $1.focal }
        if focal <= first.focal || sorted.count == 1 { return sorted.first }
        if let last = sorted.last, focal >= last.focal { return last }
        guard let upperIndex = sorted.firstIndex(where: { $0.focal >= focal }), upperIndex > 0 else {
            return sorted.first
        }
        let lower = sorted[upperIndex - 1], upper = sorted[upperIndex]
        guard lower.model == upper.model, upper.focal > lower.focal else {
            return abs(focal - lower.focal) <= abs(upper.focal - focal) ? lower : upper
        }
        let t = (focal - lower.focal) / (upper.focal - lower.focal)
        func mix(_ x: Double?, _ y: Double?) -> Double? {
            guard x != nil || y != nil else { return nil }
            return (x ?? 0) + ((y ?? 0) - (x ?? 0)) * t
        }
        return LensDistortionTerm(
            model: lower.model,
            focal: focal,
            k1: mix(lower.k1, upper.k1),
            k2: mix(lower.k2, upper.k2),
            a: mix(lower.a, upper.a),
            b: mix(lower.b, upper.b),
            c: mix(lower.c, upper.c)
        )
    }
}

/// A camera body in the embedded Lensfun table: which mount, which crop.
public struct LensfunCamera: Codable, Equatable, Sendable {
    public var maker: String
    public var aliases: [String]
    public var mount: String
    public var cropFactor: Double
}

/// The embedded Lensfun distortion table (`Resources/lensfun-distortion.json`,
/// built by `Tools/lensfun-to-json.py`). Lensfun is CC-BY-SA 3.0; the table is
/// a verbatim subset, and everything ShotDex adds — matching EXIF to a row —
/// lives outside it.
public final class LensProfileLibrary: Sendable {
    public static let shared = LensProfileLibrary()

    public let lenses: [LensfunLens]
    public let cameras: [LensfunCamera]
    private let lensesByID: [String: LensfunLens]

    private struct Payload: Decodable {
        var cameras: [LensfunCamera]
        var lenses: [LensfunLens]
    }

    private final class BundleMarker {}

    init(data: Data? = nil) {
        let data = data ?? Bundle(for: BundleMarker.self)
            .url(forResource: "lensfun-distortion", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        let payload = data.flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        lenses = payload?.lenses ?? []
        cameras = payload?.cameras ?? []
        lensesByID = Dictionary(lenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func lens(id: String) -> LensfunLens? { lensesByID[id] }

    /// The body EXIF names, matched case-insensitively on maker and any alias.
    public func camera(make: String?, model: String?) -> LensfunCamera? {
        guard let model = model?.trimmingCharacters(in: .whitespaces).lowercased(), !model.isEmpty else { return nil }
        let make = make?.trimmingCharacters(in: .whitespaces).lowercased()
        return cameras.first { camera in
            (make == nil || camera.maker.lowercased() == make)
                && camera.aliases.contains { $0.lowercased() == model }
        }
    }
}

extension PhotoRenderService {
    /// The focal length the photo was taken at, from its EXIF.
    public static func exifFocalLength(_ properties: [CFString: Any]) -> Double? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        return (exif?[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue
    }

    /// How many pixels of this photo one unit of Lensfun radius is.
    ///
    /// Lensfun keeps Hugin's convention: r = 1 is half the **short side of the
    /// calibration frame** — a sensor of the lens's crop factor at the
    /// calibration aspect ratio (Lensfun's `rescale_polynomial_coefficients`).
    /// Measured in millimetres through the diagonal, so a body with another
    /// crop factor, or a photo with another aspect ratio (a 4:3 frame against a
    /// 3:2 calibration), lands on the right part of the calibrated field:
    /// halfDiagonal(px) · cameraCrop / (lensCrop · hypot(calibrationAspect, 1)).
    public static func lensNormalizationRadius(
        extent: CGRect,
        lensCropFactor: Double,
        cameraCropFactor: Double,
        calibrationAspect: Double
    ) -> Double {
        let halfDiagonal = (extent.width * extent.width + extent.height * extent.height).squareRoot() / 2
        return halfDiagonal * max(0.1, cameraCropFactor)
            / (max(0.1, lensCropFactor) * (calibrationAspect * calibrationAspect + 1).squareRoot())
    }

    /// Corrects lens distortion with a Lensfun profile, for sources the RAW
    /// decoder does not already correct. The corrected frame is zoomed just
    /// enough that no corner or edge samples outside the photo — the
    /// "constrain crop" Lightroom applies — so a barrel correction never shows
    /// empty corners.
    public static func applyLensProfile(
        _ term: LensDistortionTerm,
        lensCropFactor: Double,
        cameraCropFactor: Double,
        calibrationAspect: Double = 1.5,
        to input: CIImage
    ) -> CIImage {
        guard let kernel = lensWarpKernel else { return input }
        let extent = input.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let norm = lensNormalizationRadius(
            extent: extent,
            lensCropFactor: lensCropFactor,
            cameraCropFactor: cameraCropFactor,
            calibrationAspect: calibrationAspect
        )
        let zoom = fillZoom(term, extent: extent, norm: norm)
        let model: Float = switch term.model {
        case .poly3: 0
        case .poly5: 1
        case .ptlens: 2
        }
        let output = kernel.apply(
            extent: extent,
            roiCallback: { _, rect in
                // Distortion moves pixels by a few percent of the frame; the
                // whole source is small enough at preview size to just ask for.
                rect.union(extent).insetBy(dx: -8, dy: -8)
            },
            image: input.clampedToExtent(),
            arguments: [
                CIVector(x: center.x, y: center.y),
                Float(norm),
                Float(zoom),
                model,
                Float(term.k1 ?? 0), Float(term.k2 ?? 0),
                Float(term.a ?? 0), Float(term.b ?? 0), Float(term.c ?? 0),
            ]
        )
        return output?.cropped(to: extent) ?? input
    }

    /// The smallest zoom ≥ 1 at which the corners and edge midpoints of the
    /// corrected frame all sample inside the photo. An output point p samples
    /// the source at p · g(r) / zoom, with r = |p| / (norm · zoom), so it stays
    /// inside when zoom ≥ g(r); iterated because r depends on the zoom.
    static func fillZoom(_ term: LensDistortionTerm, extent: CGRect, norm: Double) -> Double {
        let halfW = extent.width / 2, halfH = extent.height / 2
        let radii = [
            (halfW * halfW + halfH * halfH).squareRoot(), halfW, halfH,
        ]
        var zoom = 1.0
        for _ in 0..<6 {
            zoom = max(1, radii.map { term.scale(at: $0 / (norm * zoom)) }.max() ?? 1)
        }
        return min(zoom, 1.5)
    }

    static let lensWarpKernel = CIWarpKernel(source: """
        kernel vec2 lensWarp(vec2 center, float norm, float zoom, float model,
                             float k1, float k2, float a, float b, float c) {
            vec2 d = (destCoord() - center) / (norm * zoom);
            float r = length(d);
            float g;
            if (model < 0.5) {
                g = 1.0 - k1 + k1 * r * r;
            } else if (model < 1.5) {
                g = 1.0 + k1 * r * r + k2 * r * r * r * r;
            } else {
                g = a * r * r * r + b * r * r + c * r + 1.0 - a - b - c;
            }
            return center + d * g * norm;
        }
        """)
}
