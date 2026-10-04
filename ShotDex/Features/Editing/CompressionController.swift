import Photos
import SwiftUI
import UIKit
import ShotDexKit

struct CompressionFailure: Identifiable {
    let id = UUID()
    let filename: String
    let message: String
}

/// What Resize does to the library, one photo at a time. The app's comes
/// from `PhotoEditingService`; a test's counts what would have been created
/// and deleted.
struct ResizeOperations {
    /// Makes the resized copy of a photo; `prepared` is its original when
    /// the preparation downloaded it (FS-02.06 §5); `watermark` is that
    /// photo's stamp, tokens filled (FS-05.04).
    var compress: @MainActor (OriginalItem, _ prepared: URL?, _ watermark: WatermarkStamp?) async throws -> PhotoSaveResult
    var deleteOriginals: @MainActor ([String]) async throws -> Void
    var removeCreated: @MainActor ([String]) async throws -> Void
}

@MainActor
@Observable
final class CompressionController {
    let assets: [PHAsset]
    /// The batch, one item per photo, in order.
    let photos: [OriginalItem]
    let sourceAlbum: PHAssetCollection?

    private let service: PhotoEditingService?
    private let presetStore: CompressionPresetStore?
    private let fetcher: any OriginalFetching
    private let gate: IndexInteractionGate?
    private let availableBytes: @Sendable () -> Int64?
    /// The forms' remembered watermark (FS-05.04 §5) and the presets it
    /// points at. Nil in a test that does not stamp.
    let watermarkSettings: WatermarkSettingsStore?
    let signaturePresets: SignaturePresetStore?
    /// Token values of one photo, from the index — the same source the editor
    /// resolves `{camera}` from.
    @ObservationIgnored private let tokenValues: @MainActor (String) -> OverlayTokenValues
    @ObservationIgnored private var operations: ResizeOperations!
    private var previewSession: PhotoEditingSession?
    private var previewSource: LoadedPhotoEditSource?

    var selectedPresetID = ResizePreset.original.id
    var quality = 0.8
    var format: PhotoOutputFormat = .preserve
    /// What the resized copy keeps; starts at the Settings default
    /// (FS-08.06 §4).
    var metadata = MetadataLevel.sharingDefault()
    /// Delete each source photo once its compressed copy is saved. On by default
    /// — compressing is normally a replace, not a duplicate.
    var deleteOriginals = true
    var cropAnchor = NormalizedPoint.center
    var previewImage: UIImage?

    private(set) var estimatedBytes: Int?
    private(set) var isLoading = true
    private(set) var isEstimating = false
    private(set) var isExporting = false
    private(set) var isDeletingOriginals = false
    /// The originals of the batch are being prepared (FS-02.06 §5): nothing
    /// is created or deleted until this ends.
    private(set) var isPreparing = false
    /// The preparation the processing modal draws its download line from.
    private(set) var preparation: OriginalPreparation?
    private(set) var processedCount = 0
    private(set) var createdAssetIDs: [String] = []
    private(set) var compressedOriginalIDs: [String] = []
    private(set) var deletedOriginalCount = 0
    private(set) var fallbackToJPEGCount = 0
    /// What the watermark did across the run (FS-05.04 §5).
    private(set) var watermarkTally = WatermarkTally()
    private(set) var failures: [CompressionFailure] = []
    private(set) var didFinish = false
    private(set) var wasCancelled = false
    private(set) var rollbackErrorMessage: String?
    private(set) var deleteOriginalsErrorMessage: String?
    private(set) var errorMessage: String?

    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    init(
        assets: [PHAsset],
        sourceAlbum: PHAssetCollection?,
        service: PhotoEditingService,
        presetStore: CompressionPresetStore,
        fetcher: any OriginalFetching = PhotoKitOriginalFetcher(),
        gate: IndexInteractionGate? = nil,
        availableBytes: @escaping @Sendable () -> Int64? = { DiskSpace.availableBytes() },
        watermarkSettings: WatermarkSettingsStore? = nil,
        signaturePresets: SignaturePresetStore? = nil,
        tokenValues: @escaping @MainActor (String) -> OverlayTokenValues = { _ in .empty }
    ) {
        self.assets = assets
        self.photos = assets.map { OriginalItem(asset: $0) }
        self.sourceAlbum = sourceAlbum
        self.service = service
        self.presetStore = presetStore
        self.fetcher = fetcher
        self.gate = gate
        self.availableBytes = availableBytes
        self.watermarkSettings = watermarkSettings
        self.signaturePresets = signaturePresets
        self.tokenValues = tokenValues
        let byID = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        self.operations = ResizeOperations(
            compress: { [weak self] photo, prepared, watermark in
                guard let self, let asset = byID[photo.id] else { throw PhotoEditingError.unavailable }
                var options = self.exportOptions
                options.watermark = watermark
                return try await service.compress(
                    asset: asset,
                    options: options,
                    album: self.sourceAlbum,
                    cropAnchor: self.photos.count > 1 ? .center : self.cropAnchor,
                    preparedOriginal: prepared
                )
            },
            deleteOriginals: { try await service.deleteAssets(ids: $0) },
            removeCreated: { try await service.deleteCreatedAssets(ids: $0) }
        )
    }

