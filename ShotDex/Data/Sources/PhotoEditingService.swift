import CoreImage
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import UIKit

struct PhotoEditSourceOption: Identifiable {
    let id: String
    let source: PhotoEditSource
    let displayName: String
    let filename: String
    let type: UTType
    fileprivate let resource: PHAssetResource?
    fileprivate let contentInputURL: URL?

    var isRAW: Bool { type.conforms(to: .rawImage) }
}

@MainActor
final class PhotoEditingSession {
    let asset: PHAsset
    let contentInput: PHContentEditingInput
    let sourceOptions: [PhotoEditSourceOption]
    let recalledRecipe: PhotoEditRecipe?
    let temporaryDirectory: URL

    fileprivate init(
        asset: PHAsset,
        contentInput: PHContentEditingInput,
        sourceOptions: [PhotoEditSourceOption],
        recalledRecipe: PhotoEditRecipe?,
        temporaryDirectory: URL
    ) {
        self.asset = asset
        self.contentInput = contentInput
        self.sourceOptions = sourceOptions
        self.recalledRecipe = recalledRecipe
        self.temporaryDirectory = temporaryDirectory
    }

    var isLivePhoto: Bool { asset.mediaSubtypes.contains(.photoLive) }
    var hasRAWAndRenderedPair: Bool {
        sourceOptions.contains(where: \.isRAW)
            && sourceOptions.contains(where: { !$0.isRAW })
    }

    func preferredSource(for recipe: PhotoEditRecipe?) -> PhotoEditSourceOption? {
        if let filename = recipe?.sourceFilename,
           let exact = sourceOptions.first(where: { $0.filename == filename }) {
            return exact
        }
        if let source = recipe?.source, source != .automatic,
           let matching = sourceOptions.first(where: { $0.source == source }) {
            return matching
        }
        return sourceOptions.first(where: \.isRAW) ?? sourceOptions.first
    }
}

struct LoadedPhotoEditSource: Sendable {
    let optionID: String
    let info: PhotoRenderSourceInfo
}

struct PhotoSaveResult: Sendable {
    let assetID: String
    let format: PhotoOutputFormat
    let fellBackToJPEG: Bool
}

/// Coordinates PhotoKit content-editing sessions and the Core Image renderer.
/// PhotoKit objects stay on MainActor; expensive decode/render work lives in
/// `PhotoRenderService`.
@MainActor
final class PhotoEditingService {
    let renderer: PhotoRenderService
    private let indexNewAsset: (@Sendable (String) async -> Void)?
    private let publishCreatedAsset: (@MainActor @Sendable (String) -> Void)?
    private let filenameIndexes: PhotoOutputFilenameIndexStore

    init(
        renderer: PhotoRenderService = PhotoRenderService(),
        indexNewAsset: (@Sendable (String) async -> Void)? = nil,
        publishCreatedAsset: (@MainActor @Sendable (String) -> Void)? = nil,
        filenameIndexes: PhotoOutputFilenameIndexStore? = nil
    ) {
        self.renderer = renderer
        self.indexNewAsset = indexNewAsset
        self.publishCreatedAsset = publishCreatedAsset
        self.filenameIndexes = filenameIndexes ?? PhotoOutputFilenameIndexStore()
    }

    func beginSession(for asset: PHAsset) async throws -> PhotoEditingSession {
        guard asset.mediaType == .image else { throw PhotoEditingError.unavailable }
        let input = try await requestContentEditingInput(for: asset)
        let temporaryDirectory = try makeTemporaryDirectory()
        let recalledRecipe = decodeRecipe(input.adjustmentData)
        var sourceAsset = asset
        var sourceInput = input
        if let sourceID = recalledRecipe?.sourceAssetIdentifier,
           sourceID != asset.localIdentifier,
           let original = PHAsset.fetchAssets(
               withLocalIdentifiers: [sourceID],
               options: nil
           ).firstObject,
           let originalInput = try? await requestContentEditingInput(for: original) {
            sourceAsset = original
            sourceInput = originalInput
        }
        let resources = PHAssetResource.assetResources(for: sourceAsset)
        let options = sourceOptions(
            resources: resources,
            contentInput: sourceInput
        )
        guard !options.isEmpty else {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw PhotoEditingError.missingSource
        }
        return PhotoEditingSession(
            asset: asset,
            contentInput: input,
            sourceOptions: options,
            recalledRecipe: recalledRecipe,
            temporaryDirectory: temporaryDirectory
        )
    }

