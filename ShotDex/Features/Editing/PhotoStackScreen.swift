import Photos
import ShotDexKit
import SwiftUI

/// What a combine was opened with.
struct PhotoStackPresentation: Identifiable {
    let assets: [PHAsset]
    /// The Combine Photos row that opened it — decides the title, the modes on
    /// offer and the one it starts on.
    let purpose: CombinePurpose

    var id: String { assets.first?.localIdentifier ?? UUID().uuidString }
}

/// Combines a run of frames into one photo: Focus Stack, or Stack Exposures
/// with its Average · Lighten · Darken picker (FS-01.09).
///
/// A tier-D tool (DESIGN.md §10.3): Cancel and Save on a top bar, the preview
/// on a black stage, one panel of controls at the bottom. It is not part of the
/// editor — the editor works on one photo through a recipe, and this makes a
/// new photo out of several — so it saves a new asset and gets out of the way.
/// The work lives in `PhotoStackModel`; this view only draws it.
struct PhotoStackScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    let presentation: PhotoStackPresentation

    @State private var model: PhotoStackModel?

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let model {
                content(model)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            let model = PhotoStackModel(
                purpose: presentation.purpose,
                assets: presentation.assets,
                photoLibrary: dependencies.photoLibrary,
                indexPipeline: dependencies.indexPipeline
            )
            self.model = model
            await model.loadFrames()
        }
        .onDisappear { model?.cancel() }
    }

    @ViewBuilder
    private func content(_ model: PhotoStackModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            topBar(model)
            stage(model)
            panel(model)
        }
        .onChange(of: model.savedAssetID) { _, id in
            if id != nil { dismiss() }
        }
        .alert(
            model.failure?.title ?? "",
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
        ) {
            Button("OK") { model.failure = nil }
        } message: {
            Text(model.failure?.message ?? "")
        }
    }

    // MARK: Chrome

    private func topBar(_ model: PhotoStackModel) -> some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
            Spacer()
            Text(presentation.purpose.title)
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

    private func stage(_ model: PhotoStackModel) -> some View {
        ZStack {
            Color.black
            if let preview = model.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
            }
            if model.isWorking {
                VStack(spacing: AppTheme.Spacing.md) {
                    ProgressView().tint(.white)
                    if let statusText = model.statusText {
                        Text(statusText)
                            .font(EditorTheme.rowLabel)
                            .foregroundStyle(EditorTheme.secondaryText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func panel(_ model: PhotoStackModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Only Stack Exposures has a choice to make; Focus Stack is one job.
            if presentation.purpose.showsModePicker {
                Picker("Mode", selection: $model.mode) {
                    ForEach(presentation.purpose.stackModes) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(model.mode.purposeDescription)
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if model.mode.needsAlignment {
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
