import CoreImage
import Foundation
import ImageIO
import os
import Photos
import UniformTypeIdentifiers
import UIKit
import ShotDexKit

struct PhotoEditSourceOption: Identifiable {
    let id: String
    let source: PhotoEditSource
    let displayName: String
    let filename: String
    let type: UTType
    fileprivate let resource: PHAssetResource?
    fileprivate let contentInputURL: URL?
    /// A server original already on disk (FS-17.06 §5): read in place, not
    /// copied into the session.
    fileprivate var localFileURL: URL? = nil

    var isRAW: Bool { type.conforms(to: .rawImage) }
}

@MainActor
final class PhotoEditingSession {
    let origin: PhotoEditOrigin
    /// Nil for a server photo: there is nothing in Photos to write to.
    let contentInput: PHContentEditingInput?
    let sourceOptions: [PhotoEditSourceOption]
    let recalledRecipe: PhotoEditRecipe?
    let temporaryDirectory: URL

    fileprivate init(
        origin: PhotoEditOrigin,
        contentInput: PHContentEditingInput?,
        sourceOptions: [PhotoEditSourceOption],
        recalledRecipe: PhotoEditRecipe?,
        temporaryDirectory: URL
    ) {
        self.origin = origin
        self.contentInput = contentInput
        self.sourceOptions = sourceOptions
        self.recalledRecipe = recalledRecipe
        self.temporaryDirectory = temporaryDirectory
    }

    var asset: PHAsset? { origin.asset }

    var isLivePhoto: Bool { asset?.mediaSubtypes.contains(.photoLive) ?? false }

    /// The asset and its PhotoKit input, for the paths that write back to
    /// Photos — which a server photo never takes.
    fileprivate func library() throws -> (asset: PHAsset, input: PHContentEditingInput) {
        guard let asset, let contentInput else { throw PhotoEditingError.unavailable }
        return (asset, contentInput)
    }
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
    /// The photo's saved edit already had a layer pasted from the watermark's
    /// preset, so it was not stamped again (FS-05.04 §5).
    var watermarkWasAlreadyThere = false
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
    /// Plays a scripted iCloud download before PhotoKit's own request, so
    /// the simulator shows the editor's download card (FS-02.06). PhotoKit's
    /// fetcher returns at once; nil does the same.
    var originalFetcher: (any OriginalFetching)?
    /// Where sessions put their `ShotDexPhoto-` folders: the temporary
    /// directory, or a test's own.
    private let temporaryRoot: URL

    init(
        renderer: PhotoRenderService = PhotoRenderService(),
        indexNewAsset: (@Sendable (String) async -> Void)? = nil,
        publishCreatedAsset: (@MainActor @Sendable (String) -> Void)? = nil,
        filenameIndexes: PhotoOutputFilenameIndexStore? = nil,
        temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) {
        self.temporaryRoot = temporaryRoot
        self.renderer = renderer
        self.indexNewAsset = indexNewAsset
        self.publishCreatedAsset = publishCreatedAsset
        self.filenameIndexes = filenameIndexes ?? PhotoOutputFilenameIndexStore()
    }

    /// Sessions kept alive for photos the user has just been on, newest
    /// last. Switching photos in a multi-photo run used to redo the whole
    /// `beginSession` — a `PHContentEditingInput` request, which is an iCloud
    /// round trip for anything not local — so stepping back to the photo you
    /// were on a second ago cost the same as opening it cold.
    ///
    /// Three: the one on screen and the two either side of it, which is what
    /// a filmstrip walk actually revisits. Each entry holds a PhotoKit input
    /// and a temporary directory, not a decoded image, so the cost is small
    /// and bounded.
    ///
    /// The photo the editor has open is never the one evicted: the
    /// multi-photo preloader warms neighbours into this cache while the canvas
    /// is still using its own entry, and evicting that entry would delete the
    /// source file out from under the live editor.
    private var sessions = EditingSessionCache<PhotoEditingSession>(limit: 3)

