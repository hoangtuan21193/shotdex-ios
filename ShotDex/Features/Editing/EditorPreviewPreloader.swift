import Photos
import ShotDexKit
import UIKit

/// Draws every photo of a multi-photo run into the run's `EditorPreviewCache`
/// in the background, so the filmstrip shows each one at full quality the
/// moment it is tapped (FS-03.09b §2).
///
/// One photo at a time, outward from the one on screen, and only while the
/// editor itself is idle: the renderer is one actor shared with the canvas,
/// and a preload render queued in front of a slider's frame is a frame the
/// user waits for. The two photos either side keep their sessions in the
/// service's small recent cache — they are the likeliest next tap — and
/// every other session is ended as soon as its previews are drawn, because a
/// session holds a full copy of the original.
@MainActor
final class EditorPreviewPreloader {
    private let service: PhotoEditingService
    private let cache: EditorPreviewCache
    private var task: Task<Void, Never>?

    init(service: PhotoEditingService, cache: EditorPreviewCache) {
        self.service = service
        self.cache = cache
    }

    /// The canvas moved, or a sync changed what other photos will open with.
    /// A walk already running is not interrupted — the photo it is drawing
    /// has already paid for its session and its source copy, and dropping it
    /// on every filmstrip tap meant a quick walk through the strip never
    /// finished any photo at all. It picks its next photo around the new
    /// position instead; a walk that had run out of work starts again.
    func follow(session: EditorSession, isEditorBusy: @escaping @MainActor () -> Bool) {
        self.session = session
        self.isEditorBusy = isEditorBusy
        guard task == nil else { return }
        task = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled, let self, let next = self.nextPhoto() {
                let stored = await self.preload(
                    next.asset,
                    draft: next.draft,
                    isNeighbour: next.isNeighbour,
                    isEditorBusy: { [weak self] in self?.isEditorBusy() ?? true }
                )
                if !stored, !Task.isCancelled { self.failures.insert(next.key) }
            }
            // A cancelled walk has already been replaced, or the run closed.
            if !Task.isCancelled { self?.task = nil }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        session = nil
    }

    private weak var session: EditorSession?
    private var isEditorBusy: @MainActor () -> Bool = { true }
    /// Photos that could not be drawn (no source, iCloud unreachable), by id
    /// and draft, so the walk does not spin on them. A new draft is a new
    /// attempt; the editor opening the photo itself is the retry.
    private var failures: Set<String> = []

    /// The nearest photo to the canvas that still has work, in
    /// `EditorPreloadOrder`. Asked afresh before each photo, so a switch or a
    /// sync is followed without restarting anything.
    private func nextPhoto() -> (asset: PHAsset, draft: PhotoEditRecipe?, isNeighbour: Bool, key: String)? {
        guard let session else { return nil }
        let current = session.index
        for index in EditorPreloadOrder.indices(count: session.assets.count, around: current) where index != current {
            let asset = session.assets[index]
            guard asset.mediaType == .image else { continue }
            let draft = session.draft(for: asset)
            let key = "\(asset.localIdentifier)|\(draft.map(EditorPreviewFingerprint.of) ?? "saved")"
            guard !failures.contains(key), cache.needsPreload(
                assetID: asset.localIdentifier,
                stamp: EditorPreviewCache.stamp(of: asset),
                draft: draft
            ) else { continue }
            return (asset, draft, abs(index - current) <= 1, key)
        }
        return nil
    }

    private func preload(
        _ asset: PHAsset,
        draft: PhotoEditRecipe?,
        isNeighbour: Bool,
        isEditorBusy: @MainActor () -> Bool
    ) async -> Bool {
        guard await Self.waitUntilIdle(isEditorBusy) else { return false }
        let session: PhotoEditingSession
        do {
            session = try await service.preloadSession(for: asset, keeps: isNeighbour)
        } catch {
            return false
        }
        // A no-op for a session the recent cache kept.
        defer { service.endSession(session) }
        guard let option = session.preferredSource(for: session.recalledRecipe),
              await Self.waitUntilIdle(isEditorBusy),
              let loaded = try? await service.loadSource(option, in: session)
        else { return false }

        // The same starting point `PhotoEditorController.load` builds, so the
        // fingerprints the two write and read agree.
        var identity = PhotoEditRecipe.identity
        identity.source = option.source
        identity.sourceFilename = option.filename
        var baseline = session.recalledRecipe ?? .identity
        baseline.source = option.source
        baseline.sourceFilename = option.filename
        let recipe = draft ?? baseline
        let id = asset.localIdentifier
        let stamp = EditorPreviewCache.stamp(of: asset)
        let renderer = service.renderer
        let edge = PhotoEditorController.settleEdge

        var original: UIImage?
        if !cache.hasOriginal(assetID: id, stamp: stamp, optionID: option.id) {
            guard await Self.waitUntilIdle(isEditorBusy),
                  let cgImage = try? await renderer.renderPreview(
                      source: loaded.info,
                      recipe: identity,
                      maximumDimension: edge
                  )
            else { return false }
            original = UIImage(cgImage: cgImage)
        }

        // What the editor's `renderReady` would draw: a RAW's lens source is
        // part of the picture before the first edit writes it.
        var renderRecipe = recipe
        if loaded.info.isRAW, renderRecipe.lensProfile == nil {
            renderRecipe.lensProfile = await PhotoEditorController.resolveLens(for: loaded.info).sessionChoice
        }
        var edited: (image: UIImage, recipe: PhotoEditRecipe)?
        var skipped: PhotoEditRecipe?
        // Text layers expand `{camera}` tokens and Upright solves on the
        // editor's own preview — both live in the controller. The first visit
        // draws those; the cache keeps the result.
        if renderRecipe.overlays.contains(where: { $0.kind == .text }) || renderRecipe.upright.needsSolving {
            skipped = recipe
        } else if renderRecipe == identity, let original {
            edited = (original, recipe)
        } else if await Self.waitUntilIdle(isEditorBusy),
                  let preview = try? await renderer.renderPreviewImages(
                      source: loaded.info,
                      recipe: renderRecipe,
                      maximumDimension: edge
                  ) {
            edited = (UIImage(cgImage: preview.displayImage), recipe)
        } else {
            skipped = recipe
        }
        guard !Task.isCancelled else { return false }
        return await cache.store(
            assetID: id,
            stamp: stamp,
            baseline: baseline,
            edited: edited,
            original: original.map { ($0, option.id) },
            skipped: skipped,
            keepsInMemory: isNeighbour
        )
    }

    /// Waits for the editor to be idle twice in a row — a slider drag
    /// renders in bursts, and one idle sample between two frames is not a
    /// pause. False when the walk was cancelled meanwhile.
    private static func waitUntilIdle(_ isEditorBusy: @MainActor () -> Bool) async -> Bool {
        var idleSamples = 0
        while idleSamples < 2 {
            guard !Task.isCancelled else { return false }
            idleSamples = isEditorBusy() ? 0 : idleSamples + 1
            if idleSamples < 2 {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        return !Task.isCancelled
    }
}
