import ShotDexKit
import SwiftUI

/// Export… (FS-03.07b §3): one Form of four sections — Destination, Export,
/// File Names and the summary — on a phone; on iPad the same rows in the
/// two-column card of the Mac-style canvas (`IP23_Export`, `IPP19_Export`).
/// Tier A.
struct FileExportSheet: View {
    enum Layout { case form, card }

    @State var model: FileExportModel
    let layout: Layout
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    enum Route: Hashable { case fileName }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.stage {
                case .choosing, .planning, .confirmingReplace:
                    switch layout {
                    case .form: form
                    case .card: card
                    }
                case .running:
                    FileExportRunningView(model: model)
                        .modifier(RunTitle(model: model))
                case .finished:
                    FileExportSummaryView(model: model) { dismiss() }
                        .modifier(RunTitle(model: model))
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .fileName: FileNameScreen(model: model)
                }
            }
        }
        .modifier(FileExportSizing(layout: layout))
        // A run can't be swiped away; Cancel asks first.
        .interactiveDismissDisabled(model.isRunning)
        .onChange(of: scenePhase) { _, phase in
            // Like Upload: leaving the app stops the run; Export Remaining
            // picks it up (FS-03.07b §2).
            if phase == .background, model.isRunning { model.cancel() }
            if phase == .active, model.stage == .choosing { model.refreshFolder() }
        }
        .sensoryFeedback(.success, trigger: model.stage) { _, stage in
            stage == .finished && model.report.map { $0.failed.isEmpty && $0.stoppedBy == nil && !$0.wasCancelled } == true
        }
        .alert(replaceTitle, isPresented: Binding(
            get: { if case .confirmingReplace = model.stage { true } else { false } },
            set: { if !$0 { model.cancelReplace() } }
        )) {
            Button(ExportCopy.replace, role: .destructive) { model.confirmReplace() }
            Button(String(localized: "Cancel", table: ExportCopy.table, comment: "Export: do not replace"), role: .cancel) { model.cancelReplace() }
        }
        .alert(spaceTitle, isPresented: $model.spaceAlert) {
            Button(ExportCopy.ok, role: .cancel) {}
        }
        .alert(ExportCopy.folderGone, isPresented: $model.goneFolderAlert) {
            Button(ExportCopy.ok, role: .cancel) {}
        }
        .sheet(isPresented: $model.isPickingFolder) {
            FolderPicker { model.pickFolder($0) }
                .ignoresSafeArea()
        }
    }

    /// *Not enough space in “Exports” — needs 1.2 GB, 300 MB free.*
    private var spaceTitle: String {
        if case .notEnoughSpace(let needed, let free)? = model.preflightFailure {
            return ExportCopy.notEnoughSpace(model.folders.current?.name ?? "", needed: needed, free: free)
        }
        return ""
    }

    private var replaceTitle: String {
        if case .confirmingReplace(let count) = model.stage {
            return ExportCopy.replaceTitle(count, folder: model.folders.current?.name ?? "")
        }
        return ""
    }

    // MARK: Phone

    private var form: some View {
        Form {
            Section {
                folderRow
                dateFoldersRow
            } header: {
                Text(ExportCopy.destination)
            }
            Section {
                modeRow
                exportRows
            } header: {
                Text(ExportCopy.exportSection)
            }
            Section {
                nameRow
                conflictRow
            } header: {
                Text(ExportCopy.fileNames)
            } footer: {
                summary
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel", table: ExportCopy.table, comment: "Export sheet: close without exporting")) { dismiss() }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(ExportCopy.title).font(.headline)
                    Text(model.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(ExportCopy.title, action: export)
                    .disabled(!model.canExport || model.stage != .choosing)
            }
        }
    }

    // MARK: iPad

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ExportCopy.title).font(.title3.weight(.semibold))
                Text(model.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .padding(.horizontal, FileExportMetrics.cardPadding)
            .padding(.top, FileExportMetrics.cardPadding)
            .padding(.bottom, AppTheme.Spacing.sm)

            ScrollView {
                HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                        CardGroup(title: ExportCopy.destination) {
                            folderRow
                            Divider()
                            dateFoldersRow
                        }
                        CardGroup(title: ExportCopy.exportSection) {
                            modeRow.padding(.vertical, AppTheme.Spacing.sm)
                            exportRows
                        }
                    }
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        CardGroup(title: ExportCopy.fileNames) {
                            nameRow
                            Divider()
                            conflictRow
                        }
                        if let example = model.exampleName {
                            Text(ExportCopy.example(example))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, AppTheme.Spacing.xs)
                        }
                    }
                }
                .padding(.horizontal, FileExportMetrics.cardPadding)
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            Divider()
            HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                summary
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(String(localized: "Cancel", table: ExportCopy.table, comment: "Export sheet: close without exporting")) { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button(ExportCopy.title, action: export)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canExport || model.stage != .choosing)
            }
            .padding(.horizontal, FileExportMetrics.cardPadding)
            .padding(.vertical, AppTheme.Spacing.lg)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Rows

    private var folderRow: some View {
        Menu {
            Section {
                ForEach(model.folders.recents) { folder in
                    Button {
                        model.useFolder(folder)
                    } label: {
                        if folder.id == model.folders.current?.id {
                            Label(folder.title, systemImage: "checkmark")
                        } else {
                            Text(folder.title)
                        }
                    }
                }
            }
            Button(ExportCopy.chooseFolder) { model.isPickingFolder = true }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "folder").foregroundStyle(Color(.systemBlue))
                Text(ExportCopy.folder).foregroundStyle(.primary)
                Spacer(minLength: AppTheme.Spacing.sm)
                Text(folderValue).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    .opacity(model.isFolderNotConnected ? 0.5 : 1)
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
            }
            .modifier(RowHeight(layout: layout))
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityLabel(ExportCopy.folder)
        .accessibilityValue(folderValue)
    }

    /// `T7 › Exports`, `T7 › Exports — Not connected`, or None.
    private var folderValue: String {
        model.isFolderNotConnected ? "\(model.folderTitle) — \(ExportCopy.notConnected)" : model.folderTitle
    }

    private var dateFoldersRow: some View {
        Toggle(isOn: $model.settings.dateFolders) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ExportCopy.dateFolders)
                if let example = model.dateFolderExample {
                    Text(verbatim: example).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .modifier(RowHeight(layout: layout))
    }

    private var modeRow: some View {
        Picker(ExportCopy.exportAs, selection: $model.settings.mode) {
            ForEach(FileExportMode.allCases, id: \.self) { mode in
                Text(ExportCopy.mode(mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(ExportCopy.exportAs)
    }

    @ViewBuilder
    private var exportRows: some View {
        if model.showsVersion {
            divider
            menuRow(ExportCopy.version, value: ExportCopy.version(model.version), selection: $model.version) {
                ForEach(FileExportVersion.allCases, id: \.self) { Text(ExportCopy.version($0)).tag($0) }
            }
        }
        if model.showsRenderRows {
            divider
            menuRow(ExportCopy.size, value: model.preset.name, selection: Binding(
                get: { model.settings.presetId },
                set: { model.choosePreset($0) }
            )) {
                ForEach(model.presets) { Text($0.name).tag($0.id) }
            }
            divider
            menuRow(ExportCopy.format, value: ExportCopy.formatName(model.settings.format), selection: $model.settings.format) {
                ForEach(PhotoOutputFormat.allCases) { Text(ExportCopy.formatName($0)).tag($0) }
            }
            divider
            menuRow(ExportCopy.quality, value: ExportCopy.qualityText(model.settings.quality), selection: Binding(
                get: { FileExportQuality.nearest(model.settings.quality) },
                set: { model.settings.quality = $0 }
            )) {
                ForEach(FileExportQuality.steps, id: \.self) { Text(ExportCopy.qualityText($0)).tag($0) }
            }
            divider
            menuRow(ExportCopy.metadata, value: String(localized: model.metadata.title), selection: $model.metadata) {
                ForEach(MetadataLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        if model.showsLivePhotoVideo {
            divider
            Toggle(ExportCopy.livePhotoVideo, isOn: $model.settings.includesLivePhotoVideo)
                .modifier(RowHeight(layout: layout))
        }
    }

    /// A row separator in the card; the Form draws its own.
    @ViewBuilder
    private var divider: some View {
        if layout == .card { Divider() }
    }

    private var nameRow: some View {
        NavigationLink(value: Route.fileName) {
            HStack(spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ExportCopy.name).foregroundStyle(.primary)
                    if layout == .form, let example = model.exampleName {
                        Text(verbatim: example).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: AppTheme.Spacing.sm)
                Text(ExportCopy.templateTitle(model.template))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if layout == .card {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .modifier(RowHeight(layout: layout))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(model.exampleName.map { ExportCopy.example($0) } ?? "")
    }

    private var conflictRow: some View {
        menuRow(ExportCopy.ifFileExists, value: ExportCopy.policy(model.settings.conflictPolicy), selection: $model.settings.conflictPolicy) {
            ForEach(FileExportConflictPolicy.allCases, id: \.self) { Text(ExportCopy.policy($0)).tag($0) }
        }
    }

    /// A row whose value opens a menu, the whole row the target: "Size
    /// 2048 px ⌃⌄", the title in the primary colour and the value in the
    /// secondary one, as the canvas draws it in both layouts.
    private func menuRow<Value: Hashable, Options: View>(
        _ title: String,
        value: String,
        selection: Binding<Value>,
        @ViewBuilder options: () -> Options
    ) -> some View {
        Menu {
            Picker(title, selection: selection, content: options)
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: AppTheme.Spacing.sm)
                Text(value).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
            }
            .modifier(RowHeight(layout: layout))
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.isFolderNotConnected, let drive = model.folders.current?.place {
                Text(ExportCopy.connectDrive(drive))
            }
            ForEach(model.summaryLines, id: \.self) { Text(verbatim: $0) }
        }
    }

    private func export() { model.start() }
}

/// The run's and the summary's bar: Export, the folder under it.
private struct RunTitle: ViewModifier {
    let model: FileExportModel

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(ExportCopy.title).font(.headline)
                        Text(verbatim: model.folderTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
    }
}

/// 44pt rows in the card; the Form sizes its own.
private struct RowHeight: ViewModifier {
    let layout: FileExportSheet.Layout

    func body(content: Content) -> some View {
        switch layout {
        case .form: content
        case .card: content.frame(minHeight: AppTheme.Size.minTouch)
        }
    }
}

/// The card's grouped rows: a title over a rounded group, as the Form draws
/// its sections.
private struct CardGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title).font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.md))
        }
    }
}

/// The sheet's size: the phone's large detent, or the iPad card at the
/// width the canvas draws it (FS-03.07c §1 item 2: at most 700pt, centred).
private struct FileExportSizing: ViewModifier {
    let layout: FileExportSheet.Layout

    func body(content: Content) -> some View {
        switch layout {
        case .form:
            content.presentationDetents([.large])
        case .card:
            if #available(iOS 18.0, *) {
                content
                    .frame(width: FileExportMetrics.cardWidth, height: FileExportMetrics.cardHeight)
                    .presentationSizing(.fitted)
            } else {
                content.frame(idealWidth: FileExportMetrics.cardWidth, idealHeight: FileExportMetrics.cardHeight)
            }
        }
    }
}

/// The iPad card's geometry, from `IP23_Export` (700 × 640, 25 inset).
enum FileExportMetrics {
    static let cardWidth: CGFloat = 700
    static let cardHeight: CGFloat = 640
    static let cardPadding: CGFloat = AppTheme.Spacing.xxl
}