    /// A batch with no library behind it: the tests' (FS-02.06 AC-9, 10, 16).
    init(
        photos: [OriginalItem],
        operations: ResizeOperations,
        fetcher: any OriginalFetching,
        gate: IndexInteractionGate? = nil,
        availableBytes: @escaping @Sendable () -> Int64? = { nil },
        watermarkSettings: WatermarkSettingsStore? = nil,
        signaturePresets: SignaturePresetStore? = nil,
        tokenValues: @escaping @MainActor (String) -> OverlayTokenValues = { _ in .empty }
    ) {
        self.assets = []
        self.photos = photos
        self.sourceAlbum = nil
        self.service = nil
        self.presetStore = nil
        self.fetcher = fetcher
        self.gate = gate
        self.availableBytes = availableBytes
        self.watermarkSettings = watermarkSettings
        self.signaturePresets = signaturePresets
        self.tokenValues = tokenValues
        self.operations = operations
    }

    // MARK: Watermark (FS-05.04)

    /// The watermark this form stamps, before tokens: nil when it is off or
    /// its preset is gone.
    var watermarkTemplate: WatermarkStamp? {
        guard let watermarkSettings, let signaturePresets else { return nil }
        return watermarkSettings.formStamp(in: signaturePresets.presets)
    }

    /// The stamp for one photo of the batch, its tokens filled from that
    /// photo's own metadata.
    func watermarkStamp(for photoID: String) -> WatermarkStamp? {
        watermarkTemplate?.resolved(with: tokenValues(photoID))
    }

    /// What the watermark does to one photo; nil when it is off.
    func watermarkDecision(for photoID: String) -> WatermarkDecision? {
        watermarkTemplate.map { WatermarkPlan.decide($0, values: tokenValues(photoID)) }
    }

    var presets: [ResizePreset] { presetStore?.allPresets ?? [] }

    var selectedPreset: ResizePreset {
        presets.first(where: { $0.id == selectedPresetID }) ?? .original
    }

    var exportOptions: PhotoExportOptions {
        var preset = selectedPreset
        preset.quality = quality
        preset.format = format
        return PhotoExportOptions(
            format: format,
            quality: quality,
            preset: preset,
            metadata: metadata,
            cropAnchor: photos.count > 1 ? .center : cropAnchor
        )
    }

    /// A finished batch worth no summary: everything saved, nothing to report.
    /// The screen dismisses straight through instead of showing an empty receipt.
    var finishedCleanly: Bool {
        didFinish
            && !wasCancelled
            && failures.isEmpty
            && fallbackToJPEGCount == 0
            && !watermarkTally.isWorthReporting
            && rollbackErrorMessage == nil
            && deleteOriginalsErrorMessage == nil
    }

