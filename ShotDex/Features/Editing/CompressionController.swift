import Photos
import SwiftUI
import UIKit

struct CompressionFailure: Identifiable {
    let id = UUID()
    let filename: String
    let message: String
}

@MainActor
@Observable
final class CompressionController {
    let assets: [PHAsset]
    let sourceAlbum: PHAssetCollection?

    private let service: PhotoEditingService
    private let presetStore: CompressionPresetStore
    private var previewSession: PhotoEditingSession?
    private var previewSource: LoadedPhotoEditSource?

    var selectedPresetID = ResizePreset.original.id
    var quality = 0.8
    var format: PhotoOutputFormat = .preserve
    var includeMetadata = true
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
    private(set) var processedCount = 0
    private(set) var createdAssetIDs: [String] = []
    private(set) var compressedOriginalIDs: [String] = []
    private(set) var deletedOriginalCount = 0
    private(set) var fallbackToJPEGCount = 0
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
        presetStore: CompressionPresetStore
    ) {
        self.assets = assets
        self.sourceAlbum = sourceAlbum
        self.service = service
        self.presetStore = presetStore
    }

    var presets: [ResizePreset] { presetStore.allPresets }

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
            includeMetadata: includeMetadata,
            cropAnchor: assets.count > 1 ? .center : cropAnchor
        )
    }

    /// A finished batch worth no summary: everything saved, nothing to report.
    /// The screen dismisses straight through instead of showing an empty receipt.
    var finishedCleanly: Bool {
        didFinish
            && !wasCancelled
            && failures.isEmpty
            && fallbackToJPEGCount == 0
            && rollbackErrorMessage == nil
            && deleteOriginalsErrorMessage == nil
    }

    var progressFraction: Double {
        guard !assets.isEmpty else { return 0 }
        return Double(processedCount) / Double(assets.count)
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
        guard let first = assets.first else {
            errorMessage = "No photos were selected."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await service.beginSession(for: first)
            previewSession = session
            guard let option = session.preferredSource(for: nil) else {
                throw PhotoEditingError.missingSource
            }
            let source = try await service.loadSource(option, in: session)
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
        if let previewSession {
            service.endSession(previewSession)
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
        failures = []
        rollbackErrorMessage = nil
        deleteOriginalsErrorMessage = nil

        exportTask = Task { [weak self] in
            guard let self else { return }
            for asset in self.assets {
                if Task.isCancelled { break }
                do {
                    let result = try await self.service.compress(
                        asset: asset,
                        options: self.exportOptions,
                        album: self.sourceAlbum,
                        cropAnchor: self.assets.count > 1 ? .center : self.cropAnchor
                    )
                    self.createdAssetIDs.append(result.assetID)
                    self.compressedOriginalIDs.append(asset.localIdentifier)
                    if result.fellBackToJPEG {
                        self.fallbackToJPEGCount += 1
                    }
                } catch {
                    self.failures.append(
                        CompressionFailure(
                            filename: Self.filename(for: asset),
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

    func cancelExport() {
        guard isExporting else { return }
        wasCancelled = true
        exportTask?.cancel()
    }

    func clearError() {
        errorMessage = nil
    }

    private func updatePreviewAndEstimate() async {
        guard let previewSource else { return }
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
            let cgImage = try await service.renderer.previewImage(resized)
            previewImage = UIImage(cgImage: cgImage)
            await updateEstimate()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateEstimate() async {
        guard let previewSession, let previewSource else { return }
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
            try await service.deleteAssets(ids: compressedOriginalIDs)
            deletedOriginalCount = compressedOriginalIDs.count
        } catch {
            deleteOriginalsErrorMessage = error.localizedDescription
        }
    }

    private func removeCreatedAssetsAfterCancellation() async {
        do {
            try await service.deleteCreatedAssets(ids: createdAssetIDs)
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

    private static func filename(for asset: PHAsset) -> String {
        PHAssetResource.assetResources(for: asset).first?.originalFilename
            ?? asset.localIdentifier
    }
}
