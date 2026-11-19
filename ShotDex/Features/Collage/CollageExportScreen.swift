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
    @State private var width: CGFloat = 0

    /// The Duo's inner display and an iPad: preview leading, the options an
    /// inspector beside it, the action on the toolbar (board `IP_CollageExport`).
    private var isWide: Bool { width >= WideLayout.minimumWidth }

    private var pixelSize: CGSize { model.outputPixelSize(for: options.size) }
    private var dimensionsText: String { "\(Int(pixelSize.width)) × \(Int(pixelSize.height))" }

    var body: some View {
        ZStack {
            background
            if isWide {
                wideLayout
            } else {
                VStack(spacing: 0) {
                    topBar
                    previewArea
                    optionsCard
                    saveSection
                }
            }
        }
        .measureWidth(into: $width)
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
        .onChange(of: model.sharingAssetID) { _, assetID in
            // Share… (FS-11b §3): saved first, then the share sheet with the
            // new photo at Settings' metadata level; closing it goes on as
            // Save does.
            guard let assetID else { return }
            guard let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first else {
                model.finishSharing()
                return
            }
            Task {
                await PhotoShareSheet.share(
                    assets: [asset],
                    downloads: dependencies.originalDownloads,
                    onFinished: { model.finishSharing() }
                )
            }
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

    // MARK: Wide layout (regular width)

    /// The inspector's width, the same as the other wide tier-D tools'.
    private static let inspectorWidth: CGFloat = 360
    /// The toolbar row's height; the preview and the inspector start under it.
    private static let wideBarHeight: CGFloat = 44

    private var wideLayout: some View {
        HStack(spacing: 0) {
            previewArea
                .padding(.top, Self.wideBarHeight)
                .overlay {
                    if model.isExporting { exportHero }
                }
            wideInspector
        }
        .overlay(alignment: .top) { wideTopBar }
    }

    private var wideTopBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                    .editorGlass(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Back"))

            VStack(alignment: .leading, spacing: 1) {
                Text("Export")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(dimensionsText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(EditorTheme.secondaryText)
            }

            Spacer()

            if serverExport == nil {
                wideShareButton
            }
            wideSaveButton
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: Self.wideBarHeight)
    }

    /// The primary action on the toolbar's trailing edge (FS-21.02b §2).
    /// While the collage is drawn and saved it reads "Saving…" rather than
    /// greying out without a word.
    private var wideSaveButton: some View {
        Button {
            Task { await model.export(options) }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                if model.isExporting {
                    ProgressView().tint(.black).controlSize(.small)
                    Text(String(localized: "Saving…", comment: "Collage export toolbar button while the collage is being saved"))
                } else {
                    Text(primaryActionTitle)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(height: AppTheme.Size.minTouch)
            .background(EditorTheme.accent.opacity(model.isExporting ? 0.6 : 1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    /// Share… beside Save to Photos (board `IP_CollageExport`): a glass
    /// capsule, the secondary of the pair. Not for server photos — their
    /// Export… sheet already has Share (FS-17.06 §5b).
    private var wideShareButton: some View {
        Button {
            Task { await model.export(options, thenShare: true) }
        } label: {
            Text(Self.shareTitle)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: AppTheme.Size.minTouch)
                .editorGlass(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }

    private static let shareTitle = String(localized: "Share…", comment: "Collage export: save the collage, then open the share sheet with it")

    /// Saving, or saved and waiting on the share sheet.
    private var isBusy: Bool { model.isExporting || model.sharingAssetID != nil }

    private var primaryActionTitle: String {
        serverExport == nil
            ? String(localized: "Save to Photos")
            : String(localized: "Export…", comment: "Collage of server photos: choose where the collage goes")
    }

    private var wideInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                inspectorHeader(String(localized: "Size"))
                CollageSegmentPicker(
                    items: CollageExportSize.allCases,
                    selection: $options.size,
                    label: { $0.displayName },
                    fillsWidth: true
                )
                inspectorDivider
                qualityRow.frame(minHeight: AppTheme.Size.minTouch)
                inspectorDivider
                inspectorHeader(String(localized: "Format"))
                CollageSegmentPicker(
                    items: CollageExportFormat.allCases,
                    selection: $options.format,
                    label: { $0.displayName },
                    fillsWidth: true
                )
                inspectorDivider
                Toggle(isOn: $options.keepFirstPhotoEXIF) {
                    Text("Keep EXIF of first photo")
                        .font(rowLabelFont)
                        .foregroundStyle(.white)
                }
                .tint(EditorTheme.accent)
                .frame(minHeight: AppTheme.Size.minTouch)
                inspectorDivider
                estimateRow.frame(minHeight: AppTheme.Size.minTouch)
                inspectorDivider
                if serverExport == nil {
                    Label("Added to your ShotDex Collages album", systemImage: "rectangle.stack.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                Text(serverExport == nil
                     ? String(localized: "Opens the new photo when done")
                     : String(localized: "Choose the folder, Photos or Share next.", comment: "Collage of server photos: what Export… opens"))
                    .font(.footnote)
                    .foregroundStyle(EditorTheme.secondaryText)
                if let preparation = model.exportPreparation, preparation.state.phase == .failed {
                    exportFailure(preparation.state)
                        .padding(.top, AppTheme.Spacing.lg)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, Self.wideBarHeight + AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .disabled(model.isExporting)
        .frame(width: Self.inspectorWidth)
        .background(EditorTheme.panelSolid.opacity(0.92).ignoresSafeArea())
        .overlay(alignment: .leading) {
            Rectangle().fill(EditorTheme.hairline).frame(width: 1).ignoresSafeArea()
        }
    }

    /// The phone's card keeps its compact rows; the wide inspector reads at
    /// arm's length on a 13" display (board `IP_CollageExport`: 17 / 15).
    private var rowLabelFont: Font { isWide ? .body : EditorTheme.rowLabel }
    private var rowValueFont: Font { isWide ? .subheadline.monospacedDigit() : EditorTheme.rowValue }

    private func inspectorHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(EditorTheme.secondaryText)
            .padding(.top, AppTheme.Spacing.sm)
    }

    private var inspectorDivider: some View {
        Rectangle().fill(EditorTheme.hairline).frame(height: 1).padding(.vertical, AppTheme.Spacing.sm)
    }

    /// While the collage is drawn and saved, the progress is the thing on
    /// screen: the shared job card centred over the preview. The originals'
    /// download is the one part with a measurable fraction, so it gets the
    /// bar (and the time left); the draw-and-encode step after it has no
    /// fraction and spins.
    private var exportHero: some View {
        let title = serverExport == nil
            ? String(localized: "Saving Collage…", comment: "Collage export in progress, headline")
            : String(localized: "Preparing Collage…", comment: "Collage of server photos being drawn before the export sheet opens")
        if let preparation = model.exportPreparation, preparation.isShown,
           preparation.state.downloadCount > 0 {
            return JobProgressCard(title: title, fraction: preparation.state.fraction, detail: preparation.state.progressLine)
        }
        return JobProgressCard(title: title, fraction: nil, detail: "\(dimensionsText) · \(options.format.displayName)")
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
                .font(rowLabelFont)
                .foregroundStyle(.white)
            Slider(value: $options.quality, in: 0...100)
                .tint(EditorTheme.accent)
            Text("\(Int(options.quality))")
                .font(rowValueFont)
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var estimateRow: some View {
        HStack {
            Text("Estimated size")
                .font(rowLabelFont)
                .foregroundStyle(EditorTheme.secondaryText)
            Spacer()
            Text(estimateText)
                .font(rowValueFont)
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
                if serverExport == nil {
                    shareButton
                }
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
        .disabled(isBusy)
    }

    /// The phone's secondary action under Save to Photos: 44pt, glass
    /// (FS-11b §1, H1).
    private var shareButton: some View {
        Button {
            Task { await model.export(options, thenShare: true) }
        } label: {
            Text(Self.shareTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.Size.minTouch)
                .editorGlass(cornerRadius: AppTheme.Radius.md)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
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
    /// The wide inspector's version: the segments share the column's width.
    var fillsWidth = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                        .frame(height: fillsWidth ? 32 : 28)
                        // Neutral, not the accent: Save to Photos is the one
                        // accent button on this screen (DESIGN.md §3.1).
                        .background(
                            selection == item ? Color.white.opacity(0.24) : Color.clear,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}