    var progressFraction: Double {
        guard !photos.isEmpty else { return 0 }
        return Double(processedCount) / Double(photos.count)
    }

    var estimatedSizeText: String? {
        guard let estimatedBytes else { return nil }
        if assets.count == 1 {
            return "~\(ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file))"
        }
        let total = Int64(estimatedBytes) * Int64(assets.count)
        return "~\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) total"
    }

    var sourceIsRAW: Bool { previewSource?.info.isRAW == true }
    var supportsHEICEncoding: Bool { PhotoEditingService.supportsHEICEncoding }
    var willFallbackToJPEG: Bool {
        guard !supportsHEICEncoding else { return false }
        if format == .heic { return true }
        return format == .preserve
            && previewSource?.info.type.conforms(to: .heic) == true
    }

    func load() async {
        guard let service, !assets.isEmpty else {
            errorMessage = "No photos were selected."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // The preview is the first photo the decoder can read: a RAW it
            // can't open fails in the run's list, not the whole sheet
            // (FS-03.04b AC-14).
            let (session, source) = try await ReadableSource.firstLoadable(assets) { asset in
                let session = try await service.beginSession(for: asset)
                do {
                    guard let option = session.preferredSource(for: nil) else {
                        throw PhotoEditingError.missingSource
                    }
                    let source = try await ReadableSource.load(
                        preferred: option, among: session.sourceOptions, isRAW: \.isRAW
                    ) { try await service.loadSource($0, in: session) }
                    return (session, source)
                } catch {
                    service.endSession(session)
                    throw error
                }
            }.loaded
            previewSession = session
            previewSource = source
            format = source.info.isRAW ? .jpeg : .preserve
            await updatePreviewAndEstimate()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func close() {
        previewTask?.cancel()
        exportTask?.cancel()
        preparation?.cancel()
        if let previewSession {
            service?.endSession(previewSession)
        }
    }

    func choosePreset(_ id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        selectedPresetID = id
        if !preset.isBuiltIn {
            quality = preset.quality
            format = preset.format
        }
        schedulePreviewUpdate()
    }

    func schedulePreviewUpdate() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            await self.updatePreviewAndEstimate()
        }
    }

