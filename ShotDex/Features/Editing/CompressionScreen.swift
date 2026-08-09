import Photos
import SwiftUI

/// Immutable payload for presenting compression. Keeping the assets inside the
/// item passed to `fullScreenCover(item:)` prevents SwiftUI from opening the
/// cover with an older, empty asset-array snapshot.
struct CompressionPresentation: Identifiable {
    let id = UUID()
    let assets: [PHAsset]
    let sourceAlbum: PHAssetCollection?
}

/// Compress / resize — a tier-D tool (DESIGN.md §2): dark stage, editor slider,
/// drawn controls. It shares the editor's palette and the `EditorValueSlider` so
/// it reads as the same surface as the Photo Editor rather than a system form.
struct CompressionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.appAccent) private var accent

    let assets: [PHAsset]
    let sourceAlbum: PHAssetCollection?

    @State private var controller: CompressionController?
    @State private var isCancelConfirmationPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                EditorTheme.background.ignoresSafeArea()
                Group {
                    if let controller {
                        content(controller)
                    } else {
                        ProgressView("Preparing original…")
                            .tint(.white)
                            .foregroundStyle(.white)
                    }
                }
            }
            .navigationTitle(assets.count == 1 ? "Compress Photo" : "Compress \(assets.count) Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if controller?.isExporting == true {
                            isCancelConfirmationPresented = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .toolbarBackground(EditorTheme.panelSolid, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            guard controller == nil else { return }
            let newController = CompressionController(
                assets: assets,
                sourceAlbum: sourceAlbum,
                service: dependencies.photoEditing,
                presetStore: dependencies.compressionPresets
            )
            controller = newController
            await newController.load()
        }
        .onDisappear { controller?.close() }
        .interactiveDismissDisabled(controller?.isExporting == true)
        .confirmationDialog(
            "Cancel this export?",
            isPresented: $isCancelConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Cancel Export and Remove Copies", role: .destructive) {
                controller?.cancelExport()
            }
            Button("Continue Export", role: .cancel) {}
        } message: {
            Text("ShotDex will ask Photos to remove every copy already exported.")
        }
        .alert(
            "Compression Error",
            isPresented: Binding(
                get: { controller?.errorMessage != nil },
                set: { if !$0 { controller?.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller?.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(_ controller: CompressionController) -> some View {
        if controller.didFinish {
            CompressionSummary(controller: controller) {
                dismiss()
            }
        } else {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    CompressionPreview(controller: controller)
                        .frame(height: assets.count == 1 ? 320 : 250)

                    presetSection(controller)
                    qualitySection(controller)
                    formatSection(controller)
                    metadataSection(controller)

                    if assets.count > 1 {
                        Label(
                            "Bulk Fill presets use a centered crop for every photo.",
                            systemImage: "crop"
                        )
                        .font(.footnote)
                        .foregroundStyle(EditorTheme.dimText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    exportButton(controller)
                }
                .padding(AppTheme.Spacing.lg)
            }
            .safeAreaInset(edge: .bottom) {
                if controller.isExporting {
                    exportProgress(controller)
                }
            }
        }
    }

    private func exportButton(_ controller: CompressionController) -> some View {
        let isDisabled = controller.isLoading || controller.isExporting
        return Button {
            controller.startExport()
        } label: {
            Label(
                assets.count == 1 ? "Save to Photos" : "Compress \(assets.count) Photos",
                systemImage: "arrow.down.circle.fill"
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isDisabled ? EditorTheme.dimText : .white)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Size.primaryActionHeight)
            .background(
                isDisabled ? EditorTheme.control : accent,
                in: RoundedRectangle.app(AppTheme.Radius.md)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func presetSection(_ controller: CompressionController) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            CompressionGroupLabel(text: "Size")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(controller.presets) { preset in
                        Button {
                            controller.choosePreset(preset.id)
                        } label: {
                            VStack(spacing: AppTheme.Spacing.xs) {
                                Text(preset.name)
                                    .font(.subheadline.weight(.medium))
                                Text(presetDetail(preset))
                                    .font(.caption2)
                                    .foregroundStyle(EditorTheme.secondaryText)
                            }
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(
                            CompressionChoiceStyle(
                                selected: controller.selectedPresetID == preset.id,
                                accent: accent
                            )
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func qualitySection(_ controller: CompressionController) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            EditorValueSlider(
                label: "Quality",
                value: controller.quality,
                range: 0.1...1,
                valueText: "\(Int((controller.quality * 100).rounded()))%",
                accessibilityName: "Quality",
                onBeginDrag: {},
                onDrag: {
                    controller.quality = $0
                    controller.scheduleEstimate()
                },
                onEndDrag: { _, _, _ in controller.scheduleEstimate() },
                onReset: {
                    controller.quality = 0.8
                    controller.scheduleEstimate()
                }
            )
            HStack(spacing: AppTheme.Spacing.sm) {
                if controller.isEstimating {
                    ProgressView().controlSize(.small)
                    Text("Estimating size…")
                        .font(.caption)
                        .foregroundStyle(EditorTheme.secondaryText)
                } else if let text = controller.estimatedSizeText {
                    Text("~\(text)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(EditorTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            Text("The size is a fast estimate and may change slightly when the full-resolution file is encoded.")
                .font(.caption)
                .foregroundStyle(EditorTheme.dimText)
        }
    }

    private func formatSection(_ controller: CompressionController) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            CompressionGroupLabel(text: "Format")
            Picker(
                "Format",
                selection: Binding(
                    get: { controller.format },
                    set: {
                        controller.format = $0
                        controller.schedulePreviewUpdate()
                    }
                )
            ) {
                if !controller.sourceIsRAW {
                    Text("Same as Original").tag(PhotoOutputFormat.preserve)
                }
                Text("JPEG").tag(PhotoOutputFormat.jpeg)
                Text("HEIC").tag(PhotoOutputFormat.heic)
            }
            .pickerStyle(.segmented)
            if controller.willFallbackToJPEG {
                Label(
                    "HEIC encoding isn't available on this device. ShotDex will save JPEG instead.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
    }

    private func metadataSection(_ controller: CompressionController) -> some View {
        Toggle(
            isOn: Binding(
                get: { controller.includeMetadata },
                set: {
                    controller.includeMetadata = $0
                    controller.scheduleEstimate()
                }
            )
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Include Metadata")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Camera EXIF, date, location and orientation")
                    .font(.caption)
                    .foregroundStyle(EditorTheme.secondaryText)
            }
        }
        .tint(accent)
    }

    private func exportProgress(_ controller: CompressionController) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ProgressView(value: controller.progressFraction)
                .tint(accent)
            HStack {
                Text(
                    "Processing \(min(controller.processedCount + 1, assets.count)) of \(assets.count)"
                )
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(EditorTheme.secondaryText)
                Spacer()
                Button("Cancel", role: .destructive) {
                    isCancelConfirmationPresented = true
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EditorTheme.panelTopHairline)
                .frame(height: 1)
        }
    }

    private func presetDetail(_ preset: ResizePreset) -> String {
        switch preset.kind {
        case .original:
            "Full size"
        case .longEdge:
            "Long edge \(preset.longEdge ?? 0)"
        case .exact:
            "\(preset.width ?? 0)×\(preset.height ?? 0) · \(preset.cropMode.displayName)"
        }
    }
}

/// The uppercase tier-D group heading (DESIGN.md §7.2) used above each control.
private struct CompressionGroupLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(EditorTheme.groupLabel)
            .tracking(0.6)
            .foregroundStyle(EditorTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompressionPreview: View {
    @Bindable var controller: CompressionController
    @State private var dragStartAnchor: NormalizedPoint?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle.app(AppTheme.Radius.lg)
                    .fill(EditorTheme.panel)
                if let image = controller.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(AppTheme.Spacing.sm)
                } else {
                    ProgressView().tint(.white)
                }

                if canRepositionCrop {
                    VStack {
                        Spacer()
                        EditorPillLabel(text: "Drag to reposition crop", systemImage: "hand.draw")
                            .padding(AppTheme.Spacing.md)
                    }
                }
            }
            .clipShape(RoundedRectangle.app(AppTheme.Radius.lg))
            .contentShape(RoundedRectangle.app(AppTheme.Radius.lg))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard canRepositionCrop else { return }
                        if dragStartAnchor == nil {
                            dragStartAnchor = controller.cropAnchor
                        }
                        let start = dragStartAnchor ?? .center
                        controller.cropAnchor = NormalizedPoint(
                            x: min(1, max(0, start.x - value.translation.width / proxy.size.width)),
                            y: min(1, max(0, start.y - value.translation.height / proxy.size.height))
                        )
                    }
                    .onEnded { _ in
                        guard canRepositionCrop else { return }
                        dragStartAnchor = nil
                        controller.schedulePreviewUpdate()
                    }
            )
        }
    }

    private var canRepositionCrop: Bool {
        controller.assets.count == 1
            && controller.selectedPreset.kind == .exact
            && controller.selectedPreset.cropMode == .fill
    }
}

private struct CompressionSummary: View {
    @Bindable var controller: CompressionController
    let done: () -> Void

    var body: some View {
        List {
            Section {
                if controller.wasCancelled {
                    Label("Export cancelled", systemImage: "xmark.circle")
                } else {
                    Label(
                        "\(controller.createdAssetIDs.count) saved to Photos",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
                if !controller.failures.isEmpty {
                    Label(
                        "\(controller.failures.count) failed",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
                if controller.fallbackToJPEGCount > 0 {
                    Label(
                        "\(controller.fallbackToJPEGCount) saved as JPEG because HEIC wasn't supported",
                        systemImage: "info.circle"
                    )
                }
                if controller.rollbackErrorMessage != nil {
                    Label(
                        "Some exported copies may remain in Photos",
                        systemImage: "exclamationmark.octagon.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            if let rollbackErrorMessage = controller.rollbackErrorMessage {
                Section("Cancellation Cleanup") {
                    Text(rollbackErrorMessage)
                        .foregroundStyle(.secondary)
                }
            }

            if !controller.failures.isEmpty {
                Section("Failures") {
                    ForEach(controller.failures) { failure in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(failure.filename)
                            Text(failure.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Done", action: done)
                    .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(EditorTheme.background)
    }
}

private struct CompressionChoiceStyle: ButtonStyle {
    let selected: Bool
    /// Passed in rather than read from the environment: `makeBody` is not a view
    /// body, so `@Environment` in a `ButtonStyle` never resolves.
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : EditorTheme.secondaryText)
            .background(
                selected
                    ? accent.opacity(configuration.isPressed ? 0.75 : 1)
                    : EditorTheme.control,
                in: RoundedRectangle.app(AppTheme.Radius.md)
            )
            .overlay {
                RoundedRectangle.app(AppTheme.Radius.md)
                    .stroke(
                        selected ? accent : EditorTheme.hairline,
                        lineWidth: 1
                    )
            }
    }
}