    func endSession(_ session: PhotoEditingSession) {
        let directory = session.temporaryDirectory
        guard directory.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    func loadSource(
        _ option: PhotoEditSourceOption,
        in session: PhotoEditingSession
    ) async throws -> LoadedPhotoEditSource {
        let fileURL = session.temporaryDirectory
            .appendingPathComponent("source-\(option.id)")
            .appendingPathExtension(option.type.preferredFilenameExtension ?? "image")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            if let resource = option.resource {
                try await write(resource: resource, to: fileURL)
            } else if let inputURL = option.contentInputURL {
                try FileManager.default.copyItem(at: inputURL, to: fileURL)
            } else {
                throw PhotoEditingError.missingSource
            }
        }
        let info = try await renderer.inspectSource(at: fileURL, typeHint: option.type)
        return LoadedPhotoEditSource(optionID: option.id, info: info)
    }

    /// `recipe` is what gets attached to the photo; `renderRecipe` is what gets
    /// drawn. They differ for text overlays: the attachment keeps the `{camera}`
    /// template so reopening the edit shows what the user typed, while the pixels
    /// need the tokens already expanded.
    func saveCopy(
        session: PhotoEditingSession,
        source: LoadedPhotoEditSource,
        recipe: PhotoEditRecipe,
        renderRecipe: PhotoEditRecipe? = nil,
        requestedFormat: PhotoOutputFormat,
        includeMetadata: Bool,
        album: PHAssetCollection?
    ) async throws -> PhotoSaveResult {
        let renderRecipe = renderRecipe ?? recipe
        let resolvedRequested = await renderer.resolvedOutputFormat(
            requested: requestedFormat,
            sourceType: source.info.type,
            sourceIsRAW: source.info.isRAW
        )
        let supportedTypes = PHContentEditingOutput(
            contentEditingInput: session.contentInput
        ).supportedRenderedContentTypes
        let actualFormat = supportedTypes.contains(resolvedRequested.uniformType)
            ? resolvedRequested
            : .jpeg
        let baseURL = session.temporaryDirectory.appendingPathComponent(
            "copy-base.\(actualFormat.fileExtension)"
        )
        let renderedURL = session.temporaryDirectory.appendingPathComponent(
            "copy-rendered.\(actualFormat.fileExtension)"
        )

        var baseRecipe = PhotoEditRecipe.identity
        baseRecipe.source = recipe.source
        baseRecipe.sourceFilename = recipe.sourceFilename
        let base = try await renderer.render(source: source.info, recipe: baseRecipe)
        try await renderer.write(
            base,
            to: baseURL,
            format: actualFormat,
            quality: 1,
            includeMetadata: includeMetadata
        )
        let final = try await renderer.render(source: source.info, recipe: renderRecipe)
        try await renderer.write(
            final,
            to: renderedURL,
            format: actualFormat,
            quality: 1,
            includeMetadata: includeMetadata
        )

        var attachedRecipe = recipe
        attachedRecipe.sourceAssetIdentifier =
            recipe.sourceAssetIdentifier ?? session.asset.localIdentifier
        attachedRecipe.sourceFilename =
            session.sourceOptions.first(where: { $0.id == source.optionID })?.filename
        let filenameReservation = filenameIndexes.reserve(
            sourceAssetIdentifier:
                attachedRecipe.sourceAssetIdentifier ?? session.asset.localIdentifier,
            suffix: "SHOTDEX_EDITED"
        )
        let filename = PhotoOutputFilename.make(
            original: attachedRecipe.sourceFilename,
            suffix: "SHOTDEX_EDITED",
            index: filenameReservation.index,
            format: actualFormat
        )
        var placeholderID: String?
        var transactionFileError: Error?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetCreationRequest.forAsset()
                let resourceOptions = PHAssetResourceCreationOptions()
                resourceOptions.originalFilename = filename
                creation.addResource(with: .photo, fileURL: baseURL, options: resourceOptions)
                if includeMetadata {
                    creation.creationDate = session.asset.creationDate
                    creation.location = session.asset.location
                }
                guard let placeholder = creation.placeholderForCreatedAsset else {
                    transactionFileError = PhotoEditingError.cannotCreateAsset
                    return
                }
                placeholderID = placeholder.localIdentifier

                let output = PHContentEditingOutput(placeholderForCreatedAsset: placeholder)
                do {
                    let destination = try output.renderedContentURL(
                        for: actualFormat.uniformType
                    )
                    try FileManager.default.copyItem(at: renderedURL, to: destination)
                } catch {
                    transactionFileError = error
                    return
                }
                output.adjustmentData = self.makeAdjustmentData(attachedRecipe)
                creation.contentEditingOutput = output
                if let album, album.canPerform(.addContent),
                   let albumRequest = PHAssetCollectionChangeRequest(for: album) {
                    albumRequest.addAssets([placeholder] as NSArray)
                }
            }
        } catch {
            filenameIndexes.release(filenameReservation)
            throw error
        }
        if let transactionFileError { throw transactionFileError }
        guard let placeholderID else {
            filenameIndexes.release(filenameReservation)
            throw PhotoEditingError.cannotCreateAsset
        }
        await indexNewAsset?(placeholderID)
        publishCreatedAsset?(placeholderID)
        return PhotoSaveResult(
            assetID: placeholderID,
            format: actualFormat,
            fellBackToJPEG: actualFormat != resolvedRequested
        )
    }

    /// See `saveCopy` for why the attached and the rendered recipe can differ.
    func saveChanges(
        session: PhotoEditingSession,
        source: LoadedPhotoEditSource,
        recipe: PhotoEditRecipe,
        renderRecipe: PhotoEditRecipe? = nil,
        requestedFormat: PhotoOutputFormat,
        includeMetadata: Bool
    ) async throws -> PhotoSaveResult {
        let renderRecipe = renderRecipe ?? recipe
        let output = PHContentEditingOutput(contentEditingInput: session.contentInput)
        let resolvedRequested = await renderer.resolvedOutputFormat(
            requested: requestedFormat,
            sourceType: source.info.type,
            sourceIsRAW: source.info.isRAW
        )

        if session.isLivePhoto {
            try await saveLivePhotoChanges(
                session: session,
                source: source,
                output: output,
                recipe: renderRecipe
            )
            output.adjustmentData = makeAdjustmentData(recipe)
            try await commit(
                output: output,
                to: session.asset,
                includeMetadata: includeMetadata
            )
            let actualFormat: PhotoOutputFormat =
                output.defaultRenderedContentType?.conforms(to: .heic) == true
                    ? .heic
                    : .jpeg
            return PhotoSaveResult(
                assetID: session.asset.localIdentifier,
                format: actualFormat,
                fellBackToJPEG:
                    actualFormat == .jpeg && resolvedRequested == .heic
            )
        }

        let actualFormat = output.supportedRenderedContentTypes.contains(
            resolvedRequested.uniformType
        ) ? resolvedRequested : .jpeg
        let destination = try output.renderedContentURL(for: actualFormat.uniformType)
        let rendered = try await renderer.render(source: source.info, recipe: renderRecipe)
        try await renderer.write(
            rendered,
            to: destination,
            format: actualFormat,
            quality: 1,
            includeMetadata: includeMetadata
        )
        output.adjustmentData = makeAdjustmentData(recipe)
        try await commit(
            output: output,
            to: session.asset,
            includeMetadata: includeMetadata
        )
        return PhotoSaveResult(
            assetID: session.asset.localIdentifier,
            format: actualFormat,
            fellBackToJPEG: actualFormat != resolvedRequested
        )
    }

    func compress(
        asset: PHAsset,
        options: PhotoExportOptions,
        album: PHAssetCollection?,
        cropAnchor: NormalizedPoint? = nil
    ) async throws -> PhotoSaveResult {
        let session = try await beginSession(for: asset)
        defer { endSession(session) }
        guard let option = session.preferredSource(for: nil) else {
            throw PhotoEditingError.missingSource
        }
        let source = try await loadSource(option, in: session)
        let recipe = PhotoEditRecipe.identity
        let rendered = try await renderer.render(source: source.info, recipe: recipe)
        let resized = await renderer.resize(
            rendered,
            preset: options.preset,
            cropAnchor: cropAnchor ?? options.cropAnchor
        )
        let requestedFormat = await renderer.resolvedOutputFormat(
            requested: options.format,
            sourceType: source.info.type,
            sourceIsRAW: source.info.isRAW
        )
        let format = requestedFormat == .heic && !Self.supportsHEICEncoding
            ? .jpeg
            : requestedFormat
        let outputURL = session.temporaryDirectory.appendingPathComponent(
            "compressed.\(format.fileExtension)"
        )
        try await renderer.write(
            resized,
            to: outputURL,
            format: format,
            quality: options.quality,
            includeMetadata: options.includeMetadata
        )
        let sourceName = session.sourceOptions.first(where: { $0.id == source.optionID })?.filename
        let sourceAssetIdentifier =
            session.recalledRecipe?.sourceAssetIdentifier ?? asset.localIdentifier
        let filenameReservation = filenameIndexes.reserve(
            sourceAssetIdentifier: sourceAssetIdentifier,
            suffix: "SHOTDEX_COMPRESSED"
        )
        let filename = PhotoOutputFilename.make(
            original: sourceName,
            suffix: "SHOTDEX_COMPRESSED",
            index: filenameReservation.index,
            format: format
        )
        let id: String
        do {
            id = try await createFlatAsset(
                fileURL: outputURL,
                filename: filename,
                sourceAsset: asset,
                includeMetadata: options.includeMetadata,
                album: album
            )
        } catch {
            filenameIndexes.release(filenameReservation)
            throw error
        }
        await indexNewAsset?(id)
        return PhotoSaveResult(
            assetID: id,
            format: format,
            fellBackToJPEG: format != requestedFormat
        )
    }

    func deleteCreatedAssets(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    func estimateCompressedSize(
        session: PhotoEditingSession,
        source: LoadedPhotoEditSource,
        options: PhotoExportOptions
    ) async throws -> Int {
        var resolvedOptions = options
        let resolvedFormat = await renderer.resolvedOutputFormat(
            requested: options.format,
            sourceType: source.info.type,
            sourceIsRAW: source.info.isRAW
        )
        if resolvedFormat == .heic, !Self.supportsHEICEncoding {
            resolvedOptions.format = .jpeg
        }
        return try await renderer.estimatedEncodedByteCount(
            source: source.info,
            recipe: .identity,
            options: resolvedOptions
        )
    }

    func supportsEditOutputFormat(
        _ format: PhotoOutputFormat,
        in session: PhotoEditingSession
    ) -> Bool {
        guard format != .preserve else { return true }
        return PHContentEditingOutput(
            contentEditingInput: session.contentInput
        ).supportedRenderedContentTypes.contains(format.uniformType)
    }

    static var supportsHEICEncoding: Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(UTType.heic.identifier)
    }

    // MARK: PhotoKit

    private func requestContentEditingInput(for asset: PHAsset) async throws
        -> PHContentEditingInput {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            options.canHandleAdjustmentData = { adjustmentData in
                adjustmentData.formatIdentifier == PhotoEditRecipe.formatIdentifier
                    && adjustmentData.formatVersion == PhotoEditRecipe.formatVersion
            }
            asset.requestContentEditingInput(with: options) { input, info in
                if let input {
                    continuation.resume(returning: input)
                } else if let error = info[PHContentEditingInputErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: PhotoEditingError.unavailable)
                }
            }
        }
    }

    private func sourceOptions(
        resources: [PHAssetResource],
        contentInput: PHContentEditingInput
    ) -> [PhotoEditSourceOption] {
        var result: [PhotoEditSourceOption] = []
        let imageResources = resources.filter {
            [.photo, .fullSizePhoto, .alternatePhoto].contains($0.type)
        }

        // `fullSizeImageURL` is the current Photos rendition when the latest
        // adjustment belongs to Photos or another app. Prefer it for the
        // rendered source so opening ShotDex never silently jumps back to the
        // immutable original after a foreign edit. RAW remains a separate
        // resource option for RAW+JPEG pairs.
        if let url = contentInput.fullSizeImageURL {
            let type = contentType(for: contentInput)
                ?? UTType(filenameExtension: url.pathExtension)
                ?? .image
            let isRAW = type.conforms(to: .rawImage)
            let source: PhotoEditSource = isRAW ? .raw : .rendered
            let matchingResource = imageResources.first { resource in
                let resourceType = UTType(resource.uniformTypeIdentifier)
                    ?? UTType(
                        filenameExtension:
                            (resource.originalFilename as NSString).pathExtension
                    )
                    ?? .image
                return resourceType.conforms(to: .rawImage) == isRAW
            }
            result.append(
                PhotoEditSourceOption(
                    id: "\(source.rawValue)-current-\(url.lastPathComponent)",
                    source: source,
                    displayName: isRAW
                        ? "RAW"
                        : type.preferredFilenameExtension?.uppercased() ?? "Image",
                    filename: matchingResource?.originalFilename ?? url.lastPathComponent,
                    type: type,
                    resource: nil,
                    contentInputURL: url
                )
            )
        }

        for resource in imageResources {
            let type = UTType(resource.uniformTypeIdentifier)
                ?? UTType(filenameExtension: (resource.originalFilename as NSString).pathExtension)
                ?? .image
            let isRAW = type.conforms(to: .rawImage)
            let source: PhotoEditSource = isRAW ? .raw : .rendered
            guard !result.contains(where: { $0.source == source }) else { continue }
            result.append(
                PhotoEditSourceOption(
                    id: "\(source.rawValue)-\(resource.originalFilename)",
                    source: source,
                    displayName: isRAW ? "RAW" : type.preferredFilenameExtension?.uppercased() ?? "JPEG",
                    filename: resource.originalFilename,
                    type: type,
                    resource: resource,
                    contentInputURL: nil
                )
            )
        }
        return result.sorted { lhs, rhs in
            if lhs.isRAW != rhs.isRAW { return lhs.isRAW }
            return lhs.displayName < rhs.displayName
        }
    }

    private func contentType(for input: PHContentEditingInput) -> UTType? {
        if #available(iOS 26.0, *) {
            return input.contentType
        }
        return input.uniformTypeIdentifier.flatMap(UTType.init)
    }

    private func write(resource: PHAssetResource, to url: URL) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: url,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func makeAdjustmentData(_ recipe: PhotoEditRecipe) -> PHAdjustmentData {
        let data = (try? JSONEncoder().encode(recipe)) ?? Data()
        return PHAdjustmentData(
            formatIdentifier: PhotoEditRecipe.formatIdentifier,
            formatVersion: PhotoEditRecipe.formatVersion,
            data: data
        )
    }

    private func decodeRecipe(_ adjustmentData: PHAdjustmentData?) -> PhotoEditRecipe? {
        guard let adjustmentData,
              adjustmentData.formatIdentifier == PhotoEditRecipe.formatIdentifier,
              adjustmentData.formatVersion == PhotoEditRecipe.formatVersion
        else { return nil }
        return try? JSONDecoder().decode(PhotoEditRecipe.self, from: adjustmentData.data)
    }

    private func commit(
        output: PHContentEditingOutput,
        to asset: PHAsset,
        includeMetadata: Bool
    ) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.contentEditingOutput = output
            if !includeMetadata {
                request.creationDate = nil
                request.location = nil
            }
        }
    }

    private func createFlatAsset(
        fileURL: URL,
        filename: String,
        sourceAsset: PHAsset,
        includeMetadata: Bool,
        album: PHAssetCollection?
    ) async throws -> String {
        var placeholderID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let creation = PHAssetCreationRequest.forAsset()
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.originalFilename = filename
            creation.addResource(with: .photo, fileURL: fileURL, options: resourceOptions)
            if includeMetadata {
                creation.creationDate = sourceAsset.creationDate
                creation.location = sourceAsset.location
            }
            guard let placeholder = creation.placeholderForCreatedAsset else { return }
            placeholderID = placeholder.localIdentifier
            if let album, album.canPerform(.addContent),
               let albumRequest = PHAssetCollectionChangeRequest(for: album) {
                albumRequest.addAssets([placeholder] as NSArray)
            }
        }
        guard let placeholderID else { throw PhotoEditingError.cannotCreateAsset }
        return placeholderID
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexPhoto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        return url
    }

    // MARK: Live Photo

    private func saveLivePhotoChanges(
        session: PhotoEditingSession,
        source: LoadedPhotoEditSource,
        output: PHContentEditingOutput,
        recipe: PhotoEditRecipe
    ) async throws {
        guard let context = PHLivePhotoEditingContext(
            livePhotoEditingInput: session.contentInput
        ) else {
            throw PhotoEditingError.cannotRender
        }
        let automaticMasks = try await renderer.automaticMaskImages(
            source: source.info,
            recipe: recipe
        )
        let frameRenderer = LivePhotoFrameRenderer(
            recipe: recipe,
            automaticMasks: automaticMasks.images
        )
        context.frameProcessor = { frame, _ in
            frameRenderer.render(frame.image)
        }
        try await context.saveLivePhoto(to: output, options: nil)
    }
}