    func scheduleEstimate() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, let self else { return }
            await self.updateEstimate()
        }
    }

    func startExport() {
        guard !isExporting else { return }
        isExporting = true
        isDeletingOriginals = false
        didFinish = false
        wasCancelled = false
        processedCount = 0
        createdAssetIDs = []
        compressedOriginalIDs = []
        deletedOriginalCount = 0
        fallbackToJPEGCount = 0
        watermarkTally = WatermarkTally(presetName: watermarkTemplate?.name ?? "")
        failures = []
        rollbackErrorMessage = nil
        deleteOriginalsErrorMessage = nil

        exportTask = Task { [weak self] in
            guard let self else { return }
            // §5 first: every original is here, or the user has chosen,
            // before a single copy is created or an original deleted.
            let preparation = OriginalPreparation(
                items: self.photos, fetcher: self.fetcher, gate: self.gate, availableBytes: self.availableBytes
            )
            self.preparation = preparation
            self.isPreparing = true
            let outcome = await preparation.run()
            self.isPreparing = false
            defer { preparation.removeFiles() }
            guard case .ready(let prepared, let skipped) = outcome, !Task.isCancelled, !self.wasCancelled else {
                // Cancelled while downloading: nothing was made, so there is
                // nothing to roll back — back to the form.
                self.preparation = nil
                self.isExporting = false
                self.wasCancelled = false
                return
            }
            for photo in self.photos where skipped.contains(photo.id) {
                self.failures.append(CompressionFailure(
                    filename: photo.filename,
                    message: String(localized: "Couldn't be downloaded from iCloud.", comment: "Resize summary: a photo left out")
                ))
            }
            for photo in self.photos where !skipped.contains(photo.id) {
                if Task.isCancelled { break }
                do {
                    let decision = self.watermarkDecision(for: photo.id)
                    let stamp: WatermarkStamp? = if case .stamp(let stamp) = decision { stamp } else { nil }
                    let result = try await self.operations.compress(photo, prepared[photo.id], stamp)
                    if let decision { self.watermarkTally.record(decision, filename: photo.filename) }
                    self.createdAssetIDs.append(result.assetID)
                    self.compressedOriginalIDs.append(photo.id)
                    if result.fellBackToJPEG {
                        self.fallbackToJPEGCount += 1
                    }
                } catch {
                    self.failures.append(
                        CompressionFailure(
                            filename: photo.filename,
                            message: error.localizedDescription
                        )
                    )
                }
                self.processedCount += 1
            }

            if Task.isCancelled || self.wasCancelled {
                await self.removeCreatedAssetsAfterCancellation()
            } else {
                await self.deleteOriginalsIfRequested()
                self.isExporting = false
                self.didFinish = true
            }
        }
    }

    /// Cancel in the processing modal. While the originals are still
    /// downloading nothing has been made, so it stops at once (AC-10);
    /// later it removes the copies already saved.
    func cancelExport() {
        guard isExporting else { return }
        wasCancelled = true
        if isPreparing {
            preparation?.cancel()
        }
        exportTask?.cancel()
    }

    func clearError() {
        errorMessage = nil
    }

    private func updatePreviewAndEstimate() async {
        guard let service, let previewSource else { return }
        do {
            let rendered = try await service.renderer.render(
                source: previewSource.info,
                recipe: .identity,
                maximumDimension: 2_000
            )
            let resized = await service.renderer.resize(
                rendered,
                preset: exportOptions.preset,
                cropAnchor: assets.count > 1 ? .center : cropAnchor
            )
            // The same raster as the file gets, at the preview's size: the
            // block is placed by the short edge, so it lands in proportion.
            let stamped = await service.renderer.applyingWatermark(
                photos.first.flatMap { watermarkStamp(for: $0.id) },
                to: resized
            )
            let cgImage = try await service.renderer.previewImage(stamped)
            previewImage = UIImage(cgImage: cgImage)
            await updateEstimate()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateEstimate() async {
        guard let service, let previewSession, let previewSource else { return }
        isEstimating = true
        defer { isEstimating = false }
        do {
            estimatedBytes = try await service.estimateCompressedSize(
                session: previewSession,
                source: previewSource,
                options: exportOptions
            )
        } catch {
            estimatedBytes = nil
        }
    }

    /// After a successful batch, delete the source photos whose compressed copy
    /// was saved. Only runs when `deleteOriginals` is on. Photos shows its own
    /// system confirmation; deletions land in Recently Deleted. A failure here is
    /// non-fatal — the compressed copies are already saved.
    private func deleteOriginalsIfRequested() async {
        guard deleteOriginals, !compressedOriginalIDs.isEmpty else { return }
        isDeletingOriginals = true
        defer { isDeletingOriginals = false }
        do {
            // Only the photos whose copy was saved: one left out at the
            // download, or one that failed, keeps its original (AC-9).
            try await operations.deleteOriginals(compressedOriginalIDs)
            deletedOriginalCount = compressedOriginalIDs.count
        } catch {
            deleteOriginalsErrorMessage = error.localizedDescription
        }
    }

    private func removeCreatedAssetsAfterCancellation() async {
        do {
            try await operations.removeCreated(createdAssetIDs)
            createdAssetIDs.removeAll()
        } catch {
            let message =
                "Photos couldn't remove every exported copy: \(error.localizedDescription)"
            rollbackErrorMessage = message
            errorMessage = "Export stopped, but \(message)"
        }
        isExporting = false
        didFinish = true
    }

}
