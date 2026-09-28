import CoreGraphics
import CoreImage
import CoreML
import Foundation
import Vision

/// Works out a photo's depth when the capture stored none (FS-03.15e §3).
///
/// A protocol so the render path can be tested with a stand-in: the real
/// model is ~50MB and slow, and a test needs to count runs and make one fail.
public protocol DepthEstimating: Sendable {
    /// Normalised depth for `image`, as a gray picture: bright near, dark far.
    func depth(of image: CGImage) throws -> CGImage
}

/// Where a photo's Lens Blur depth comes from — what the group's header says.
public enum LensBlurDepth: Equatable, Sendable {
    /// Nothing asked for depth yet, or there is no estimator.
    case none
    /// The capture's own map (Portrait mode and the like).
    case captured
    /// Worked out by the bundled model, now or on an earlier open.
    case estimated
    /// The model could not do it; Lens Blur leaves the photo as shot.
    case failed
}

/// Depth Anything V2 Small, bundled as a compiled Core ML model.
///
/// The model answers with relative inverse depth — bigger is nearer, with no
/// fixed range — so the output is stretched to 0…1 by its own minimum and
/// maximum, the way a captured disparity map is.
public final class CoreMLDepthEstimator: DepthEstimating, @unchecked Sendable {

    /// The model's file name in the app bundle.
    public static let modelName = "DepthAnythingV2SmallF16"

    private let url: URL
    private let lock = NSLock()
    private var model: MLModel?

    public init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: Self.modelName, withExtension: "mlmodelc") else { return nil }
        self.url = url
    }

    public func depth(of image: CGImage) throws -> CGImage {
        let model = try loadedModel()
        let description = model.modelDescription
        guard let input = description.inputDescriptionsByName.first(where: { $0.value.type == .image }),
              let constraint = input.value.imageConstraint,
              let outputName = description.outputDescriptionsByName.keys.sorted().first
        else { throw PhotoEditingError.unavailable }

        let feature = try MLFeatureValue(cgImage: image, constraint: constraint, options: [
            .cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue,
        ])
        let provider = try MLDictionaryFeatureProvider(dictionary: [input.key: feature])
        let output = try model.prediction(from: provider)
        guard let value = output.featureValue(for: outputName) else { throw PhotoEditingError.unavailable }

        let raw: CIImage
        if let buffer = value.imageBufferValue {
            raw = CIImage(cvPixelBuffer: buffer)
        } else if let array = value.multiArrayValue {
            raw = try Self.image(from: array)
        } else {
            throw PhotoEditingError.unavailable
        }
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let normalized = PhotoRenderService.normalizedDisparity(raw, context: context)
        guard let cgImage = context.createCGImage(
            normalized, from: normalized.extent.integral, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()
        ) else { throw PhotoEditingError.cannotRender }
        return cgImage
    }

    private func loadedModel() throws -> MLModel {
        lock.lock()
        defer { lock.unlock() }
        if let model { return model }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = try MLModel(contentsOf: url, configuration: configuration)
        model = loaded
        return loaded
    }

    /// A 2-D (or 1×H×W) float array as a one-channel float image.
    private static func image(from array: MLMultiArray) throws -> CIImage {
        let shape = array.shape.map(\.intValue)
        guard shape.count >= 2 else { throw PhotoEditingError.unavailable }
        let height = shape[shape.count - 2], width = shape[shape.count - 1]
        var values = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            values[index] = array[index].floatValue
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: width * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .Rf,
            colorSpace: nil
        )
        // Array rows run top-down; Core Image's y runs up.
        .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(height)))
    }
}
