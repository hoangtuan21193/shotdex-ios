import Photos
import ShotDexKit
import SwiftUI

/// What the panorama screen was opened with.
struct PanoramaMergePresentation: Identifiable {
    let assets: [PHAsset]

    var id: String { assets.first?.localIdentifier ?? UUID().uuidString }
}

/// Joins a run of overlapping frames into one photo.
///
/// A tier-D tool (DESIGN.md §10.3): Cancel and Save on a top bar, the picture
/// on a black stage, one panel of controls. Not a mode of Combine Photos — the
/// combine modes stack frames that sit on top of each other, and this joins
/// frames that sit beside each other.
struct PanoramaMergeScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let presentation: PanoramaMergePresentation
    var onSaved: ((String) -> Void)?

    @State private var model: PanoramaMergeModel?

    var body: some View {
        GeometryReader { proxy in
            // The same rule as the editor (DESIGN.md §10.3): wide enough, tall
            // enough, and actually landscape. A sidebar is paid for in width,
            // which only a landscape window has spare — and a panorama is the
            // flattest thing this app shows, so height is the thing it cannot
            // give up.
            let wide = EditorLayoutMetrics.usesSidebar(width: proxy.size.width, height: proxy.size.height)
                && proxy.size.width > proxy.size.height

            ZStack {
                EditorTheme.background.ignoresSafeArea()
                if let model {
                    if wide {
                        VStack(spacing: 0) {
                            topBar(model)
                            HStack(spacing: 0) {
                                stage(model)
                                if model.hasPicture {
                                    Divider().overlay(EditorTheme.panelTopHairline)
                                    panelColumn(model, bottomInset: proxy.safeAreaInsets.bottom)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            topBar(model)
                            stage(model)
                            if model.hasPicture {
                                panel(model, bottomInset: proxy.safeAreaInsets.bottom)
                            }
                        }
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .overlay { if let model, model.isSaving { savingOverlay(model) } }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(model?.isSaving == true)
        .task {
            guard model == nil else { return }
            let created = PanoramaMergeModel(
                assets: presentation.assets,
                photoLibrary: photoLibrary,
                stitch: dependencies.panoramaStitchService
            )
            model = created
            await created.load()
        }
        .onChange(of: model?.savedAssetID) {
            guard let identifier = model?.savedAssetID else { return }
            onSaved?(identifier)
            dismiss()
        }
        .alert(
            "Couldn't Save",
            isPresented: Binding(
                get: { model?.errorMessage != nil },
                set: { if !$0 { model?.dismissError() } }
            )
        ) {
            Button("OK") { model?.dismissError() }
        } message: {
            Text(model?.errorMessage ?? "")
        }
    }

    // MARK: Chrome

    private func topBar(_ model: PanoramaMergeModel) -> some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
                .disabled(model.isSaving)
            Spacer()
            Text("Panorama")
                .font(EditorTheme.sidebarTitle)
                .foregroundStyle(.white)
            Spacer()
            Button("Save") { model.save() }
                .fontWeight(.semibold)
                .foregroundStyle(model.canSave ? EditorTheme.accent : EditorTheme.dimText)
                .disabled(!model.canSave)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: AppTheme.Size.minTouch + AppTheme.Spacing.md)
    }

    private func stage(_ model: PanoramaMergeModel) -> some View {
        ZStack {
            Color.black
            if let preview = model.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Panorama preview")
            }
            switch model.state {
            case .loading(let done, let total):
                working("Loading \(done + 1) of \(total)…")
            case .stitching(let message):
                working(message)
            case .noOverlap:
                message(
                    "These photos don't overlap",
                    detail: "Frames need to overlap by about a third for ShotDex to join them."
                )
            case .unavailable(let count):
                message(
                    "^[\(count) photo](inflect: true) couldn't be downloaded",
                    detail: "They're stored in iCloud. Check your connection and try again."
                )
            case .failed(let text):
                message("Couldn't build the panorama", detail: text)
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { refiningBadge(model) }
        .overlay(alignment: .bottom) { notPlaced(model) }
    }

    @ViewBuilder
    private func refiningBadge(_ model: PanoramaMergeModel) -> some View {
        if model.isRefining, model.preview != nil {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .padding(AppTheme.Spacing.sm)
                .background(.ultraThinMaterial, in: Circle())
                .padding(AppTheme.Spacing.md)
                .accessibilityLabel("Sharpening the preview")
        }
    }

    /// Frames that could not be joined. Named, never dropped in silence
    /// (FS-14.01 §2).
    @ViewBuilder
    private func notPlaced(_ model: PanoramaMergeModel) -> some View {
        if !model.unplaced.isEmpty {
            Label(
                "^[\(model.unplaced.count) photo](inflect: true) not placed",
                systemImage: "exclamationmark.triangle"
            )
            .font(EditorTheme.maskSubtitle)
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }

    private func working(_ text: String) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ProgressView().tint(.white)
            Text(text)
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "pano")
                .font(.system(size: 32))
                .foregroundStyle(EditorTheme.dimText)
            Text(title)
                .font(EditorTheme.sidebarTitle)
                .foregroundStyle(.white)
            Text(detail)
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.xl)
    }

    // MARK: Panel

    /// `bottomInset` is the home-indicator strip. The panel's background runs
    /// under it, which is right — a slab that stops short leaves a black band —
    /// but the last control must not, or the Size slider ends up under the
    /// indicator where a drag is the system's gesture and not ours.
    private func panel(_ model: PanoramaMergeModel, bottomInset: CGFloat) -> some View {
        PanoramaMergePanel(model: model)
            .padding(AppTheme.Spacing.lg)
            .padding(.bottom, bottomInset)
            .background(EditorTheme.panelSolid)
            .overlay(alignment: .top) {
                Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 1)
            }
    }

    private func panelColumn(_ model: PanoramaMergeModel, bottomInset: CGFloat) -> some View {
        ScrollView {
            PanoramaMergePanel(model: model)
                .padding(AppTheme.Spacing.lg)
                .padding(.bottom, bottomInset)
        }
        .frame(width: EditorLayoutMetrics.sidebarDefaultWidth)
        .background(EditorTheme.panelSolid)
    }

    // MARK: Saving

    /// A full-screen lock while the picture is written (DESIGN.md §10.3): this
    /// can run for a minute on a big panorama, and everything on the screen
    /// behind it would change what is being written.
    private func savingOverlay(_ model: PanoramaMergeModel) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            VStack(spacing: AppTheme.Spacing.md) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Saving Panorama")
                    .font(EditorTheme.sidebarTitle)
                    .foregroundStyle(.white)
                ProgressView(value: model.saveProgress ?? 0)
                    .tint(EditorTheme.accent)
                Text("\(Int((model.saveProgress ?? 0) * 100))%")
                    .font(EditorTheme.rowLabel.monospacedDigit())
                    .foregroundStyle(EditorTheme.secondaryText)
                Button("Cancel", role: .destructive) { model.cancelSave() }
                    .padding(.top, AppTheme.Spacing.sm)
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: 300)
            .background(EditorTheme.panelSolid, in: RoundedRectangle.app(AppTheme.Radius.lg))
            .overlay {
                RoundedRectangle.app(AppTheme.Radius.lg).stroke(EditorTheme.hairline, lineWidth: 1)
            }
        }
    }
}

extension View {
    func panoramaMergeCover(
        _ presentation: Binding<PanoramaMergePresentation?>,
        onDismiss: @escaping () -> Void,
        onSaved: @escaping (String) -> Void
    ) -> some View {
        fullScreenCover(item: presentation, onDismiss: onDismiss) { presentation in
            PanoramaMergeScreen(presentation: presentation, onSaved: onSaved)
        }
    }
}