    /// Opens a session, reusing the cached one when this photo was open a
    /// moment ago. `isOnCanvas`: the editor's own photo, pinned against
    /// eviction until another photo takes the canvas.
    func beginSession(for asset: PHAsset, isOnCanvas: Bool = false) async throws -> PhotoEditingSession {
        try await beginSession(for: .asset(asset), isOnCanvas: isOnCanvas)
    }

    /// `progress` gets the iCloud download's 0…1 on the main actor, when the
    /// original has to come down (FS-02.06 AC-3).
    func beginSession(
        for origin: PhotoEditOrigin,
        isOnCanvas: Bool = false,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async throws -> PhotoEditingSession {
        if isOnCanvas { sessions.activeID = origin.id }
        if let cached = sessions.cached(origin.id) {
            return cached
        }
        let session = try await makeSession(for: origin, progress: progress)
        // Cancelled while it was waiting on iCloud — the editor closed: the
        // session goes now, not at the next launch's sweep (AC-4).
        guard !Task.isCancelled else {
            discard(session)
            throw CancellationError()
        }
        remember(session, for: origin.id)
        return session
    }

    /// A session for the multi-photo preloader (FS-03.09b §2). `keeps` puts
    /// it in the recent cache — a neighbour of the photo on screen, likely the
    /// next one opened. Otherwise it is the caller's, to hand to `endSession`
    /// when the previews are drawn: the preloader walks the whole run, and a
    /// session holds a full copy of the original, so twenty photos must not
    /// mean twenty copies.
    func preloadSession(
        for origin: PhotoEditOrigin,
        keeps: Bool,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async throws -> PhotoEditingSession {
        if let cached = sessions.cached(origin.id) {
            return cached
        }
        let session = try await makeSession(for: origin, progress: progress)
        // The editor may have closed, or the walk moved on, while this was
        // waiting on iCloud.
        guard !Task.isCancelled else {
            discard(session)
            throw CancellationError()
        }
        if keeps { remember(session, for: origin.id) }
        return session
    }

    private func remember(_ session: PhotoEditingSession, for id: String) {
        for dropped in sessions.remember(session, id: id) { discard(dropped) }
    }

    /// Drops a cached session for good — the only place its temporary
    /// directory is removed, so a session still in the cache keeps its files.
    private func discard(_ session: PhotoEditingSession) {
        let directory = session.temporaryDirectory
        guard directory.path.hasPrefix(temporaryRoot.path) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Everything the cache holds, released when the editor closes.
    func releaseCachedSessions() {
        for session in sessions.releaseAll() { discard(session) }
    }

    private func makeSession(
        for origin: PhotoEditOrigin,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async throws -> PhotoEditingSession {
        switch origin {
        case .asset(let asset): try await makeSession(for: asset, progress: progress)
        case .serverFile(let photo): try makeSession(for: photo)
        }
    }

    /// A server original fetched to disk: its files are the sources — the
    /// RAW and its JPEG/HEIC twin, when both came down — and there is no
    /// saved recipe to recall (FS-17.06 §5).
    private func makeSession(for photo: FetchedServerPhoto) throws -> PhotoEditingSession {
        let options = photo.files.map { fetched in
            let type = UTType(filenameExtension: (fetched.file.name as NSString).pathExtension) ?? .image
            let isRAW = type.conforms(to: .rawImage)
            let source: PhotoEditSource = isRAW ? .raw : .rendered
            return PhotoEditSourceOption(
                id: "\(source.rawValue)-\(fetched.file.name)",
                source: source,
                displayName: isRAW ? "RAW" : type.preferredFilenameExtension?.uppercased() ?? "JPEG",
                filename: fetched.file.name,
                type: type,
                resource: nil,
                contentInputURL: nil,
                localFileURL: fetched.url
            )
        }.sorted { lhs, rhs in
            if lhs.isRAW != rhs.isRAW { return lhs.isRAW }
            return lhs.displayName < rhs.displayName
        }
        guard !options.isEmpty else { throw PhotoEditingError.missingSource }
        return PhotoEditingSession(
            origin: .serverFile(photo),
            contentInput: nil,
            sourceOptions: options,
            recalledRecipe: nil,
            temporaryDirectory: try makeTemporaryDirectory()
        )
    }

    private func makeSession(
        for asset: PHAsset,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async throws -> PhotoEditingSession {
        guard asset.mediaType == .image else { throw PhotoEditingError.unavailable }
        let report: @Sendable (Double) -> Void = { value in
            Task { @MainActor in progress?(value) }
        }
        try await originalFetcher?.scriptedTransfer(for: asset.localIdentifier, progress: report)
        let input = try await requestContentEditingInput(for: asset, progress: report)
        try Self.checkComplete(input, of: asset)
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
            origin: .asset(asset),
            contentInput: input,
            sourceOptions: options,
            recalledRecipe: recalledRecipe,
            temporaryDirectory: temporaryDirectory
        )
    }

    /// Ends a session the caller owns. A session the cache still holds —
    /// recent, or retired by a save — is *not* torn down: deleting its
    /// temporary directory would leave the next open, or the canvas still
    /// drawing from it, reading files that are gone.
    func endSession(_ session: PhotoEditingSession) {
        guard !sessions.owns(session) else { return }
        discard(session)
    }

    func loadSource(
        _ option: PhotoEditSourceOption,
        in session: PhotoEditingSession
    ) async throws -> LoadedPhotoEditSource {
        let fileURL = option.localFileURL ?? session.temporaryDirectory
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
        var info = try await inspect(fileURL, typeHint: option.type, filename: option.filename)
        // Names the photo across launches, so its mattes are read back from
        // disk instead of worked out again (FS-03.15d §5).
        info.persistentIdentity = "\(session.origin.id)|\(option.id)|\(session.origin.stamp)"
        return LoadedPhotoEditSource(optionID: option.id, info: info)
    }

    /// The kit's inspection, with the decoder's refusal turned into the
    /// message that names the camera and the iOS version (FS-03.04b §3).
    private func inspect(_ url: URL, typeHint: UTType, filename: String?) async throws -> PhotoRenderSourceInfo {
        do {
            return try await renderer.inspectSource(at: url, typeHint: typeHint)
        } catch PhotoEditingError.unsupportedRAW {
            throw RAWFileCamera.error(for: url, filename: filename)
        }
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
        metadata: MetadataLevel,
        album: PHAssetCollection?
    ) async throws -> PhotoSaveResult {
        let (asset, contentInput) = try session.library()
        let renderRecipe = renderRecipe ?? recipe
        let resolvedRequested = await renderer.resolvedOutputFormat(
            requested: requestedFormat,
            sourceType: source.info.type,
            sourceIsRAW: source.info.isRAW
        )
        let supportedTypes = PHContentEditingOutput(
            contentEditingInput: contentInput
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
            metadata: metadata
        )
        let final = try await renderer.render(source: source.info, recipe: renderRecipe)
        try await renderer.write(
            final,
            to: renderedURL,
            format: actualFormat,
            quality: 1,
            metadata: metadata
        )

        var attachedRecipe = recipe
        attachedRecipe.sourceAssetIdentifier =
            recipe.sourceAssetIdentifier ?? asset.localIdentifier
        attachedRecipe.sourceFilename =
            session.sourceOptions.first(where: { $0.id == source.optionID })?.filename
        let filenameReservation = filenameIndexes.reserve(
            sourceAssetIdentifier:
                attachedRecipe.sourceAssetIdentifier ?? asset.localIdentifier,
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
                let carryOver = AssetMetadataCarryOver(level: metadata)
                if carryOver.keepsDate { creation.creationDate = asset.creationDate }
                if carryOver.keepsLocation { creation.location = asset.location }
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
    ///
    /// No metadata choice: the photo stays in the library, so its date and
    /// location are the user's own data, not something to strip on the way
    /// out — and Revert to Original would not bring them back (FS-08.06 AC-17).
    func saveChanges(
        session: PhotoEditingSession,
        source: LoadedPhotoEditSource,
        recipe: PhotoEditRecipe,
        renderRecipe: PhotoEditRecipe? = nil,
        requestedFormat: PhotoOutputFormat
    ) async throws -> PhotoSaveResult {
        let (asset, contentInput) = try session.library()
        let renderRecipe = renderRecipe ?? recipe
        let output = PHContentEditingOutput(contentEditingInput: contentInput)
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
            try await commit(output: output, to: asset)
            sessions.retire(asset.localIdentifier)
            let actualFormat: PhotoOutputFormat =
                output.defaultRenderedContentType?.conforms(to: .heic) == true
                    ? .heic
                    : .jpeg
            return PhotoSaveResult(
                assetID: asset.localIdentifier,
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
            // Save Changes keeps everything: the photo never leaves (AC-17).
            metadata: .all
        )
        output.adjustmentData = makeAdjustmentData(recipe)
        try await commit(output: output, to: asset)
        // The photo now carries the saved recipe and a new modification
        // date: the next open must read PhotoKit again, not reuse this
        // session's pre-save input (FS-03.09b AC-5).
        sessions.retire(asset.localIdentifier)
        return PhotoSaveResult(
            assetID: asset.localIdentifier,
            format: actualFormat,
            fellBackToJPEG: actualFormat != resolvedRequested
        )
    }

    /// `preparedOriginal`: the photo's original, already downloaded by the
    /// Resize preparation (FS-02.06 §5). Read from there, so nothing comes
    /// from iCloud mid-batch; otherwise the session reads Photos as before.
    func compress(
        asset: PHAsset,
        options: PhotoExportOptions,
        album: PHAssetCollection?,
        cropAnchor: NormalizedPoint? = nil,
        preparedOriginal: URL? = nil
    ) async throws -> PhotoSaveResult {
        if let preparedOriginal {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let type = UTType(filenameExtension: preparedOriginal.pathExtension) ?? .image
            let resources = PHAssetResource.assetResources(for: asset)
            let name = resources.first { $0.type == .photo }?.originalFilename ?? resources.first?.originalFilename
            let info = try await inspect(preparedOriginal, typeHint: type, filename: name)
            // No session on this path: the saved edit comes from the asset's
            // adjustment resource, a few kilobytes.
            let saved = options.watermark == nil ? nil : await savedRecipe(of: asset)
            return try await compress(
                source: info, sourceName: name, sourceAssetIdentifier: asset.localIdentifier,
                asset: asset, directory: directory, options: options, album: album, cropAnchor: cropAnchor,
                savedRecipe: saved
            )
        }
        let session = try await beginSession(for: asset)
        defer { endSession(session) }
        guard let option = session.preferredSource(for: nil) else {
            throw PhotoEditingError.missingSource
        }
        // A pair whose RAW the decoder can't read is resized from its JPEG
        // (FS-03.04b §4).
        let source = try await ReadableSource.load(
            preferred: option, among: session.sourceOptions, isRAW: \.isRAW
        ) { try await loadSource($0, in: session) }
        return try await compress(
            source: source.info,
            sourceName: session.sourceOptions.first(where: { $0.id == source.optionID })?.filename,
            sourceAssetIdentifier: session.recalledRecipe?.sourceAssetIdentifier ?? asset.localIdentifier,
            asset: asset, directory: session.temporaryDirectory, options: options, album: album, cropAnchor: cropAnchor,
            savedRecipe: session.recalledRecipe
        )
    }

    private func compress(
        source: PhotoRenderSourceInfo,
        sourceName: String?,
        sourceAssetIdentifier: String,
        asset: PHAsset,
        directory: URL,
        options: PhotoExportOptions,
        album: PHAssetCollection?,
        cropAnchor: NormalizedPoint?,
        savedRecipe: PhotoEditRecipe?
    ) async throws -> PhotoSaveResult {
        let recipe = PhotoEditRecipe.identity
        // The file already carries the edit — a layer pasted from this very
        // preset included — so it is not stamped twice (FS-05.04 §5).
        let wasAlreadyThere = options.watermark.map {
            WatermarkPlan.alreadyStamped(savedLayers: savedRecipe?.overlays, presetID: $0.presetID)
        } ?? false
        let rendered = try await renderer.render(source: source, recipe: recipe)
        let resized = await renderer.resize(
            rendered,
            preset: options.preset,
            cropAnchor: cropAnchor ?? options.cropAnchor
        )
        // Last, at the size the file is written at (FS-05.04 §3).
        let stamped = await renderer.applyingWatermark(wasAlreadyThere ? nil : options.watermark, to: resized)
        let requestedFormat = await renderer.resolvedOutputFormat(
            requested: options.format,
            sourceType: source.type,
            sourceIsRAW: source.isRAW
        )
        let format = requestedFormat == .heic && !Self.supportsHEICEncoding
            ? .jpeg
            : requestedFormat
        let outputURL = directory.appendingPathComponent(
            "compressed.\(format.fileExtension)"
        )
        try await renderer.write(
            stamped,
            to: outputURL,
            format: format,
            quality: options.quality,
            metadata: options.metadata
        )
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
                metadata: options.metadata,
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
            fellBackToJPEG: format != requestedFormat,
            watermarkWasAlreadyThere: wasAlreadyThere
        )
    }

    /// The edit saved with a photo, read from its adjustment resource — for a
    /// path that has the original but no editing session (an original the
    /// Resize preparation downloaded). Nil when the photo has no ShotDex edit.
    func savedRecipe(of asset: PHAsset) async -> PhotoEditRecipe? {
        guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .adjustmentData })
        else { return nil }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let data: Data? = await withCheckedContinuation { continuation in
            var collected = Data()
            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                collected.append(chunk)
            } completionHandler: { error in
                continuation.resume(returning: error == nil ? collected : nil)
            }
        }
        return data.flatMap(Self.recipe(fromAdjustmentResource:))
    }

    /// Photos keeps an edit's adjustment data as a property list: the format
    /// identifier, its version and the app's bytes. Only ShotDex's own format
    /// decodes; an edit made by another app is no edit of ours.
    nonisolated static func recipe(fromAdjustmentResource data: Data) -> PhotoEditRecipe? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["adjustmentFormatIdentifier"] as? String == PhotoEditRecipe.formatIdentifier,
              let bytes = plist["adjustmentData"] as? Data
        else { return nil }
        return try? JSONDecoder().decode(PhotoEditRecipe.self, from: bytes)
    }

    /// The edit drawn at full size into a file this app owns — a server
    /// photo's export (FS-17.06 §6), which Photos never sees.
    func writeRender(
        source: LoadedPhotoEditSource,
        recipe: PhotoEditRecipe,
        format: PhotoOutputFormat,
        metadata: MetadataLevel,
        resize: ResizePreset? = nil,
        to url: URL
    ) async throws {
        var rendered = try await renderer.render(source: source.info, recipe: recipe)
        var quality = 1.0
        if let resize {
            rendered = await renderer.resize(rendered, preset: resize, cropAnchor: .center)
            quality = resize.quality
        }
        try await renderer.write(rendered, to: url, format: format, quality: quality, metadata: metadata)
    }

    func deleteCreatedAssets(ids: [String]) async throws {
        try await deleteAssets(ids: ids)
    }

    /// Deletes library assets by identifier. Photos shows its own system
    /// confirmation before removing user originals; deletions land in Recently
    /// Deleted, not permanent. Used both for cancellation rollback of exported
    /// copies and for removing originals after a successful compress.
    func deleteAssets(ids: [String]) async throws {
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
        guard let contentInput = session.contentInput else {
            // A server photo is written by ShotDex itself, not by Photos.
            return format == .jpeg || (format == .heic && Self.supportsHEICEncoding)
        }
        return PHContentEditingOutput(
            contentEditingInput: contentInput
        ).supportedRenderedContentTypes.contains(format.uniformType)
    }

    static var supportsHEICEncoding: Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(UTType.heic.identifier)
    }

