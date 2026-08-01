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
            Group {
                if let controller {
                    content(controller)
                } else {
                    ProgressView("Preparing original…")
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
        }
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
                VStack(spacing: 18) {
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
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        controller.startExport()
                    } label: {
                        Label(
                            assets.count == 1 ? "Save to Photos" : "Compress \(assets.count) Photos",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isLoading || controller.isExporting)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                if controller.isExporting {
                    exportProgress(controller)
                }
            }
        }
    }

    private func presetSection(_ controller: CompressionController) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Size")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(controller.presets) { preset in
                        Button {
                            controller.choosePreset(preset.id)
                        } label: {
                            VStack(spacing: 3) {
                                Text(preset.name)
                                    .font(.subheadline.weight(.medium))
                                Text(presetDetail(preset))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Quality")
                    .font(.headline)
                Spacer()
                Text("\(Int((controller.quality * 100).rounded()))%")
                    .monospacedDigit()
                if controller.isEstimating {
                    ProgressView().controlSize(.small)
                } else if let text = controller.estimatedSizeText {
                    Text("· \(text)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Slider(
                value: Binding(
                    get: { controller.quality },
                    set: {
                        controller.quality = $0
                        controller.scheduleEstimate()
                    }
                ),
                in: 0.1...1,
                step: 0.01
            )
            Text("The size is a fast estimate and may change slightly when the full-resolution file is encoded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatSection(_ controller: CompressionController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format")
                .font(.headline)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Include Metadata")
                    .font(.headline)
                Text("Camera EXIF, date, location and orientation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exportProgress(_ controller: CompressionController) -> some View {
        VStack(spacing: 10) {
            ProgressView(value: controller.progressFraction)
            HStack {
                Text(
                    "Processing \(min(controller.processedCount + 1, assets.count)) of \(assets.count)"
                )
                .font(.subheadline.monospacedDigit())
                Spacer()
                Button("Cancel", role: .destructive) {
                    isCancelConfirmationPresented = true
                }
            }
        }
        .padding()
        .background(.regularMaterial)
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

private struct CompressionPreview: View {
    @Bindable var controller: CompressionController
    @State private var dragStartAnchor: NormalizedPoint?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                if let image = controller.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    ProgressView()
                }

                if canRepositionCrop {
                    VStack {
                        Spacer()
                        Label("Drag to reposition crop", systemImage: "hand.draw")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(12)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
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
                        VStack(alignment: .leading, spacing: 4) {
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
    }
}

private struct CompressionChoiceStyle: ButtonStyle {
    let selected: Bool
    /// Passed in rather than read from the environment: `makeBody` is not a view
    /// body, so `@Environment` in a `ButtonStyle` never resolves.
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                selected
                    ? accent.opacity(configuration.isPressed ? 0.75 : 1)
                    : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selected ? accent : Color.secondary.opacity(0.18),
                        lineWidth: 1
                    )
            }
    }
}
