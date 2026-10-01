import SwiftUI

/// The collage Export screen (§12). Not a dismiss-on-confirm panel — it opens
/// full-screen over the editor: the finished collage blurred behind, a true
/// preview above it, and a dark-glass options card carrying the five export
/// decisions plus Save to Photos. Saving files the photo into the `Collages`
/// album and hands the new asset id back so the editor can open its detail.
struct CollageExportScreen: View {
    @Bindable var model: CollageEditorModel
    /// Set for a collage of server photos: the button opens the export
    /// sheet instead of saving to Photos (FS-17.06 §5b).
    var serverExport: ServerExportContext?
    let onClose: () -> Void
    /// Every destination of a server run has the collage.
    var onServerExported: () -> Void = {}

    @Environment(AppDependencies.self) private var dependencies
    @State private var serverExportModel: ServerExportModel?

    @Environment(\.dismiss) private var dismiss

    @State private var options = CollageExportOptions()
    @State private var preview: UIImage?

    private var pixelSize: CGSize { model.outputPixelSize(for: options.size) }
    private var dimensionsText: String { "\(Int(pixelSize.width)) × \(Int(pixelSize.height))" }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                previewArea
                optionsCard
                saveSection
            }
        }
        .preferredColorScheme(.dark)
        .task { preview = await model.renderPreview() }
        .onChange(of: model.composedFile) { _, file in
            guard let file, let serverExport else { return }
            serverExportModel = .makeComposed(
                .init(file: file, tool: .collage, firstFilename: model.firstPlacedFilename),
                photos: model.photos.compactMap(\.serverFile),
                context: serverExport,
                dependencies: dependencies
            )
        }
        .sheet(item: $serverExportModel, onDismiss: { model.composedFile = nil }) { exportModel in
            ServerExportSheet(model: exportModel) {
                serverExportModel = nil
                onServerExported()
            }
        }
    }

    // MARK: Background + preview

    @ViewBuilder
    private var background: some View {
        EditorTheme.background.ignoresSafeArea()
        if let preview {
            // Filled inside a view that takes the screen's size, so the
            // fill never widens the ZStack: a square collage on a portrait
            // phone otherwise laid the whole screen out 870pt wide, with the
            // top bar and the options card pushed off both edges.
            Color.clear
                .overlay {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 30)
                }
                .clipped()
                .overlay(Color.black.opacity(0.6))
                .ignoresSafeArea()
        }
    }

    private var previewArea: some View {
        Group {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .padding(AppTheme.Spacing.xl)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Top bar (leading cluster clears the Dynamic Island)

    private var topBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .editorGlass(Circle())
            }
            .accessibilityLabel(String(localized: "Back"))

            Text("Export")
                .font(EditorTheme.maskTitle)
                .foregroundStyle(.white)

            Spacer()

            Text(dimensionsText)
                .font(EditorTheme.rowValue)
                .foregroundStyle(EditorTheme.secondaryText)
        }
        .padding(.horizontal, AppTheme.Size.floatingChromeMargin)
        .padding(.top, EditorLayoutMetrics.editorFloatingCommandRowTopInset)
        .frame(height: 44 + EditorLayoutMetrics.editorFloatingCommandRowTopInset, alignment: .center)
    }

    // MARK: Options card

    private var optionsCard: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            segmentRow(title: String(localized: "Size")) {
                CollageSegmentPicker(
                    items: CollageExportSize.allCases,
                    selection: $options.size,
                    label: { $0.displayName }
                )
            }
            qualityRow
            segmentRow(title: String(localized: "Format")) {
                CollageSegmentPicker(
                    items: CollageExportFormat.allCases,
                    selection: $options.format,
                    label: { $0.displayName }
                )
            }
            Toggle(isOn: $options.keepFirstPhotoEXIF) {
                Text("Keep EXIF of first photo")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(.white)
            }
            .tint(EditorTheme.accent)
            estimateRow
        }
        .padding(AppTheme.Spacing.lg)
        .editorGlass(cornerRadius: AppTheme.Radius.lg)
        .padding(.horizontal, AppTheme.Size.screenMargin)
    }

    private func segmentRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(EditorTheme.rowLabel)
                .foregroundStyle(.white)
            Spacer()
            content()
        }
    }

    private var qualityRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text("Quality")
                .font(EditorTheme.rowLabel)
                .foregroundStyle(.white)
            Slider(value: $options.quality, in: 0...100)
                .tint(EditorTheme.accent)
            Text("\(Int(options.quality))")
                .font(EditorTheme.rowValue)
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var estimateRow: some View {
        HStack {
            Text("Estimated size")
                .font(EditorTheme.rowLabel)
                .foregroundStyle(EditorTheme.secondaryText)
            Spacer()
            Text(estimateText)
                .font(EditorTheme.rowValue)
                .foregroundStyle(.white)
        }
    }

    private var estimateText: String {
        let bytes = model.estimatedBytes(for: options)
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return "~\(size) · \(dimensionsText)"
    }

    // MARK: Save

    private var saveSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Not a "smart album": in this app that word means a saved rule
            // query. This is a plain album the export files into.
            if serverExport == nil {
                Label("Added to your ShotDex Collages album", systemImage: "rectangle.stack.badge.plus")
                    .font(.footnote)
                    .foregroundStyle(EditorTheme.secondaryText)
            }

            if let preparation = model.exportPreparation, preparation.state.phase == .failed {
                exportFailure(preparation.state)
            } else {
                if let preparation = model.exportPreparation, preparation.isShown,
                   preparation.state.downloadCount > 0 {
                    // The cells' originals come down before the collage is
                    // drawn (FS-02.06 §9): the line and its bar, here.
                    OriginalDownloadLine(state: preparation.state, textColor: EditorTheme.secondaryText)
                        .tint(EditorTheme.accent)
                }
                saveButton
            }

            Text(serverExport == nil
                 ? String(localized: "Opens the new photo when done")
                 : String(localized: "Choose the folder, Photos or Share next.", comment: "Collage of server photos: what Export… opens"))
                .font(.caption)
                .foregroundStyle(EditorTheme.dimText)
        }
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.lg)
    }

    private var saveButton: some View {
        Button {
            Task { await model.export(options) }
        } label: {
            Group {
                if model.isExporting {
                    ProgressView().tint(.black)
                } else {
                    Text(serverExport == nil
                         ? String(localized: "Save to Photos")
                         : String(localized: "Export…", comment: "Collage of server photos: choose where the collage goes"))
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Size.primaryActionHeight)
            .background(EditorTheme.accent, in: RoundedRectangle.app(AppTheme.Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(model.isExporting)
    }

    /// A cell's original did not come down (FS-02.06 AC-12): nothing was
    /// saved. Retry runs the export again; Cancel puts the message away.
    private func exportFailure(_ state: OriginalPreparationState) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Label(state.failureTitle, systemImage: "exclamationmark.icloud")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(state.failureNamesText)
                .font(.footnote)
                .foregroundStyle(EditorTheme.secondaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: AppTheme.Spacing.sm) {
                Button {
                    model.dismissExportFailure()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Size.primaryActionHeight)
                        .editorGlass(cornerRadius: AppTheme.Radius.md)
                }
                Button {
                    Task { await model.export(options) }
                } label: {
                    Text("Retry")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Size.primaryActionHeight)
                        .background(EditorTheme.accent, in: RoundedRectangle.app(AppTheme.Radius.md))
                }
                .disabled(model.isExporting)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A compact dark-glass segmented control for the Export options.
struct CollageSegmentPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == item ? .black : .white)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .frame(height: 28)
                        .background(
                            selection == item ? EditorTheme.accent : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}
