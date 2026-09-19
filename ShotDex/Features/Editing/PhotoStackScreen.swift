import Photos
import ShotDexKit
import SwiftUI

/// What a combine was opened with.
struct PhotoStackPresentation: Identifiable {
    let assets: [PHAsset]

    var id: String { assets.first?.localIdentifier ?? UUID().uuidString }
}

/// Combines a run of frames into one photo: multiple exposure and focus
/// stacking.
///
/// A tier-D tool (DESIGN.md §10.3): Cancel and Save on a top bar, the preview
/// on a black stage, one panel of controls at the bottom. It is not part of the
/// editor — the editor works on one photo through a recipe, and this makes a
/// new photo out of several — so it saves a new asset and gets out of the way.
struct PhotoStackScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    let presentation: PhotoStackPresentation

    @State private var mode: PhotoStackMode = .average
    @State private var preview: UIImage?
    @State private var isWorking = false
    @State private var statusText: String?
    @State private var errorMessage: String?
    @State private var savedAssetID: String?
    /// Source frames at preview resolution, loaded once and reused for every
    /// mode change — reloading eight originals per picker tap is the difference
    /// between instant and unusable.
    @State private var previewFrames: [CIImage] = []
    @State private var renderTask: Task<Void, Never>?

    private let renderer = PhotoStackRenderer()

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                stage
                panel
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadFrames() }
        .onDisappear { renderTask?.cancel() }
        .alert(
            "Couldn't Combine",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
            Spacer()
            Text("Combine \(presentation.assets.count) Photos")
                .font(EditorTheme.sidebarTitle)
                .foregroundStyle(.white)
            Spacer()
            Button("Save") { save() }
                .fontWeight(.semibold)
                .foregroundStyle(preview == nil || isWorking ? EditorTheme.dimText : EditorTheme.accent)
                .disabled(preview == nil || isWorking)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: AppTheme.Size.minTouch + AppTheme.Spacing.md)
    }

    private var stage: some View {
        ZStack {
            Color.black
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
            }
            if isWorking {
                VStack(spacing: AppTheme.Spacing.md) {
                    ProgressView().tint(.white)
                    if let statusText {
                        Text(statusText)
                            .font(EditorTheme.rowLabel)
                            .foregroundStyle(EditorTheme.secondaryText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Picker("Mode", selection: $mode) {
                ForEach(PhotoStackMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in renderPreview() }

            Text(mode.explanation)
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if mode.needsAlignment {
                Label(
                    "Frames are lined up before stacking, so a handheld sequence still works — a tripod still works better.",
                    systemImage: "info.circle"
                )
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.dimText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1)
        }
    }

    // MARK: Work

    /// Loads every frame once at preview resolution. Full resolution is left
    /// until Save: a thirty-frame macro stack at 48 megapixels is gigabytes, and
    /// nobody needs that to choose between Average and Lighten.
    private func loadFrames() async {
        isWorking = true
        statusText = "Loading \(presentation.assets.count) photos…"
        defer { isWorking = false }

        var frames: [CIImage] = []
        for asset in presentation.assets {
            guard let image = await Self.previewImage(
                for: asset,
                photoLibrary: dependencies.photoLibrary
            ), let ciImage = CIImage(image: image) else { continue }
            frames.append(ciImage)
        }
        previewFrames = frames
        guard frames.count >= 2 else {
            errorMessage = PhotoStackError.needsTwoImages.localizedDescription
            return
        }
        await render()
    }

    private func renderPreview() {
        renderTask?.cancel()
        renderTask = Task { await render() }
    }

    private func render() async {
        guard previewFrames.count >= 2 else { return }
        isWorking = true
        statusText = mode.needsAlignment ? "Lining frames up…" : "Combining…"
        defer { isWorking = false }
        do {
            let combined = try await renderer.combine(images: previewFrames, mode: mode)
            let cgImage = try await renderer.render(combined)
            guard !Task.isCancelled else { return }
            preview = UIImage(cgImage: cgImage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-runs the combine at full resolution and writes a new asset. The
    /// preview is not saved: it is a 1600pt proxy, and a photographer stacking
    /// macro frames wants every pixel they shot.
    private func save() {
        renderTask?.cancel()
        renderTask = Task {
            isWorking = true
            statusText = "Loading full-resolution frames…"
            defer { isWorking = false }
            do {
                var frames: [CIImage] = []
                for (index, asset) in presentation.assets.enumerated() {
                    statusText = "Loading \(index + 1) of \(presentation.assets.count)…"
                    guard let data = await Self.originalData(for: asset),
                          let image = CIImage(data: data)
                    else { continue }
                    frames.append(image)
                }
                guard frames.count >= 2 else { throw PhotoStackError.needsTwoImages }

                statusText = mode.needsAlignment ? "Lining frames up…" : "Combining…"
                let combined = try await renderer.combine(images: frames, mode: mode)
                let cgImage = try await renderer.render(combined)

                statusText = "Saving…"
                guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.98) else {
                    throw PhotoStackError.renderFailed
                }
                let name = "ShotDex-\(mode.rawValue)-\(Int(Date().timeIntervalSince1970)).jpg"
                savedAssetID = try await dependencies.photoLibrary.saveImage(data, filename: name)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension PhotoStackScreen {
    /// One frame at proxy resolution, through the viewer's own request path so
    /// an iCloud-only original is fetched rather than skipped.
    static func previewImage(
        for asset: PHAsset,
        photoLibrary: PhotoLibraryService
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestDetailImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                allowNetwork: true,
                progress: { _ in }
            ) { image, isDegraded in
                // The request calls back more than once as better data lands;
                // take the first final one and ignore the rest.
                guard !isDegraded, !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }

    /// The original file's bytes, for the full-resolution pass at save time.
    static func originalData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

extension View {
    func photoStackCover(
        _ presentation: Binding<PhotoStackPresentation?>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        fullScreenCover(item: presentation, onDismiss: onDismiss) { presentation in
            PhotoStackScreen(presentation: presentation)
        }
    }
}
