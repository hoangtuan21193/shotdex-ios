import Photos
import SwiftUI

/// Immutable payload for presenting the collage editor. Assets live inside the
/// item (see `CompressionPresentation`) so the cover never opens against an
/// older, empty snapshot.
struct CollagePresentation: Identifiable {
    let id = UUID()
    /// Images only, pick order, 2–9 of them.
    let assets: [PHAsset]
}

/// Full-screen collage editor, on the photo editor's chrome contract: black
/// OLED stage, fixed-height opaque bottom panel, one accent. The screen is a
/// thin shell — geometry and state live in `CollageEditorModel`, panel content
/// in `CollagePanelViews`, and every sheet is declared here.
struct CollageScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    let assets: [PHAsset]

    @State private var model: CollageEditorModel?
    @State private var isDiscardConfirmationPresented = false
    @State private var replacingCellIndex: Int?
    @State private var editingOverlay: PhotoOverlay?
    @State private var isAddingText = false
    @State private var isFontPickerPresented = false

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let model {
                editor(model)
            } else {
                ProgressView()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard model == nil else { return }
            let newModel = CollageEditorModel(
                assets: assets,
                photoLibrary: dependencies.photoLibrary,
                indexPipeline: dependencies.indexPipeline,
                overlayFontRecents: dependencies.overlayFontRecents
            )
            model = newModel
            newModel.loadPreviews()
        }
        .interactiveDismissDisabled(model?.hasEdits == true || model?.isExporting == true)
        .onChange(of: model?.didSave) { _, didSave in
            if didSave == true { dismiss() }
        }
        .confirmationDialog(
            "Discard this collage?",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .alert(
            "Collage Error",
            isPresented: Binding(
                get: { model?.errorMessage != nil },
                set: { if !$0 { model?.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model?.errorMessage ?? "")
        }
        .sheet(item: replaceSheetBinding) { target in
            if let model {
                CollageReplaceSheet(
                    assets: model.assets,
                    photoLibrary: dependencies.photoLibrary
                ) { assetID in
                    model.replaceCell(target.index, with: assetID)
                }
                .presentationDetents([.height(220)])
            }
        }
        .sheet(isPresented: $isFontPickerPresented) {
            if let model {
                EditorFontPickerSheet(
                    recents: dependencies.overlayFontRecents.recents,
                    current: model.lastFont
                ) { choice in
                    model.rememberFont(choice)
                    model.updateSelectedOverlay { overlay in
                        overlay.fontPostScriptName = choice.postScriptName
                        overlay.fontFamilyName = choice.familyName
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isAddingText) {
            EditorInlineTextEditor(
                initialText: "",
                tokens: .empty,
                alignment: .center,
                onCommit: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { model?.addTextOverlay(trimmed) }
                    isAddingText = false
                },
                onCancel: { isAddingText = false }
            )
        }
        .fullScreenCover(item: $editingOverlay) { overlay in
            EditorInlineTextEditor(
                initialText: overlay.text,
                tokens: .empty,
                alignment: overlay.alignment,
                onCommit: { text in
                    model?.updateSelectedOverlay { $0.text = text }
                    editingOverlay = nil
                },
                onCancel: { editingOverlay = nil }
            )
        }
    }

    // MARK: - Layout

    private func editor(_ model: CollageEditorModel) -> some View {
        VStack(spacing: 0) {
            topBar(model)
            CollageCanvasView(
                model: model,
                onReplaceRequest: { index in replacingCellIndex = index },
                onEditText: { overlay in
                    model.selectedOverlayID = overlay.id
                    editingOverlay = overlay
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            panel(model)
        }
    }

    private func topBar(_ model: CollageEditorModel) -> some View {
        HStack {
            Button("Cancel") {
                if model.hasEdits {
                    isDiscardConfirmationPresented = true
                } else {
                    dismiss()
                }
            }
            .foregroundStyle(EditorTheme.secondaryText)

            Spacer()

            Text("Collage")
                .font(EditorTheme.maskTitle)
                .foregroundStyle(.white)

            Spacer()

            Button {
                Task { await model.export() }
            } label: {
                if model.isExporting {
                    ProgressView()
                        .tint(EditorTheme.accent)
                } else {
                    Text("Save")
                        .fontWeight(.semibold)
                        .foregroundStyle(EditorTheme.accent)
                }
            }
            .disabled(model.isExporting || model.template == nil)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func panel(_ model: CollageEditorModel) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(EditorTheme.panelTopHairline)
                .frame(height: 1)
            panelContent(model)
                .frame(maxHeight: .infinity)
            groupNav(model)
        }
        .frame(height: EditorLayoutMetrics.editorPanelFixedHeight)
        .background(EditorTheme.panelSolid)
    }

    @ViewBuilder
    private func panelContent(_ model: CollageEditorModel) -> some View {
        switch model.panelGroup {
        case .layout:
            CollageLayoutPanel(model: model)
        case .style:
            CollageStylePanel(model: model)
        case .text:
            CollageTextPanel(
                model: model,
                onAddText: { isAddingText = true },
                onEditText: { overlay in
                    model.selectedOverlayID = overlay.id
                    editingOverlay = overlay
                },
                onPickFont: { isFontPickerPresented = true }
            )
        }
    }

    private func groupNav(_ model: CollageEditorModel) -> some View {
        HStack {
            ForEach(CollageEditorModel.PanelGroup.allCases) { group in
                Button {
                    withAnimation(EditorTheme.animation) { model.panelGroup = group }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: group.systemImage)
                            .font(.system(size: 16, weight: .medium))
                        Text(group.title)
                            .font(EditorTheme.tabLabel)
                    }
                    .foregroundStyle(
                        model.panelGroup == group ? EditorTheme.accent : EditorTheme.dimText
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: EditorLayoutMetrics.editorGroupNavHeight)
        .padding(.bottom, 4)
    }

    // MARK: - Replace sheet plumbing

    private struct ReplaceTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private var replaceSheetBinding: Binding<ReplaceTarget?> {
        Binding(
            get: { replacingCellIndex.map(ReplaceTarget.init(index:)) },
            set: { replacingCellIndex = $0?.index }
        )
    }
}

/// Thumbnails of the already-selected set; tapping one swaps it into the
/// long-pressed cell. Duplicates are allowed on purpose — repeating a photo
/// is a legitimate layout choice.
private struct CollageReplaceSheet: View {
    let assets: [PHAsset]
    let photoLibrary: PhotoLibraryService
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replace With")
                .font(EditorTheme.panelTitle)
                .foregroundStyle(.white)
                .padding(.top, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        CollageReplaceThumbnail(asset: asset, photoLibrary: photoLibrary)
                            .onTapGesture {
                                onPick(asset.localIdentifier)
                                dismiss()
                            }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorTheme.panelSolid)
        .preferredColorScheme(.dark)
    }
}

private struct CollageReplaceThumbnail: View {
    let asset: PHAsset
    let photoLibrary: PhotoLibraryService

    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            .fill(EditorTheme.control)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            .onAppear {
                _ = photoLibrary.requestThumbnail(
                    for: asset,
                    targetSize: CGSize(width: 200, height: 200),
                    allowNetwork: false
                ) { result in
                    if let result { image = result }
                }
            }
    }
}