/// PHLivePhotoEditingContext calls this block synchronously for every frame.
/// Subject/Sky inference is resolved once from the full-size still and scaled
/// across the motion resource; geometric and range masks remain frame-aware.
private final class LivePhotoFrameRenderer: @unchecked Sendable {
    private let recipe: PhotoEditRecipe
    private let automaticMasks: [UUID: CGImage]
    /// The overlay layer, rasterized on the first frame and reused for the rest.
    /// Every frame of the motion resource is the same size, so laying out Core Text
    /// ninety times over would cost seconds to draw the same pixels.
    private let overlayLock = NSLock()
    private var overlayLayer: (extent: CGRect, image: CIImage)?

    init(
        recipe: PhotoEditRecipe,
        automaticMasks: [UUID: CGImage]
    ) {
        self.recipe = recipe
        self.automaticMasks = automaticMasks
    }

    func render(_ input: CIImage) -> CIImage {
        var image = PhotoRenderService.applyAdjustments(
            recipe.adjustments,
            to: input,
            appliesExposure: true
        )
        image = PhotoRenderService.applyColor(recipe.color, to: image)
        image = PhotoRenderService.applyCurve(recipe.curve, to: image)
        image = PhotoRenderService.applyOptics(recipe.adjustments, to: image)
        image = PhotoRenderService.applyGeo(recipe.adjustments, to: image)
        image = PhotoRenderService.applyFilter(
            recipe.filter,
            intensity: recipe.filterIntensity,
            to: image
        )
        image = PhotoRenderService.applyCrop(recipe.crop, to: image)
        for mask in recipe.masks where mask.isVisible {
            let maskImage = renderMask(mask, over: image)
            let adjusted = PhotoRenderService.applyAdjustments(
                mask.adjustments,
                to: image,
                appliesExposure: true
            )
            image = PhotoRenderService.filtered(
                "CIBlendWithMask",
                image: adjusted,
                values: [
                    kCIInputBackgroundImageKey: image,
                    kCIInputMaskImageKey: maskImage,
                ]
            )
        }
        image = applyDrawing(to: image)
        return applyOverlays(to: image)
    }