    // MARK: PhotoKit

    /// The photo's editing input, downloading the original from iCloud when
    /// it is not here. Cancelling the task cancels PhotoKit's request at once
    /// (FS-02.06 AC-4) — and resumes here whether or not PhotoKit calls back.
    private func requestContentEditingInput(
        for asset: PHAsset,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> PHContentEditingInput {
        let request = ContentEditingRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.continuation = continuation
                let options = PHContentEditingInputRequestOptions()
                options.isNetworkAccessAllowed = true
                options.canHandleAdjustmentData = { adjustmentData in
                    adjustmentData.formatIdentifier == PhotoEditRecipe.formatIdentifier
                        && adjustmentData.formatVersion == PhotoEditRecipe.formatVersion
                }
                if let progress {
                    options.progressHandler = { value, _ in progress(value) }
                }
                let id = asset.requestContentEditingInput(with: options) { input, info in
                    if let input {
                        request.finish(.success(input))
                    } else if let error = info[PHContentEditingInputErrorKey] as? Error {
                        request.finish(.failure(error))
                    } else {
                        request.finish(.failure(PhotoEditingError.unavailable))
                    }
                }
                if request.start(id: id) {
                    asset.cancelContentEditingInputRequest(id)
                }
            }
        } onCancel: {
            if let id = request.cancel() {
                Task { @MainActor in asset.cancelContentEditingInputRequest(id) }
            }
        }
    }

    /// The input's file must be the whole photo (FS-02.06 §3): for a photo
    /// with no edit of anyone's the file is the original, and its size is
    /// the photo's. An edited photo's input is the unedited original, whose
    /// size the crop has since changed, so it is not judged here.
    private static func checkComplete(_ input: PHContentEditingInput, of asset: PHAsset) throws {
        guard input.adjustmentData == nil, let url = input.fullSizeImageURL,
              let measured = OriginalCompleteness.measure(url) else { return }
        let photo = PixelSize(width: asset.pixelWidth, height: asset.pixelHeight)
        guard OriginalCompleteness.isSufficient(
            received: measured.size.oriented(measured.orientation), requestedLongEdge: photo.longEdge, photo: photo
        ) else {
            // A RAW Photos holds whole but the decoder refuses (a cut-off or
            // unknown file) reads as "only a preview here": it is the RAW
            // message, not an iCloud one (FS-03.04b §3).
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) == true,
               !PhotoRenderService.canDecodeRAW(at: url) {
                throw RAWFileCamera.error(for: url, filename: url.lastPathComponent)
            }
            throw OriginalFetchError.incomplete
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

    /// Only the edit changes; the asset's date and location stay as they are.
    private func commit(output: PHContentEditingOutput, to asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.contentEditingOutput = output
        }
    }

    private func createFlatAsset(
        fileURL: URL,
        filename: String,
        sourceAsset: PHAsset,
        metadata: MetadataLevel,
        album: PHAssetCollection?
    ) async throws -> String {
        var placeholderID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let creation = PHAssetCreationRequest.forAsset()
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.originalFilename = filename
            creation.addResource(with: .photo, fileURL: fileURL, options: resourceOptions)
            let carryOver = AssetMetadataCarryOver(level: metadata)
            if carryOver.keepsDate { creation.creationDate = sourceAsset.creationDate }
            if carryOver.keepsLocation { creation.location = sourceAsset.location }
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
        let url = temporaryRoot
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
        guard let contentInput = session.contentInput,
              let context = PHLivePhotoEditingContext(livePhotoEditingInput: contentInput)
        else {
            throw PhotoEditingError.cannotRender
        }
        let automaticMasks = try await renderer.automaticMaskImages(
            source: source.info,
            recipe: recipe
        )
        let frameRenderer = LivePhotoFrameRenderer(
            recipe: recipe,
            source: source.info,
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
final class LivePhotoFrameRenderer: @unchecked Sendable {
    private let recipe: PhotoEditRecipe
    /// The still's source, for its EXIF focal length: the lens profile of a
    /// motion frame is the still's, since it is the same lens at the same focal.
    private let source: PhotoRenderSourceInfo
    private let automaticMasks: [UUID: CGImage]
    /// The overlay layer, rasterized on the first frame and reused for the rest.
    /// Every frame of the motion resource is the same size, so laying out Core Text
    /// ninety times over would cost seconds to draw the same pixels.
    private let overlayLock = NSLock()
    private var overlayLayer: (extent: CGRect, image: CIImage)?

    init(
        recipe: PhotoEditRecipe,
        source: PhotoRenderSourceInfo,
        automaticMasks: [UUID: CGImage]
    ) {
        self.recipe = recipe
        self.source = source
        self.automaticMasks = automaticMasks
    }

    func render(_ input: CIImage) -> CIImage {
        // The same stage list as the still, so a Live Photo's motion frames
        // cannot drift from its key frame.
        var image = PhotoRenderService.applyPreMaskStages(
            of: recipe,
            source: source,
            appliesExposure: true,
            to: input
        )
        for mask in recipe.masks where mask.isVisible {
            let maskImage = renderMask(mask, over: image)
            let adjusted = PhotoRenderService.applyMaskAdjustments(of: mask, to: image)
            image = PhotoRenderService.filtered(
                "CIBlendWithMask",
                image: adjusted,
                values: [
                    kCIInputBackgroundImageKey: image,
                    kCIInputMaskImageKey: maskImage,
                ]
            )
        }
        image = PhotoRenderService.applyPostMaskStages(of: recipe, to: image)
        // Drawing layers are overlays now, rasterized in stack order with the rest.
        return applyOverlays(to: image)
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
        case .subject, .object, .people, .sky, .depthRange, .faceSkin, .eyes, .lips:
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

/// One `requestContentEditingInput` call: resumes its continuation exactly
/// once, whether PhotoKit answers, the task is cancelled first, or both.
private final class ContentEditingRequest: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var id: PHContentEditingInputRequestID?
    private var isCancelled = false
    private var isDone = false
    private var pending: Result<PHContentEditingInput, Error>?
    private var stored: CheckedContinuation<PHContentEditingInput, Error>?

    /// The continuation to resume. A result that came first — the task was
    /// cancelled before the request began — resumes it at once.
    var continuation: CheckedContinuation<PHContentEditingInput, Error>? {
        get { lock.withLock { stored } }
        set {
            let early: Result<PHContentEditingInput, Error>? = lock.withLock {
                stored = newValue
                defer { pending = nil }
                return pending
            }
            if let early { newValue?.resume(with: early) }
        }
    }

    /// Records PhotoKit's id; true when the task was cancelled before it
    /// existed, so the caller cancels the request at once.
    func start(id: PHContentEditingInputRequestID) -> Bool {
        lock.withLock {
            self.id = id
            return isCancelled
        }
    }

    /// The id to cancel, once; the continuation resumes with cancellation.
    func cancel() -> PHContentEditingInputRequestID? {
        let id: PHContentEditingInputRequestID? = lock.withLock {
            isCancelled = true
            return self.id
        }
        finish(.failure(CancellationError()))
        return id
    }

    func finish(_ result: Result<PHContentEditingInput, Error>) {
        let continuation: CheckedContinuation<PHContentEditingInput, Error>? = lock.withLock {
            guard !isDone else { return nil }
            isDone = true
            if stored == nil { pending = result }
            return stored
        }
        continuation?.resume(with: result)
    }
}
