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
    /// Called with the new asset's id once it is saved and indexed, just
    /// before the screen closes. Cancel does not call it, so the host keeps the
    /// selection and the user can try another row on the same frames.
    var onSaved: (String) -> Void = { _ in }

    @State private var model: PhotoStackModel?
    /// The stroke under the finger, in normalized picture coordinates, drawn
    /// live until it lifts and becomes a real stroke.
    @State private var liveStroke: [NormalizedPoint] = []

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
            if let id {
                onSaved(id)
                dismiss()
            }
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
                if model.isRetouching {
                    retouchCanvas(model, imageSize: preview.size)
                }
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

    /// Paints over the preview. Points are kept normalized to the picture —
    /// top-left origin, like every other brush in the editor — so the stroke
    /// replays at full resolution on Save.
    private func retouchCanvas(_ model: PhotoStackModel, imageSize: CGSize) -> some View {
        GeometryReader { geometry in
            let rect = Self.fittedRect(imageSize, in: geometry.size)
            let width = CGFloat(model.brushSize) * min(rect.width, rect.height)
            Path { path in
                let points = liveStroke.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                if points.count == 1 { path.addLine(to: first) }
            }
            .stroke(EditorTheme.accent.opacity(0.45), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = (value.location.x - rect.minX) / rect.width
                        let y = (value.location.y - rect.minY) / rect.height
                        liveStroke.append(NormalizedPoint(x: min(1, max(0, x)), y: min(1, max(0, y))))
                    }
                    .onEnded { _ in
                        model.addRetouchStroke(points: liveStroke)
                        liveStroke = []
                    }
            )
        }
        .accessibilityLabel("Retouch canvas")
        .accessibilityHint("Paint to take this area from the selected frame.")
    }

    static func fittedRect(_ size: CGSize, in bounds: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: bounds) }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2,
                      width: fitted.width, height: fitted.height)
    }

    /// The brush, the frame it paints from, Undo and Done (FS-01.10 §5).
    @ViewBuilder
    private func retouchControls(_ model: PhotoStackModel) -> some View {
        Text(model.picksFrameAutomatically
             ? "Paint where the stack went wrong. Each stroke takes that area from the frame sharpest where it starts."
             : "Paint where the stack went wrong. Strokes take that area from the frame picked below.")
            .font(EditorTheme.maskSubtitle)
            .foregroundStyle(EditorTheme.dimText)
            .fixedSize(horizontal: false, vertical: true)

        EditorValueSlider(
            label: String(localized: "Brush", comment: "Focus Stack retouch slider: brush width"),
            value: model.brushSize * 100,
            range: (PhotoStackModel.brushSizeRange.lowerBound * 100)...(PhotoStackModel.brushSizeRange.upperBound * 100),
            valueText: "\(Int((model.brushSize * 100).rounded()))",
            accessibilityName: String(localized: "Brush size", comment: "Focus Stack retouch slider: brush width, accessibility name"),
            onBeginDrag: {},
            onDrag: { model.brushSize = $0 / 100 },
            onReset: { model.brushSize = 0.06 }
        )

        retouchFrameStrip(model)

        HStack {
            Button {
                model.undoRetouchStroke()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndoRetouch)
            .foregroundStyle(model.canUndoRetouch ? .white : EditorTheme.dimText)
            Spacer()
            Button("Done") { model.endRetouch() }
                .fontWeight(.semibold)
                .foregroundStyle(EditorTheme.accent)
        }
        .font(EditorTheme.rowLabel)
        .frame(minHeight: AppTheme.Size.minTouch)
    }

    /// Auto, then every frame that lined up, in stacking order — the editor's
    /// filmstrip thumbnails at their compact size.
    private func retouchFrameStrip(_ model: PhotoStackModel) -> some View {
        let side = EditorLayoutMetrics.wideFilmstripThumbnailSide
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    model.pickRetouchFrame(nil)
                } label: {
                    Text("Auto")
                        .font(EditorTheme.rowLabel.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: side, height: side)
                        .background(EditorTheme.control, in: RoundedRectangle.app(AppTheme.Radius.sm))
                        .overlay {
                            RoundedRectangle.app(AppTheme.Radius.sm)
                                .strokeBorder(model.picksFrameAutomatically ? EditorTheme.accent : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick the sharpest frame automatically")
                .accessibilityAddTraits(model.picksFrameAutomatically ? [.isSelected, .isButton] : .isButton)

                ForEach(model.retouchableFrames, id: \.self) { index in
                    let isCurrent = model.retouchFrame == index
                    Button {
                        model.pickRetouchFrame(index)
                    } label: {
                        EditorFilmstripThumbnail(asset: model.loadedAssets[index], photoLibrary: dependencies.photoLibrary)
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle.app(AppTheme.Radius.sm))
                            .overlay {
                                // Accent for a frame the user picked; grey for
                                // the one Auto last chose, so the two never look
                                // like the same choice.
                                RoundedRectangle.app(AppTheme.Radius.sm)
                                    .strokeBorder(
                                        isCurrent ? (model.picksFrameAutomatically ? EditorTheme.secondaryText : EditorTheme.accent) : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                            .opacity(isCurrent ? 1 : 0.72)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Frame \(index + 1) of \(model.loadedAssets.count)")
                    .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        .frame(height: side)
    }

    /// Method, and the two sliders Helicon and Zerene both expose (FS-01.10 §3).
    @ViewBuilder
    private func focusControls(_ model: PhotoStackModel) -> some View {
        Picker("Method", selection: Binding(
            get: { model.focusOptions.method },
            set: { model.selectFocusMethod($0) }
        )) {
            ForEach(FocusStackOptions.Method.allCases) { method in
                Text(method.displayName).tag(method)
            }
        }
        .pickerStyle(.segmented)

        Text(model.focusOptions.method.purposeDescription)
            .font(EditorTheme.maskSubtitle)
            .foregroundStyle(EditorTheme.dimText)
            .fixedSize(horizontal: false, vertical: true)

        let options = model.focusOptions
        EditorValueSlider(
            label: String(localized: "Radius", comment: "Focus Stack slider: size of the area sharpness is judged over"),
            value: Double(options.radius),
            range: 1...10,
            valueText: "\(options.radius)",
            accessibilityName: String(localized: "Radius", comment: "Focus Stack slider: size of the area sharpness is judged over"),
            onBeginDrag: {},
            onDrag: { value in
                let radius = Int(value.rounded())
                if radius != model.focusOptions.radius {
                    model.requestFocusOptions(FocusStackOptions(method: options.method, radius: radius, smoothing: model.focusOptions.smoothing))
                }
            },
            onReset: {
                let defaults = FocusStackOptions.defaults(for: options.method)
                model.requestFocusOptions(FocusStackOptions(method: options.method, radius: defaults.radius, smoothing: model.focusOptions.smoothing))
            }
        )
        EditorValueSlider(
            label: String(localized: "Smoothing", comment: "Focus Stack slider: how much the choice between frames is blurred"),
            value: Double(options.smoothing),
            range: 0...10,
            valueText: "\(options.smoothing)",
            accessibilityName: String(localized: "Smoothing", comment: "Focus Stack slider: how much the choice between frames is blurred"),
            onBeginDrag: {},
            onDrag: { value in
                let smoothing = Int(value.rounded())
                if smoothing != model.focusOptions.smoothing {
                    model.requestFocusOptions(FocusStackOptions(method: options.method, radius: model.focusOptions.radius, smoothing: smoothing))
                }
            },
            onReset: {
                let defaults = FocusStackOptions.defaults(for: options.method)
                model.requestFocusOptions(FocusStackOptions(method: options.method, radius: model.focusOptions.radius, smoothing: defaults.smoothing))
            }
        )

        Button {
            model.beginRetouch()
        } label: {
            Label(model.retouchStrokes.isEmpty ? "Retouch" : "Retouch (\(model.retouchStrokes.count))",
                  systemImage: "paintbrush.pointed")
                .font(EditorTheme.rowLabel.weight(.semibold))
        }
        .foregroundStyle(model.canRetouch ? EditorTheme.accent : EditorTheme.dimText)
        .disabled(!model.canRetouch)
        .frame(minHeight: AppTheme.Size.minTouch)
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

            if model.mode == .focusStack {
                if model.isRetouching {
                    retouchControls(model)
                } else {
                    focusControls(model)
                }
            }

            if let message = model.missingFramesMessage {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
                    Label(message, systemImage: "icloud.slash")
                        .font(EditorTheme.maskSubtitle)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") { model.retryMissingFrames() }
                        .font(EditorTheme.rowLabel.weight(.semibold))
                        .foregroundStyle(EditorTheme.accent)
                        .disabled(model.isWorking)
                        .frame(minHeight: AppTheme.Size.minTouch)
                }
            }

            if let message = model.excludedFramesMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(EditorTheme.maskSubtitle)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.mode.needsAlignment {
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
        // On the panel, not beside the screen's alert: two presentations on
        // one view and the alert never shows. An alert, not a confirmation
        // dialog: iOS 26 draws that as a popover with its Cancel hidden
        // (REVIEW_QUEUE 2026-09-19, the Settings blocker).
        .alert(
            "Clear Retouch?",
            isPresented: Binding(get: { model.pendingFocusOptions != nil }, set: { if !$0 { model.pendingFocusOptions = nil } })
        ) {
            Button("Clear Retouch and Change", role: .destructive) { model.confirmPendingFocusOptions() }
            Button("Keep Retouch", role: .cancel) { model.pendingFocusOptions = nil }
        } message: {
            Text("Your retouch strokes were painted over this stack. Changing Method, Radius or Smoothing clears them.")
        }
    }
}

extension View {
    /// Presents a Combine Photos screen. There is no onDismiss on purpose:
    /// Cancel leaves the selection as it was (FS-01.09 §3); only a save reports
    /// back, through `onSaved`.
    func photoStackCover(
        _ presentation: Binding<PhotoStackPresentation?>,
        onSaved: @escaping (String) -> Void
    ) -> some View {
        fullScreenCover(item: presentation) { presentation in
            PhotoStackScreen(presentation: presentation, onSaved: onSaved)
        }
    }
}