    private func applyDrawing(to input: CIImage) -> CIImage {
        guard recipe.drawing?.hasVisibleEffect == true else { return input }
        let extent = input.extent
        // `PhotoRenderService.drawingLayer` caches by data + size, so the vector is
        // rasterized once for the clip and composited over every frame.
        guard let layer = PhotoRenderService.drawingLayer(recipe.drawing, extent: extent)
        else { return input }
        return layer.composited(over: input).cropped(to: extent)
    }

    private func applyOverlays(to input: CIImage) -> CIImage {
        guard !recipe.overlays.isEmpty else { return input }
        let extent = input.extent
        guard let layer = cachedOverlayLayer(for: extent) else { return input }
        return layer.composited(over: input).cropped(to: extent)
    }

    private func cachedOverlayLayer(for extent: CGRect) -> CIImage? {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        if let overlayLayer, overlayLayer.extent == extent { return overlayLayer.image }
        guard let layer = PhotoRenderService.overlayLayer(
            recipe.overlays,
            extent: extent
        ) else { return nil }
        overlayLayer = (extent, layer)
        return layer
    }

    private func renderMask(_ mask: PhotoMask, over image: CIImage) -> CIImage {
        let extent = image.extent.integral
        var accumulated = blackMask(extent)
        for component in mask.components {
            var incoming = componentMask(component, image: image).cropped(to: extent)
            if component.opacity < 0.999 {
                incoming = incoming.applyingFilter(
                    "CIColorMatrix",
                    parameters: [
                        "inputRVector": CIVector(x: component.opacity, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: component.opacity, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: component.opacity, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    ]
                )
            }
            let kernel = component.operation == .add
                ? PhotoRenderService.addMaskKernel
                : PhotoRenderService.subtractMaskKernel
            accumulated = kernel?.apply(
                extent: extent,
                arguments: [accumulated, incoming]
            ) ?? accumulated
        }
        if mask.isInverted, let kernel = PhotoRenderService.invertMaskKernel {
            accumulated = kernel.apply(
                extent: extent,
                arguments: [accumulated]
            ) ?? accumulated
        }
        return accumulated.cropped(to: extent)
    }

    private func componentMask(
        _ component: PhotoMaskComponent,
        image: CIImage
    ) -> CIImage {
        let extent = image.extent.integral
        switch component.kind {
        case .brush:
            return brushMask(component.brushStrokes, extent: extent)
        case .linearGradient:
            let start = imagePoint(component.startPoint, extent: extent)
            let end = imagePoint(component.endPoint, extent: extent)
            return CIFilter(
                name: "CILinearGradient",
                parameters: [
                    "inputPoint0": CIVector(cgPoint: start),
                    "inputPoint1": CIVector(cgPoint: end),
                    "inputColor0": CIColor.white,
                    "inputColor1": CIColor.black,
                ]
            )?.outputImage?.cropped(to: extent) ?? blackMask(extent)
        case .radialGradient:
            let center = imagePoint(component.center, extent: extent)
            let radiusX = max(1, component.radiusX * extent.width)
            let radiusY = max(1, component.radiusY * extent.height)
            return CIFilter(
                name: "CIRadialGradient",
                parameters: [
                    kCIInputCenterKey: CIVector(x: 0, y: 0),
                    "inputRadius0": max(0, 1 - component.feather),
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
                .cropped(to: extent) ?? blackMask(extent)
        case .subject, .sky:
            guard let mask = automaticMasks[component.id] else {
                return blackMask(extent)
            }
            return CIImage(cgImage: mask)
                .transformed(by:
                    CGAffineTransform(
                        scaleX: extent.width / CGFloat(mask.width),
                        y: extent.height / CGFloat(mask.height)
                    )
                )
                .transformed(by:
                    CGAffineTransform(
                        translationX: extent.minX,
                        y: extent.minY
                    )
                )
                .cropped(to: extent)
        case .luminanceRange:
            return PhotoRenderService.luminanceMaskKernel?.apply(
                extent: extent,
                arguments: [
                    image,
                    component.luminanceMinimum,
                    component.luminanceMaximum,
                    max(0.005, component.feather * 0.25),
                ]
            ) ?? blackMask(extent)
        case .colorRange:
            return PhotoRenderService.colorMaskKernel?.apply(
                extent: extent,
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
            ) ?? blackMask(extent)
        }
    }

    private func brushMask(_ strokes: [BrushStroke], extent: CGRect) -> CIImage {
        guard !strokes.isEmpty,
              let bitmap = CGContext(
                  data: nil,
                  width: max(1, Int(extent.width.rounded(.up))),
                  height: max(1, Int(extent.height.rounded(.up))),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return blackMask(extent) }
        bitmap.setFillColor(gray: 0, alpha: 1)
        bitmap.fill(CGRect(origin: .zero, size: extent.size))
        let shortEdge = min(extent.width, extent.height)
        // Shared with `PhotoRenderService.brushMask` on purpose: the two used to
        // carry copies of this loop that had already drifted apart on eraser blending
        // and on where the 1px floor sat.
        BrushStrokeRasterizer.draw(strokes, in: bitmap, shortEdge: shortEdge) { point in
            let mapped = imagePoint(point, extent: extent)
            return CGPoint(x: mapped.x - extent.minX, y: mapped.y - extent.minY)
        }
        guard let cgImage = bitmap.makeImage() else { return blackMask(extent) }
        return CIImage(cgImage: cgImage)
            .transformed(by:
                CGAffineTransform(translationX: extent.minX, y: extent.minY)
            )
    }

    private func blackMask(_ extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: extent)
    }

    private func imagePoint(_ point: NormalizedPoint, extent: CGRect) -> CGPoint {
        CGPoint(
            x: extent.minX + extent.width * point.x,
            y: extent.minY + extent.height * (1 - point.y)
        )
    }
}
