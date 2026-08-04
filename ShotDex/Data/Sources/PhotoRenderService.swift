import Accelerate
import CoreImage
import CoreML
import ImageIO
import UniformTypeIdentifiers
import Vision

struct PhotoRenderSourceInfo: @unchecked Sendable {
    let url: URL
    let type: UTType
    let pixelWidth: Int
    let pixelHeight: Int
    let orientation: CGImagePropertyOrientation
    let isRAW: Bool
    let properties: [CFString: Any]
}

struct PhotoRenderResult {
    let image: CIImage
    let colorSpace: CGColorSpace
    let properties: [CFString: Any]
}

struct ResolvedAutomaticMasks: @unchecked Sendable {
    let images: [UUID: CGImage]
}

struct ResolvedMaskThumbnails: @unchecked Sendable {
    let images: [UUID: CGImage]
}

struct ResolvedFilterThumbnails: @unchecked Sendable {
    let images: [PhotoFilter: CGImage]
}

struct PhotoRenderPreview: @unchecked Sendable {
    let displayImage: CGImage
    let cleanImage: CGImage
}

/// Core Image render graph shared by the editor, single-photo compression and
/// bulk export. The actor owns one CIContext and the Core ML model so neither is
/// repeatedly constructed while sliders move.
actor PhotoRenderService {
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .name: "ShotDex Photo Renderer",
    ])

    private struct RAWBaseSignature: Equatable {
        let exposure: Double
        let temperature: Double
        let tint: Double
        let luminanceNoise: Double
        let colorNoise: Double
        let sharpness: Double
        let lensCorrection: Double
    }

    private struct InteractiveBaseCache {
        let sourceURL: URL
        let rawSignature: RAWBaseSignature?
        let image: CGImage
        let colorSpace: CGColorSpace
    }

    private var interactiveBaseCache: InteractiveBaseCache?
    private var skyModel: MLModel?
    private var automaticMaskCache: [String: CIImage] = [:]
    private var automaticMaskCacheOrder: [String] = []
    private static let automaticMaskCacheCapacity = 8

    static let addMaskKernel = CIColorKernel(source: """
        kernel vec4 addMask(__sample current, __sample incoming) {
            float value = max(current.r, incoming.r * incoming.a);
            return vec4(value, value, value, 1.0);
        }
        """)

    static let subtractMaskKernel = CIColorKernel(source: """
        kernel vec4 subtractMask(__sample current, __sample incoming) {
            float value = max(0.0, current.r - incoming.r * incoming.a);
            return vec4(value, value, value, 1.0);
        }
        """)

    static let invertMaskKernel = CIColorKernel(source: """
        kernel vec4 invertMask(__sample value) {
            float result = 1.0 - value.r;
            return vec4(result, result, result, 1.0);
        }
        """)

    static let luminanceMaskKernel = CIColorKernel(source: """
        kernel vec4 luminanceMask(__sample color, float lower, float upper, float feather) {
            float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
            float edge = max(0.001, feather);
            float low = smoothstep(lower - edge, lower + edge, luminance);
            float high = 1.0 - smoothstep(upper - edge, upper + edge, luminance);
            float value = clamp(low * high, 0.0, 1.0);
            return vec4(value, value, value, 1.0);
        }
        """)

    static let colorMaskKernel = CIColorKernel(source: """
        kernel vec4 colorMask(__sample color, vec3 target, float tolerance, float feather) {
            float distance = length(color.rgb - target);
            float edge = max(0.001, feather);
            float value = 1.0 - smoothstep(tolerance - edge, tolerance + edge, distance);
            return vec4(value, value, value, 1.0);
        }
        """)

    func inspectSource(at url: URL, typeHint: UTType? = nil) throws -> PhotoRenderSourceInfo {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let rawProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any]
        else {
            throw PhotoEditingError.cannotDecode
        }

        let detectedType = CGImageSourceGetType(source)
            .flatMap { UTType($0 as String) }
            ?? typeHint
            ?? .image
        let width = (rawProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (rawProperties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientationRaw =
            (rawProperties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up
        let isRAW = detectedType.conforms(to: .rawImage)

        if isRAW, CIRAWFilter(imageURL: url) == nil {
            throw PhotoEditingError.unsupportedRAW
        }

        return PhotoRenderSourceInfo(
            url: url,
            type: detectedType,
            pixelWidth: width,
            pixelHeight: height,
            orientation: orientation,
            isRAW: isRAW,
            properties: rawProperties
        )
    }

    func renderPreview(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat,
        showsMaskOverlay: Bool = false,
        selectedMaskID: UUID? = nil
    ) throws -> CGImage {
        try renderPreviewImages(
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension,
            showsMaskOverlay: showsMaskOverlay,
            selectedMaskID: selectedMaskID
        ).displayImage
    }

    func renderPreviewImages(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat,
        showsMaskOverlay: Bool = false,
        selectedMaskID: UUID? = nil
    ) throws -> PhotoRenderPreview {
        let result = try renderPhoto(
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension
        )
        return try makePreviewImages(
            result: result,
            source: source,
            recipe: recipe,
            showsMaskOverlay: showsMaskOverlay,
            selectedMaskID: selectedMaskID
        )
    }

    func installInteractiveBase(
        _ image: CGImage,
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe
    ) {
        interactiveBaseCache = InteractiveBaseCache(
            sourceURL: source.url,
            rawSignature: rawBaseSignature(source: source, recipe: recipe),
            image: image,
            colorSpace: preservedColorSpace(
                from: source.properties,
                isRAW: source.isRAW
            )
        )
    }

    func renderInteractivePreviewImages(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat,
        cachesBase: Bool,
        showsMaskOverlay: Bool = false,
        selectedMaskID: UUID? = nil
    ) throws -> PhotoRenderPreview {
        let baseResult = try makeInteractiveBaseImage(
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension,
            cachesBase: cachesBase
        )
        let result = try render(
            baseResult: baseResult,
            source: source,
            recipe: recipe,
            maximumDimension: nil
        )
        return try makePreviewImages(
            result: result,
            source: source,
            recipe: recipe,
            showsMaskOverlay: showsMaskOverlay,
            selectedMaskID: selectedMaskID
        )
    }

    private func makePreviewImages(
        result: PhotoRenderResult,
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        showsMaskOverlay: Bool,
        selectedMaskID: UUID?
    ) throws -> PhotoRenderPreview {
        guard let cleanImage = context.createCGImage(
            result.image,
            from: result.image.extent,
            format: .RGBA8,
            colorSpace: result.colorSpace
        ) else {
            throw PhotoEditingError.cannotRender
        }
        var display = result.image
        var isDisplayDistinct = false

        if showsMaskOverlay,
           let selectedMaskID,
           let mask = recipe.masks.first(where: { $0.id == selectedMaskID }),
           let renderedMask = try renderMask(
               mask,
               over: result.image,
               rawSkyMatte: nil,
               cacheIdentity: maskCacheIdentity(source: source, recipe: recipe)
           ) {
            // The tint answers "where is the mask", not "is its effect on" — it
            // shows whenever the overlay is asked for, even with the effect
            // unticked. The controller hides the overlay at the moment the effect
            // is switched off, so an eye that is lit is always an explicit request.
            // (An earlier build refused to tint an effect-off mask instead, which
            // made the eye a button that sometimes did nothing.)
            display = overlayMask(renderedMask, on: display)
            isDisplayDistinct = true
        }

        // The drawing and overlays land on the display copy only, and after the
        // mask tint: the clean copy is what the eyedropper samples and what the
        // histogram is built from, and neither a scribble nor a caption is part of
        // the photo's exposure. Drawing first so a caption stays legible over it.
        if recipe.drawing?.hasVisibleEffect == true {
            display = Self.applyDrawing(recipe.drawing, to: display)
            isDisplayDistinct = true
        }
        if !recipe.overlays.isEmpty {
            display = Self.applyOverlays(recipe.overlays, to: display)
            isDisplayDistinct = true
        }

        guard isDisplayDistinct else {
            return PhotoRenderPreview(
                displayImage: cleanImage,
                cleanImage: cleanImage
            )
        }
        guard let displayImage = context.createCGImage(
            display,
            from: display.extent,
            format: .RGBA8,
            colorSpace: result.colorSpace
        ) else {
            throw PhotoEditingError.cannotRender
        }
        return PhotoRenderPreview(
            displayImage: displayImage,
            cleanImage: cleanImage
        )
    }

    /// The finished photo, overlays included — every path that writes a file goes
    /// through here, so a saved photo can never be missing its watermark.
    ///
    /// The overlay composite lives here rather than inside `render(baseResult:)` so
    /// the preview path can keep an overlay-free copy: the eyedropper and the
    /// histogram read the *photo*, and a white credit line would otherwise be
    /// sampled as a colour and spike the highlight end of the histogram.
    func render(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat? = nil
    ) throws -> PhotoRenderResult {
        let result = try renderPhoto(
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension
        )
        let hasDrawing = recipe.drawing?.hasVisibleEffect ?? false
        guard hasDrawing || !recipe.overlays.isEmpty else { return result }
        // Drawing first, then the text/signature overlays on top of it.
        var image = Self.applyDrawing(recipe.drawing, to: result.image)
        image = Self.applyOverlays(recipe.overlays, to: image)
        return PhotoRenderResult(
            image: image,
            colorSpace: result.colorSpace,
            properties: result.properties
        )
    }

    /// Everything except the overlays.
    private func renderPhoto(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat? = nil
    ) throws -> PhotoRenderResult {
        let baseResult = try makeBaseImage(
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension
        )
        return try render(
            baseResult: baseResult,
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension
        )
    }

    private func render(
        baseResult: BaseImageResult,
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat?
    ) throws -> PhotoRenderResult {
        let unadjusted = baseResult.image
        var image = Self.applyAdjustments(
            recipe.adjustments,
            to: unadjusted,
            appliesExposure: !source.isRAW
        )
        image = Self.applyColor(recipe.color, to: image)
        image = Self.applyFilter(
            recipe.filter,
            intensity: recipe.filterIntensity,
            to: image
        )
        image = Self.applyCrop(recipe.crop, to: image)
        let croppedRawSkyMatte = baseResult.rawSkyMatte.map {
            Self.applyCrop(recipe.crop, to: $0)
        }
        let cacheIdentity = maskCacheIdentity(source: source, recipe: recipe)

        for mask in recipe.masks where mask.isVisible {
            guard let maskImage = try renderMask(
                mask,
                over: image,
                rawSkyMatte: croppedRawSkyMatte,
                cacheIdentity: cacheIdentity
            ) else { continue }
            let adjusted = Self.applyAdjustments(
                mask.adjustments,
                to: image,
                appliesExposure: true
            )
            image = blend(adjusted: adjusted, original: image, mask: maskImage)
        }

        if let maximumDimension {
            image = scaleDown(image, maximumDimension: maximumDimension)
        }
        image = image.transformed(by:
            CGAffineTransform(
                translationX: -image.extent.origin.x,
                y: -image.extent.origin.y
            )
        )
        return PhotoRenderResult(
            image: image,
            colorSpace: baseResult.colorSpace,
            properties: source.properties
        )
    }

    func resize(
        _ result: PhotoRenderResult,
        preset: ResizePreset,
        cropAnchor: NormalizedPoint
    ) -> PhotoRenderResult {
        let sourceExtent = result.image.extent.integral
        let target = preset.targetPixelSize(
            sourceWidth: Int(sourceExtent.width),
            sourceHeight: Int(sourceExtent.height)
        )
        guard target.width > 0, target.height > 0 else { return result }

        let output: CIImage
        switch preset.kind {
        case .original:
            output = result.image
        case .longEdge:
            let scale = min(
                target.width / sourceExtent.width,
                target.height / sourceExtent.height
            )
            output = lanczosScale(result.image, scale: scale)
        case .exact:
            switch preset.cropMode {
            case .fit:
                let scale = min(
                    target.width / sourceExtent.width,
                    target.height / sourceExtent.height
                )
                output = lanczosScale(result.image, scale: scale)
            case .fill:
                let scale = max(
                    target.width / sourceExtent.width,
                    target.height / sourceExtent.height
                )
                let scaled = lanczosScale(result.image, scale: scale)
                let overflowX = max(0, scaled.extent.width - target.width)
                let overflowY = max(0, scaled.extent.height - target.height)
                let cropX = scaled.extent.minX + overflowX * cropAnchor.x
                let cropY = scaled.extent.minY + overflowY * (1 - cropAnchor.y)
                output = scaled.cropped(
                    to: CGRect(x: cropX, y: cropY, width: target.width, height: target.height)
                )
            }
        }

        let normalized = output.transformed(by:
            CGAffineTransform(
                translationX: -output.extent.minX,
                y: -output.extent.minY
            )
        )
        return PhotoRenderResult(
            image: normalized,
            colorSpace: result.colorSpace,
            properties: result.properties
        )
    }

    func write(
        _ result: PhotoRenderResult,
        to url: URL,
        format: PhotoOutputFormat,
        quality: Double,
        includeMetadata: Bool
    ) throws {
        let resolvedFormat = format == .preserve ? .jpeg : format
        guard let cgImage = context.createCGImage(
            result.image,
            from: result.image.extent,
            format: .RGBA8,
            colorSpace: result.colorSpace
        ) else {
            throw PhotoEditingError.cannotRender
        }

        let type = resolvedFormat.uniformType.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type,
            1,
            nil
        ) else {
            throw PhotoEditingError.cannotEncode
        }
        var properties: [CFString: Any] = includeMetadata ? result.properties : [:]
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = cgImage.width
        properties[kCGImagePropertyPixelHeight] = cgImage.height
        properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0.1, quality))
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoEditingError.cannotEncode
        }
    }

    func estimatedEncodedByteCount(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        options: PhotoExportOptions
    ) throws -> Int {
        let encodedWidth = max(1, source.pixelWidth)
        let encodedHeight = max(1, source.pixelHeight)
        let originalSize: (width: Int, height: Int)
        switch source.orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            originalSize = (encodedHeight, encodedWidth)
        default:
            originalSize = (encodedWidth, encodedHeight)
        }
        let presetTarget = options.preset.targetPixelSize(
            sourceWidth: originalSize.width,
            sourceHeight: originalSize.height
        )
        let target: CGSize
        if options.preset.kind == .exact, options.preset.cropMode == .fit {
            let fitScale = min(
                presetTarget.width / CGFloat(originalSize.width),
                presetTarget.height / CGFloat(originalSize.height)
            )
            target = CGSize(
                width: max(1, (CGFloat(originalSize.width) * fitScale).rounded()),
                height: max(1, (CGFloat(originalSize.height) * fitScale).rounded())
            )
        } else {
            target = presetTarget
        }
        let proxyScale = min(1, 1_200 / max(1, max(target.width, target.height)))
        let proxyPreset = ResizePreset(
            name: "Estimate",
            kind: .exact,
            width: max(1, Int((target.width * proxyScale).rounded())),
            height: max(1, Int((target.height * proxyScale).rounded())),
            cropMode: options.preset.cropMode,
            quality: options.quality,
            format: options.format
        )
        let preview = try render(source: source, recipe: recipe, maximumDimension: 1_200)
        let previewResized = resize(
            preview,
            preset: proxyPreset,
            cropAnchor: options.cropAnchor
        )
        let resolvedFormat = resolvedOutputFormat(
            requested: options.format,
            sourceType: source.type,
            sourceIsRAW: source.isRAW
        )
        let data = NSMutableData()
        guard let cgImage = context.createCGImage(
            previewResized.image,
            from: previewResized.image.extent,
            format: .RGBA8,
            colorSpace: previewResized.colorSpace
        ), let destination = CGImageDestinationCreateWithData(
            data,
            resolvedFormat.uniformType.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoEditingError.cannotEncode
        }
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: options.quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoEditingError.cannotEncode
        }

        let targetPixels = max(1, target.width * target.height)
        let previewPixels = max(
            1,
            previewResized.image.extent.width * previewResized.image.extent.height
        )
        let ratio = pow(targetPixels / previewPixels, 0.82)
        let metadataOverhead: Int
        if options.includeMetadata,
           PropertyListSerialization.propertyList(
               source.properties,
               isValidFor: .binary
           ), let encoded = try? PropertyListSerialization.data(
               fromPropertyList: source.properties,
               format: .binary,
               options: 0
           ) {
            metadataOverhead = encoded.count
        } else {
            metadataOverhead = 0
        }
        return max(
            data.length,
            Int(Double(data.length) * ratio) + metadataOverhead
        )
    }

    func previewImage(
        _ result: PhotoRenderResult,
        maximumDimension: CGFloat = 1_800
    ) throws -> CGImage {
        let image = scaleDown(result.image, maximumDimension: maximumDimension)
        guard let cgImage = context.createCGImage(
            image,
            from: image.extent,
            format: .RGBA8,
            colorSpace: result.colorSpace
        ) else {
            throw PhotoEditingError.cannotRender
        }
        return cgImage
    }

    /// Samples the display histogram of the whole image. It is never scoped to a
    /// mask: the card has to keep describing the frame's exposure, otherwise it
    /// changes meaning the moment a mask is opened.
    func histogram(
        of image: CGImage,
        binCount: Int = 64
    ) -> PhotoHistogram {
        let count = max(16, min(256, binCount))
        let longestEdge = max(image.width, image.height)
        guard longestEdge > 0 else { return .empty }
        let sampleScale = min(1, 256 / CGFloat(longestEdge))
        let width = max(1, Int((CGFloat(image.width) * sampleScale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * sampleScale).rounded()))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let didDraw = pixels.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress,
                  let bitmapContext = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  )
            else {
                return false
            }
            bitmapContext.interpolationQuality = .low
            bitmapContext.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard didDraw else {
            return .empty
        }

        var red = [Double](repeating: 0, count: count)
        var green = [Double](repeating: 0, count: count)
        var blue = [Double](repeating: 0, count: count)
        var sampleCount = 0.0
        var clippedHighlights = 0.0
        var clippedShadows = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let b = Int(pixels[offset + 2])
            red[min(count - 1, r * count / 256)] += 1
            green[min(count - 1, g * count / 256)] += 1
            blue[min(count - 1, b * count / 256)] += 1
            sampleCount += 1
            if r >= 254 || g >= 254 || b >= 254 { clippedHighlights += 1 }
            if r <= 1, g <= 1, b <= 1 { clippedShadows += 1 }
        }
        guard sampleCount > 0 else { return .empty }

        // A white wall or clipped highlight can dominate one bin. Lightroom-
        // style display histograms clip rare peaks and use a perceptual curve
        // so the rest of the tonal distribution remains readable.
        let populatedBins = (red + green + blue).filter { $0 > 0 }.sorted()
        guard !populatedBins.isEmpty else { return .empty }
        let percentileIndex = min(
            populatedBins.count - 1,
            Int(Double(populatedBins.count - 1) * 0.98)
        )
        let displayMaximum = max(1, populatedBins[percentileIndex])
        func normalized(_ values: [Double]) -> [Double] {
            values.map { sqrt(min(1, $0 / displayMaximum)) }
        }
        return PhotoHistogram(
            red: normalized(red),
            green: normalized(green),
            blue: normalized(blue),
            clippedHighlightFraction: clippedHighlights / sampleCount,
            clippedShadowFraction: clippedShadows / sampleCount
        )
    }

    func automaticMaskImages(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat = 2_400
    ) throws -> ResolvedAutomaticMasks {
        let base = try makeBaseImage(
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension
        )
        var image = Self.applyAdjustments(
            recipe.adjustments,
            to: base.image,
            appliesExposure: !source.isRAW
        )
        image = Self.applyColor(recipe.color, to: image)
        image = Self.applyFilter(
            recipe.filter,
            intensity: recipe.filterIntensity,
            to: image
        )
        image = Self.applyCrop(recipe.crop, to: image)
        let croppedRawSkyMatte = base.rawSkyMatte.map {
            Self.applyCrop(recipe.crop, to: $0)
        }
        let cacheIdentity = maskCacheIdentity(source: source, recipe: recipe)
        var images: [UUID: CGImage] = [:]
        for component in recipe.masks.flatMap(\.components)
        where component.kind == .subject || component.kind == .sky {
            guard let mask = try componentMask(
                component,
                image: image,
                rawSkyMatte: croppedRawSkyMatte,
                cacheIdentity: cacheIdentity
            ), let cgImage = context.createCGImage(
                mask,
                from: mask.extent,
                format: .L8,
                colorSpace: CGColorSpaceCreateDeviceGray()
            ) else { continue }
            images[component.id] = cgImage
        }
        return ResolvedAutomaticMasks(images: images)
    }

    /// Small per-mask previews for the mask list: the edited image with that
    /// mask's real shape tinted. Rendered once per mask-set change, not per
    /// slider frame.
    func maskThumbnails(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat = 120
    ) throws -> ResolvedMaskThumbnails {
        guard !recipe.masks.isEmpty else { return ResolvedMaskThumbnails(images: [:]) }
        // `renderPhoto`, so a caption sitting over the mask never appears in a 120pt
        // matte swatch whose whole job is to show a shape.
        let result = try renderPhoto(
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension
        )
        let cacheIdentity = maskCacheIdentity(source: source, recipe: recipe)
        // Lightroom-style matte swatch: the mask's red shape on flat grey, no
        // photo underneath. Red-over-the-picture at 42pt was unreadable — the
        // shape drowned in the image it was tinting.
        let extent = result.image.extent
        let backdrop = CIImage(color: CIColor(red: 0.16, green: 0.16, blue: 0.18))
            .cropped(to: extent)
        let fill = CIImage(color: CIColor(red: 1, green: 0.08, blue: 0.13))
            .cropped(to: extent)
        var images: [UUID: CGImage] = [:]
        for mask in recipe.masks {
            guard let matte = try renderMask(
                mask,
                over: result.image,
                rawSkyMatte: nil,
                cacheIdentity: cacheIdentity
            ), let cgImage = context.createCGImage(
                blend(adjusted: fill, original: backdrop, mask: matte),
                from: extent,
                format: .RGBA8,
                colorSpace: result.colorSpace
            ) else { continue }
            images[mask.id] = cgImage
        }
        return ResolvedMaskThumbnails(images: images)
    }

    /// Swatches for the Filters tab: the photo being edited, at thumbnail size,
    /// through every look asked for.
    ///
    /// Masks, Clean Up strokes and overlays are dropped rather than rendered — at
    /// 150px they are invisible, and solving a Remove fill fifty times over would
    /// cost seconds to show nothing. Everything that does change the colour of a swatch —
    /// adjustments, the Color tab, the crop — is kept, so a swatch always predicts
    /// what tapping it will do. Filter intensity is ignored on purpose: a swatch
    /// shows the whole look, and the slider then dials it back.
    func filterThumbnails(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        filters: [PhotoFilter],
        maximumDimension: CGFloat = 150
    ) throws -> ResolvedFilterThumbnails {
        guard !filters.isEmpty else { return ResolvedFilterThumbnails(images: [:]) }
        var base = recipe
        base.filter = .original
        base.filterIntensity = 1
        base.masks = []
        base.overlays = []
        let result = try renderPhoto(
            source: source,
            recipe: base,
            maximumDimension: maximumDimension
        )
        // Flattened once: reusing the recipe's `CIImage` per look would make Core
        // Image re-evaluate the whole adjustment chain fifty times over.
        guard let flattened = context.createCGImage(
            result.image,
            from: result.image.extent,
            format: .RGBA8,
            colorSpace: result.colorSpace
        ) else { return ResolvedFilterThumbnails(images: [:]) }
        let unfiltered = CIImage(cgImage: flattened)
        var images: [PhotoFilter: CGImage] = [:]
        for filter in filters {
            guard filter != .original else {
                images[filter] = flattened
                continue
            }
            guard let cgImage = context.createCGImage(
                Self.applyFilter(filter, to: unfiltered),
                from: unfiltered.extent,
                format: .RGBA8,
                colorSpace: result.colorSpace
            ) else { continue }
            images[filter] = cgImage
        }
        return ResolvedFilterThumbnails(images: images)
    }

    func resolvedOutputFormat(
        requested: PhotoOutputFormat,
        sourceType: UTType,
        sourceIsRAW: Bool
    ) -> PhotoOutputFormat {
        guard requested == .preserve else { return requested }
        if sourceIsRAW { return .jpeg }
        return sourceType.conforms(to: .heic) ? .heic : .jpeg
    }

    // MARK: Base image

    private struct BaseImageResult {
        var image: CIImage
        let colorSpace: CGColorSpace
        let rawSkyMatte: CIImage?
    }

    private func makeInteractiveBaseImage(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat,
        cachesBase: Bool
    ) throws -> BaseImageResult {
        let signature = rawBaseSignature(source: source, recipe: recipe)
        if let cache = interactiveBaseCache,
           cache.sourceURL == source.url,
           cache.rawSignature == signature {
            var image = CIImage(
                cgImage: cache.image,
                options: [.colorSpace: cache.colorSpace]
            )
            image = scaleDown(image, maximumDimension: maximumDimension)
            return BaseImageResult(
                image: image,
                colorSpace: cache.colorSpace,
                rawSkyMatte: nil
            )
        }

        let baseResult = try makeBaseImage(
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension
        )
        guard cachesBase,
              let image = context.createCGImage(
                  baseResult.image,
                  from: baseResult.image.extent,
                  format: .RGBA8,
                  colorSpace: baseResult.colorSpace
              )
        else {
            return baseResult
        }
        interactiveBaseCache = InteractiveBaseCache(
            sourceURL: source.url,
            rawSignature: signature,
            image: image,
            colorSpace: baseResult.colorSpace
        )
        return BaseImageResult(
            image: CIImage(
                cgImage: image,
                options: [.colorSpace: baseResult.colorSpace]
            ),
            colorSpace: baseResult.colorSpace,
            rawSkyMatte: nil
        )
    }

    private func rawBaseSignature(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe
    ) -> RAWBaseSignature? {
        guard source.isRAW else { return nil }
        let adjustments = recipe.adjustments
        return RAWBaseSignature(
            exposure: adjustments.exposure,
            temperature: adjustments.rawTemperature,
            tint: adjustments.rawTint,
            luminanceNoise: adjustments.rawLuminanceNoise,
            colorNoise: adjustments.rawColorNoise,
            sharpness: adjustments.rawSharpness,
            lensCorrection: adjustments.lensCorrection
        )
    }

    private func makeBaseImage(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat?
    ) throws -> BaseImageResult {
        let colorSpace = preservedColorSpace(from: source.properties, isRAW: source.isRAW)
        if source.isRAW {
            guard let raw = CIRAWFilter(imageURL: source.url) else {
                throw PhotoEditingError.unsupportedRAW
            }
            raw.orientation = source.orientation
            raw.exposure = Float(recipe.adjustments.exposure)
            raw.neutralTemperature = max(
                2_000,
                min(50_000, raw.neutralTemperature + Float(recipe.adjustments.rawTemperature * 4_000))
            )
            raw.neutralTint = max(
                -150,
                min(150, raw.neutralTint + Float(recipe.adjustments.rawTint * 150))
            )
            if raw.isLuminanceNoiseReductionSupported {
                raw.luminanceNoiseReductionAmount = clampedUnit(
                    Double(raw.luminanceNoiseReductionAmount)
                        + recipe.adjustments.rawLuminanceNoise
                )
            }
            if raw.isColorNoiseReductionSupported {
                raw.colorNoiseReductionAmount = clampedUnit(
                    Double(raw.colorNoiseReductionAmount) + recipe.adjustments.rawColorNoise
                )
            }
            if raw.isSharpnessSupported {
                raw.sharpnessAmount = clampedUnit(
                    Double(raw.sharpnessAmount) + recipe.adjustments.rawSharpness
                )
            }
            if raw.isLensCorrectionSupported {
                raw.isLensCorrectionEnabled = recipe.adjustments.lensCorrection >= 0.5
            }
            if let maximumDimension {
                let nativeLongEdge = max(raw.nativeSize.width, raw.nativeSize.height)
                raw.scaleFactor = Float(min(1, maximumDimension / max(1, nativeLongEdge)))
                raw.isDraftModeEnabled = true
            } else {
                raw.scaleFactor = 1
                raw.isDraftModeEnabled = false
            }
            guard let image = raw.outputImage else {
                throw PhotoEditingError.unsupportedRAW
            }
            return BaseImageResult(
                image: image,
                colorSpace: colorSpace,
                rawSkyMatte: raw.semanticSegmentationSkyMatte
            )
        }

        let options: [CIImageOption: Any] = [
            .applyOrientationProperty: true,
            .colorSpace: colorSpace,
        ]
        guard var image = CIImage(contentsOf: source.url, options: options) else {
            throw PhotoEditingError.cannotDecode
        }
        if let maximumDimension {
            image = scaleDown(image, maximumDimension: maximumDimension)
        }
        return BaseImageResult(image: image, colorSpace: colorSpace, rawSkyMatte: nil)
    }

    private func preservedColorSpace(
        from properties: [CFString: Any],
        isRAW: Bool
    ) -> CGColorSpace {
        let profile = (properties[kCGImagePropertyProfileName] as? String)?.lowercased() ?? ""
        if profile.contains("display p3") || profile.contains("p3") || isRAW {
            return CGColorSpace(name: CGColorSpace.displayP3)!
        }
        if profile.contains("adobe") {
            return CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    // MARK: Adjustment graph

    static func applyAdjustments(
        _ adjustments: PhotoAdjustments,
        to input: CIImage,
        appliesExposure: Bool
    ) -> CIImage {
        var image = input
        if appliesExposure, abs(adjustments.exposure) > 0.0001 {
            image = filtered(
                "CIExposureAdjust",
                image: image,
                values: [kCIInputEVKey: adjustments.exposure]
            )
        }

        let shadowValue = min(1, max(-1, adjustments.shadows + adjustments.brilliance * 0.35))
        let highlightValue = min(
            1,
            max(-1, adjustments.highlights + adjustments.brilliance * 0.2)
        )
        if abs(shadowValue) > 0.0001 || abs(highlightValue) > 0.0001 {
            image = filtered(
                "CIHighlightShadowAdjust",
                image: image,
                values: [
                    "inputShadowAmount": max(0, shadowValue),
                    "inputHighlightAmount": max(0.15, 1 + highlightValue * 0.75),
                    "inputRadius": 0,
                ]
            )
        }

        if abs(adjustments.whites) > 0.0001 {
            // Whites moves the top of the tone curve only: the two upper control
            // points travel while the shadow anchors stay put, so a highlight
            // recovery does not wash the midtones out the way brightness does.
            let lift = adjustments.whites
            image = filtered(
                "CIToneCurve",
                image: image,
                values: [
                    "inputPoint0": CIVector(x: 0, y: 0),
                    "inputPoint1": CIVector(x: 0.25, y: 0.25),
                    "inputPoint2": CIVector(x: 0.5, y: CGFloat(0.5 + lift * 0.04)),
                    "inputPoint3": CIVector(x: 0.75, y: CGFloat(0.75 + lift * 0.13)),
                    "inputPoint4": CIVector(x: 1, y: CGFloat(min(1, 1 + lift * 0.1))),
                ]
            )
        }

        if abs(adjustments.blackPoint) > 0.0001 {
            let minimum = max(0, adjustments.blackPoint * 0.18)
            image = filtered(
                "CIColorClamp",
                image: image,
                values: [
                    "inputMinComponents": CIVector(
                        x: minimum,
                        y: minimum,
                        z: minimum,
                        w: 0
                    ),
                    "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
                ]
            )
        }

        let saturation = max(
            0,
            1 + adjustments.saturation + adjustments.brilliance * 0.08
        )
        let contrast = max(0.2, 1 + adjustments.contrast * 0.75)
        if abs(saturation - 1) > 0.0001
            || abs(contrast - 1) > 0.0001
            || abs(adjustments.brightness) > 0.0001 {
            image = filtered(
                "CIColorControls",
                image: image,
                values: [
                    kCIInputSaturationKey: saturation,
                    kCIInputContrastKey: contrast,
                    kCIInputBrightnessKey: adjustments.brightness * 0.5,
                ]
            )
        }
        if abs(adjustments.vibrance) > 0.0001 || abs(adjustments.brilliance) > 0.0001 {
            image = filtered(
                "CIVibrance",
                image: image,
                values: [
                    "inputAmount": adjustments.vibrance + adjustments.brilliance * 0.25
                ]
            )
        }
        if abs(adjustments.warmth) > 0.0001 || abs(adjustments.tint) > 0.0001 {
            image = filtered(
                "CITemperatureAndTint",
                image: image,
                values: [
                    "inputNeutral": CIVector(x: 6_500, y: 0),
                    "inputTargetNeutral": CIVector(
                        x: 6_500 + adjustments.warmth * 3_000,
                        y: adjustments.tint * 150
                    ),
                ]
            )
        }
        // Detail and Effects are two-way. Dragging right does the obvious thing;
        // dragging left does its opposite, which is what a photographer expects
        // from a slider with a centre tick.
        if adjustments.sharpness > 0 {
            image = filtered(
                "CISharpenLuminance",
                image: image,
                values: ["inputSharpness": adjustments.sharpness * 1.2]
            )
        } else if adjustments.sharpness < 0 {
            // Left of centre softens instead of sharpening.
            image = blurred(image, radius: -adjustments.sharpness * 2.5)
        }
        if adjustments.definition > 0 {
            image = filtered(
                "CIUnsharpMask",
                image: image,
                values: [
                    kCIInputRadiusKey: 2 + adjustments.definition * 4,
                    kCIInputIntensityKey: adjustments.definition,
                ]
            )
        } else if adjustments.definition < 0 {
            // Negative definition flattens local contrast by mixing in a blurred
            // copy — the inverse of an unsharp mask rather than a plain blur.
            let amount = -adjustments.definition
            image = filtered(
                "CIMix",
                image: blurred(image, radius: 1 + amount * 3),
                values: [
                    kCIInputBackgroundImageKey: image,
                    "inputAmount": amount * 0.7,
                ]
            ).cropped(to: image.extent)
        }
        if adjustments.noiseReduction < 0 {
            // Left of centre removes noise; the slider reads as "how much noise
            // the photo has", so less is to the left.
            image = filtered(
                "CINoiseReduction",
                image: image,
                values: [
                    "inputNoiseLevel": -adjustments.noiseReduction * 0.08,
                    "inputSharpness": max(0, adjustments.sharpness * 0.4),
                ]
            )
        } else if adjustments.noiseReduction > 0 {
            image = applyGrain(adjustments.noiseReduction * 0.6, to: image)
        }
        if abs(adjustments.vignette) > 0.0001 {
            // A negative intensity brightens the corners instead of darkening
            // them, so the same slider covers both looks.
            image = filtered(
                "CIVignette",
                image: image,
                values: [
                    kCIInputIntensityKey: adjustments.vignette * 2,
                    kCIInputRadiusKey: min(image.extent.width, image.extent.height) * 0.45,
                ]
            )
        }
        if adjustments.grain > 0 {
            image = applyGrain(adjustments.grain, to: image)
        }
        return image
    }

    /// Gaussian blur that keeps the image's extent: the filter itself grows the
    /// extent and leaves transparent edges unless the input is clamped first.
    static func blurred(_ input: CIImage, radius: Double) -> CIImage {
        guard radius > 0.01 else { return input }
        return filtered(
            "CIGaussianBlur",
            image: input.clampedToExtent(),
            values: [kCIInputRadiusKey: radius]
        ).cropped(to: input.extent)
    }

    /// `CIRandomGenerator` is deterministic per pixel coordinate, so the grain
    /// pattern stays put between renders instead of boiling while a slider moves.
    /// The noise is desaturated and soft-light blended so it reads as film grain
    /// rather than colored sensor noise.
    static func applyGrain(_ amount: Double, to input: CIImage) -> CIImage {
        let extent = input.extent
        guard extent.width > 1, extent.height > 1,
              let noise = CIFilter(name: "CIRandomGenerator")?.outputImage
        else { return input }
        let grayNoise = filtered(
            "CIColorMatrix",
            image: noise,
            values: [
                "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]
        )
        // Grain clumps are scaled with the image so a 2400 px preview and the
        // full-resolution save show the same texture.
        let grainScale = max(1, max(extent.width, extent.height) / 1_600)
        let sized = grayNoise
            .transformed(by: CGAffineTransform(scaleX: grainScale, y: grainScale))
            .cropped(to: extent)
        let blended = filtered(
            "CISoftLightBlendMode",
            image: sized,
            values: [kCIInputBackgroundImageKey: input]
        )
        return filtered(
            "CIMix",
            image: blended,
            values: [
                kCIInputBackgroundImageKey: input,
                "inputAmount": min(1, max(0, amount)),
            ]
        ).cropped(to: extent)
    }

    /// Mixes the filtered image back over the unfiltered one so a preset can be
    /// dialled in instead of being all-or-nothing.
    static func applyFilter(
        _ filter: PhotoFilter,
        intensity: Double,
        to input: CIImage
    ) -> CIImage {
        guard filter != .original else { return input }
        let output = applyFilter(filter, to: input)
        let amount = min(1, max(0, intensity))
        guard amount < 0.999 else { return output }
        guard amount > 0.001 else { return input }
        return filtered(
            "CIMix",
            image: output,
            values: [
                kCIInputBackgroundImageKey: input,
                "inputAmount": amount,
            ]
        ).cropped(to: input.extent)
    }

    static func applyFilter(_ filter: PhotoFilter, to input: CIImage) -> CIImage {
        // Every film simulation is a lookup table. The ten original presets below
        // keep their hand-built Core Image chains, so a recipe saved before the
        // film looks existed still renders byte-for-byte the way it did.
        if let look = FilmLookLibrary.look(for: filter) {
            return applyFilmLook(look, key: filter.rawValue, to: input)
        }
        switch filter {
        case .original:
            return input
        case .vivid:
            return filtered(
                "CIColorControls",
                image: filtered("CIVibrance", image: input, values: ["inputAmount": 0.35]),
                values: [kCIInputSaturationKey: 1.2, kCIInputContrastKey: 1.08]
            )
        case .vividWarm:
            let vivid = applyFilter(.vivid, to: input)
            return filtered(
                "CITemperatureAndTint",
                image: vivid,
                values: [
                    "inputNeutral": CIVector(x: 6_500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7_800, y: 12),
                ]
            )
        case .vividCool:
            let vivid = applyFilter(.vivid, to: input)
            return filtered(
                "CITemperatureAndTint",
                image: vivid,
                values: [
                    "inputNeutral": CIVector(x: 6_500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5_200, y: -8),
                ]
            )
        case .dramatic, .dramaticWarm, .dramaticCool:
            var image = filtered(
                "CIColorControls",
                image: input,
                values: [kCIInputSaturationKey: 0.92, kCIInputContrastKey: 1.24]
            )
            image = filtered(
                "CIUnsharpMask",
                image: image,
                values: [kCIInputRadiusKey: 3, kCIInputIntensityKey: 0.35]
            )
            if filter == .dramaticWarm {
                image = filtered(
                    "CITemperatureAndTint",
                    image: image,
                    values: [
                        "inputNeutral": CIVector(x: 6_500, y: 0),
                        "inputTargetNeutral": CIVector(x: 7_600, y: 8),
                    ]
                )
            } else if filter == .dramaticCool {
                image = filtered(
                    "CITemperatureAndTint",
                    image: image,
                    values: [
                        "inputNeutral": CIVector(x: 6_500, y: 0),
                        "inputTargetNeutral": CIVector(x: 5_300, y: -8),
                    ]
                )
            }
            return image
        case .mono:
            return filtered("CIPhotoEffectMono", image: input)
        case .silvertone:
            return filtered("CIPhotoEffectTonal", image: input)
        case .noir:
            return filtered("CIPhotoEffectNoir", image: input)
        default:
            // Unreachable: everything else has a `FilmLook` and returned above.
            return input
        }
    }

    static func filtered(
        _ name: String,
        image: CIImage,
        values: [String: Any] = [:]
    ) -> CIImage {
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in values {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage ?? image
    }

    // MARK: Crop

    static func applyCrop(_ crop: PhotoCropRecipe, to input: CIImage) -> CIImage {
        var image = input
        if crop.quarterTurns % 4 != 0 {
            image = image.oriented(
                forExifOrientation: crop.quarterTurns % 4 == 1
                    ? Int32(CGImagePropertyOrientation.right.rawValue)
                    : crop.quarterTurns % 4 == 2
                        ? Int32(CGImagePropertyOrientation.down.rawValue)
                        : Int32(CGImagePropertyOrientation.left.rawValue)
            )
        }
        if crop.flippedHorizontally {
            image = image.transformed(by:
                CGAffineTransform(
                    translationX: image.extent.maxX + image.extent.minX,
                    y: 0
                ).scaledBy(x: -1, y: 1)
            )
        }
        if abs(crop.straightenDegrees) > 0.001 {
            let radians = crop.straightenDegrees * .pi / 180
            let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
            image = image.transformed(by:
                CGAffineTransform(translationX: center.x, y: center.y)
                    .rotated(by: radians)
                    .translatedBy(x: -center.x, y: -center.y)
            )
        }
        let normalized = crop.rect.cgRect
        let extent = image.extent
        let cropRect = CGRect(
            x: extent.minX + extent.width * normalized.minX,
            y: extent.minY + extent.height * (1 - normalized.maxY),
            width: extent.width * normalized.width,
            height: extent.height * normalized.height
        ).intersection(extent)
        if !cropRect.isNull, cropRect.width > 0, cropRect.height > 0 {
            image = image.cropped(to: cropRect)
        }
        return image
    }

    // MARK: Masks

    private func renderMask(
        _ mask: PhotoMask,
        over image: CIImage,
        rawSkyMatte: CIImage?,
        cacheIdentity: String
    ) throws -> CIImage? {
        let extent = image.extent.integral
        var accumulated = blackMask(extent: extent)
        for component in mask.components {
            guard var incoming = try componentMask(
                component,
                image: image,
                rawSkyMatte: rawSkyMatte,
                cacheIdentity: cacheIdentity
            ) else { continue }
            incoming = incoming.cropped(to: extent)
            if component.opacity < 0.999 {
                incoming = incoming.applyingFilter(
                    "CIColorMatrix",
                    parameters: [
                        "inputRVector": CIVector(
                            x: component.opacity,
                            y: 0,
                            z: 0,
                            w: 0
                        ),
                        "inputGVector": CIVector(
                            x: 0,
                            y: component.opacity,
                            z: 0,
                            w: 0
                        ),
                        "inputBVector": CIVector(
                            x: 0,
                            y: 0,
                            z: component.opacity,
                            w: 0
                        ),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    ]
                )
            }
            accumulated = combineMask(
                accumulated,
                with: incoming,
                operation: component.operation,
                extent: extent
            )
        }
        if mask.isInverted, let kernel = Self.invertMaskKernel {
            accumulated = kernel.apply(extent: extent, arguments: [accumulated]) ?? accumulated
        }
        return accumulated.cropped(to: extent)
    }

    private func componentMask(
        _ component: PhotoMaskComponent,
        image: CIImage,
        rawSkyMatte: CIImage?,
        cacheIdentity: String
    ) throws -> CIImage? {
        switch component.kind {
        case .brush:
            return brushMask(component.brushStrokes, extent: image.extent)
        case .linearGradient:
            return linearGradientMask(component, extent: image.extent)
        case .radialGradient:
            return radialGradientMask(component, extent: image.extent)
        case .subject:
            return try cachedAutomaticMask(
                key: "\(cacheIdentity)|subject|\(component.id)|\(component.subjectPoint.x)|\(component.subjectPoint.y)",
                image: image
            ) {
                try subjectMask(at: component.subjectPoint, image: image)
            }
        case .sky:
            if let rawSkyMatte {
                return rawSkyMatte
                    .transformed(by:
                        CGAffineTransform(
                            scaleX: image.extent.width / rawSkyMatte.extent.width,
                            y: image.extent.height / rawSkyMatte.extent.height
                        )
                    )
                    .cropped(to: image.extent)
            }
            return try cachedAutomaticMask(
                key: "\(cacheIdentity)|sky|\(component.id)",
                image: image
            ) {
                try coreMLSkyMask(image: image)
            }
        case .luminanceRange:
            guard let kernel = Self.luminanceMaskKernel else { return nil }
            return kernel.apply(
                extent: image.extent,
                arguments: [
                    image,
                    component.luminanceMinimum,
                    component.luminanceMaximum,
                    max(0.005, component.feather * 0.25),
                ]
            )
        case .colorRange:
            guard let kernel = Self.colorMaskKernel else { return nil }
            return kernel.apply(
                extent: image.extent,
                arguments: [
                    image,
                    CIVector(
                        x: component.sampledRed,
                        y: component.sampledGreen,
                        z: component.sampledBlue
                    ),
                    component.colorTolerance,
                    max(0.005, component.feather * 0.25),
                ]
            )
        }
    }

    private func blackMask(extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: extent)
    }

    private func maskCacheIdentity(
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe
    ) -> String {
        let crop = recipe.crop
        return [
            source.url.path,
            "\(crop.rect.x),\(crop.rect.y),\(crop.rect.width),\(crop.rect.height)",
            "\(crop.quarterTurns),\(crop.straightenDegrees),\(crop.flippedHorizontally)",
        ].joined(separator: "|")
    }

    private func cachedAutomaticMask(
        key: String,
        image: CIImage,
        build: () throws -> CIImage?
    ) throws -> CIImage? {
        let extent = image.extent.integral
        let sizedKey = "\(key)|\(Int(extent.width))x\(Int(extent.height))"
        guard max(extent.width, extent.height) <= 3_000 else {
            return try build()
        }
        if let cached = automaticMaskCache[sizedKey] {
            return cached
                .transformed(
                    by: CGAffineTransform(
                        translationX: extent.minX - cached.extent.minX,
                        y: extent.minY - cached.extent.minY
                    )
                )
                .cropped(to: extent)
        }
        guard let mask = try build(),
              let cgImage = context.createCGImage(
                  mask,
                  from: extent,
                  format: .L8,
                  colorSpace: CGColorSpaceCreateDeviceGray()
              )
        else { return nil }
        let detached = CIImage(cgImage: cgImage)
        automaticMaskCache[sizedKey] = detached
        automaticMaskCacheOrder.append(sizedKey)
        while automaticMaskCacheOrder.count > Self.automaticMaskCacheCapacity {
            let evicted = automaticMaskCacheOrder.removeFirst()
            automaticMaskCache.removeValue(forKey: evicted)
        }
        return detached
            .transformed(
                by: CGAffineTransform(
                    translationX: extent.minX,
                    y: extent.minY
                )
            )
            .cropped(to: extent)
    }

    private func combineMask(
        _ current: CIImage,
        with incoming: CIImage,
        operation: MaskBlendOperation,
        extent: CGRect
    ) -> CIImage {
        let kernel = operation == .add ? Self.addMaskKernel : Self.subtractMaskKernel
        return kernel?.apply(extent: extent, arguments: [current, incoming]) ?? current
    }

    private func brushMask(_ strokes: [BrushStroke], extent: CGRect) -> CIImage {
        guard !strokes.isEmpty,
              let context = CGContext(
                  data: nil,
                  width: max(1, Int(extent.width.rounded(.up))),
                  height: max(1, Int(extent.height.rounded(.up))),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return blackMask(extent: extent) }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: extent.size))
        let shortEdge = min(extent.width, extent.height)

        // Each stroke carries its own soft edge — see `BrushStrokeRasterizer` for
        // why the single Gaussian this replaces made zoom-painted detail disappear.
        BrushStrokeRasterizer.draw(strokes, in: context, shortEdge: shortEdge) { point in
            let mapped = Self.imagePoint(point, extent: extent)
            return CGPoint(x: mapped.x - extent.minX, y: mapped.y - extent.minY)
        }
        guard let cgImage = context.makeImage() else { return blackMask(extent: extent) }
        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    private func linearGradientMask(
        _ component: PhotoMaskComponent,
        extent: CGRect
    ) -> CIImage? {
        let start = Self.imagePoint(component.startPoint, extent: extent)
        let end = Self.imagePoint(component.endPoint, extent: extent)
        return CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(cgPoint: start),
                "inputPoint1": CIVector(cgPoint: end),
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black,
            ]
        )?.outputImage?.cropped(to: extent)
    }

    private func radialGradientMask(
        _ component: PhotoMaskComponent,
        extent: CGRect
    ) -> CIImage? {
        let center = Self.imagePoint(component.center, extent: extent)
        let radiusX = max(1, component.radiusX * extent.width)
        let radiusY = max(1, component.radiusY * extent.height)
        let inner = max(0, 1 - component.feather)
        return CIFilter(
            name: "CIRadialGradient",
            parameters: [
                kCIInputCenterKey: CIVector(x: 0, y: 0),
                "inputRadius0": inner,
                "inputRadius1": 1,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black,
            ]
        )?.outputImage?
            .transformed(by: CGAffineTransform(scaleX: radiusX, y: radiusY))
            .transformed(
                by: CGAffineTransform(
                    translationX: center.x,
                    y: center.y
                )
            )
            .cropped(to: extent)
    }

    private func subjectMask(at point: NormalizedPoint, image: CIImage) throws -> CIImage? {
        let normalizedImage = image.transformed(by:
            CGAffineTransform(
                translationX: -image.extent.minX,
                y: -image.extent.minY
            )
        )
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: normalizedImage)
        try handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        let instance = instanceIndex(
            at: point,
            in: observation.instanceMask
        )
        let selected = instance > 0
            ? IndexSet(integer: instance)
            : observation.allInstances
        let pixelBuffer = try observation.generateScaledMaskForImage(
            forInstances: selected,
            from: handler
        )
        return CIImage(cvPixelBuffer: pixelBuffer)
            .transformed(by:
                CGAffineTransform(
                    translationX: image.extent.minX,
                    y: image.extent.minY
                )
            )
            .cropped(to: image.extent)
    }

    private func instanceIndex(at point: NormalizedPoint, in buffer: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let x = min(width - 1, max(0, Int(point.x * Double(width))))
        let y = min(height - 1, max(0, Int(point.y * Double(height))))
        let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_OneComponent8:
            return Int(row.assumingMemoryBound(to: UInt8.self)[x])
        case kCVPixelFormatType_OneComponent16Half:
            let bits = row.assumingMemoryBound(to: UInt16.self)[x]
            return Int(Float(Float16(bitPattern: bits)).rounded())
        case kCVPixelFormatType_OneComponent32Float:
            return Int(row.assumingMemoryBound(to: Float.self)[x].rounded())
        default:
            return 0
        }
    }

    private func coreMLSkyMask(image: CIImage) throws -> CIImage? {
        let model = try loadSkyModel()
        let modelSize = CGSize(width: 448, height: 448)
        let extent = image.extent
        let scale = min(modelSize.width / extent.width, modelSize.height / extent.height)
        let fittedSize = CGSize(width: extent.width * scale, height: extent.height * scale)
        let fittedOrigin = CGPoint(
            x: (modelSize.width - fittedSize.width) / 2,
            y: (modelSize.height - fittedSize.height) / 2
        )
        let normalized = image
            .transformed(by:
                CGAffineTransform(
                    translationX: -extent.minX,
                    y: -extent.minY
                )
            )
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by:
                CGAffineTransform(
                    translationX: fittedOrigin.x,
                    y: fittedOrigin.y
                )
            )
        let canvas = normalized.composited(
            over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: modelSize))
        )

        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            448,
            448,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            throw PhotoEditingError.cannotRender
        }
        context.render(
            canvas,
            to: pixelBuffer,
            bounds: CGRect(origin: .zero, size: modelSize),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        let prediction = try model.prediction(from: provider)
        guard let array = prediction.featureValue(for: "semanticPredictions")?.multiArrayValue
        else { return nil }
        let skyIndices = skyClassIndices(for: model)
        guard !skyIndices.isEmpty else { return nil }

        var pixels = [UInt8](repeating: 0, count: 448 * 448)
        if array.dataType == .int32, array.shape.count == 2 {
            let values = array.dataPointer.bindMemory(
                to: Int32.self,
                capacity: array.count
            )
            let rowStride = array.strides[0].intValue
            let columnStride = array.strides[1].intValue
            for y in 0..<448 {
                for x in 0..<448 {
                    let value = Int(values[y * rowStride + x * columnStride])
                    pixels[y * 448 + x] = skyIndices.contains(value) ? 255 : 0
                }
            }
        } else {
            for y in 0..<448 {
                for x in 0..<448 {
                    let value = array[[NSNumber(value: y), NSNumber(value: x)]].intValue
                    pixels[y * 448 + x] = skyIndices.contains(value) ? 255 : 0
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let maskImage = CGImage(
            width: 448,
            height: 448,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: 448,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw PhotoEditingError.cannotRender
        }

        let fittedRect = CGRect(origin: fittedOrigin, size: fittedSize)
        let modelMask = CIImage(cgImage: maskImage).cropped(to: fittedRect)
        let restored = modelMask
            .transformed(by:
                CGAffineTransform(
                    translationX: -fittedRect.minX,
                    y: -fittedRect.minY
                )
            )
            .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            .transformed(by:
                CGAffineTransform(
                    translationX: extent.minX,
                    y: extent.minY
                )
            )
        return restored
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.5 / scale])
            .cropped(to: extent)
    }

    private func loadSkyModel() throws -> MLModel {
        if let skyModel { return skyModel }
        guard let url = Bundle.main.url(
            forResource: "DETRResnet50SemanticSegmentationF16P8",
            withExtension: "mlmodelc"
        ) else {
            throw PhotoEditingError.unavailable
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: configuration)
        skyModel = model
        return model
    }

    private func skyClassIndices(for model: MLModel) -> Set<Int> {
        guard let metadata = model.modelDescription.metadata[.creatorDefinedKey]
                as? [String: Any],
              let raw = metadata["com.apple.coreml.model.preview.params"] as? String,
              let data = raw.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let labels = dictionary["labels"] as? [String]
        else { return [] }
        return Set(labels.enumerated().compactMap { index, label in
            label.lowercased().contains("sky") ? index : nil
        })
    }

    private func blend(adjusted: CIImage, original: CIImage, mask: CIImage) -> CIImage {
        Self.filtered(
            "CIBlendWithMask",
            image: adjusted,
            values: [
                kCIInputBackgroundImageKey: original,
                kCIInputMaskImageKey: mask,
            ]
        )
    }

    private func overlayMask(_ mask: CIImage, on image: CIImage) -> CIImage {
        // Red, not the UI accent: the overlay has to be obviously a temporary
        // stand-in for the selected area, and a blue tint reads as part of the
        // photo's own colour once the user starts moving sliders.
        //
        // A flat 45% wash went muddy over dark subjects — the very places a mask
        // is usually drawn. Screening a red in first lifts the shadows into the
        // hue, then the vivid wash on top keeps it saturated everywhere, which is
        // what makes Lightroom's overlay readable at a glance.
        let glow = CIImage(
            color: CIColor(red: 0.62, green: 0, blue: 0.02, alpha: 1)
        ).cropped(to: image.extent)
        let lifted = Self.filtered(
            "CIScreenBlendMode",
            image: glow,
            values: [kCIInputBackgroundImageKey: image]
        )
        let tint = CIImage(
            color: CIColor(red: 1, green: 0.08, blue: 0.13, alpha: 0.52)
        ).cropped(to: image.extent)
        let washed = tint.composited(over: lifted).cropped(to: image.extent)
        let overlay = blend(adjusted: washed, original: image, mask: mask)
        return overlay.cropped(to: image.extent)
    }

    /// Static so the Clean Up stage — which also runs from the Live Photo frame
    /// processor, outside the actor — maps points exactly the way the mask
    /// rasterizer does instead of carrying a third copy of the y flip.
    static func imagePoint(_ point: NormalizedPoint, extent: CGRect) -> CGPoint {
        CGPoint(
            x: extent.minX + extent.width * point.x,
            y: extent.minY + extent.height * (1 - point.y)
        )
    }

    private func scaleDown(_ image: CIImage, maximumDimension: CGFloat) -> CIImage {
        let longEdge = max(image.extent.width, image.extent.height)
        guard longEdge > maximumDimension else { return image }
        let scale = maximumDimension / longEdge
        return lanczosScale(image, scale: scale)
    }

    private func lanczosScale(_ image: CIImage, scale: CGFloat) -> CIImage {
        guard abs(scale - 1) > 0.000_001 else { return image }
        return image.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1,
            ]
        )
    }

    private func clampedUnit(_ value: Double) -> Float {
        Float(min(1, max(0, value)))
    }
}
