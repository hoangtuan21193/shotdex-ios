import AppKit
import ShotDexKit
import SwiftUI

/// The Resize page (board `MAC_Compress`): before and after at 100% with a
/// divider, the table of every photo, and the inspector of 300 on the right.
/// Always dark, chrome included (D10); the accent only on Resize N Photos.
struct MacResizePage: View {
    @Bindable var model: MacResizeModel
    /// Cancel, ◀ and Done: back where it was opened.
    let close: () -> Void
    @State private var choosesFolder = false

    var body: some View {
        HStack(spacing: 0) {
            // Heights from the room there is: the preview keeps the board's 372
            // while it fits, the table takes the rest and scrolls inside.
            GeometryReader { geometry in
                let note: CGFloat = 52
                let preview = min(372, max(160, (geometry.size.height - 16 - 16 - note) * 0.55))
                VStack(alignment: .leading, spacing: 0) {
                    MacResizePreviewView(model: model)
                        .frame(height: preview)
                        .padding([.horizontal, .top], 16)
                    MacResizeTable(model: model)
                        .frame(height: max(100, geometry.size.height - preview - 16 - 16 - note))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    Text("RAW files are saved as JPEG at the new size. Originals stay where they are unless you choose to remove them. ShotDex never edits file contents.",
                         comment: "Mac Resize: the note under the table")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.Editor.secondaryText)
                        .lineLimit(2)
                        .frame(height: note, alignment: .center)
                        .padding(.horizontal, 28)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            if model.showsInspector {
                Rectangle().fill(MacTheme.Editor.hairline).frame(width: 1)
                MacResizeInspector(model: model, choosesFolder: $choosesFolder)
                    .frame(width: 300)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(MacTheme.Editor.label)
        .navigationTitle(String(localized: "Resize", comment: "Mac Resize: the page title"))
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .fileImporter(isPresented: $choosesFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.choose(url) }
        }
        .onExitCommand(perform: cancel)
        .task { await model.load() }
        .onDisappear { model.close() }
    }

    /// "8 photos · 194.3 MB from 4 sources".
    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
        return MacInflect.string("^[\(model.rows.count) photo](inflect: true) · \(size) from ^[\(model.sourceCount) source](inflect: true)",
                                 comment: "Mac Resize: subtitle with the count, size and sources")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: cancel) {
                Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .help(String(localized: "Back (⌘[ or Esc)", comment: "Mac Resize toolbar: leave"))
            .accessibilityIdentifier("resize.back")
        }

        ToolbarItem(placement: .primaryAction) {
            Button { model.showsInspector.toggle() } label: {
                Label(String(localized: "Inspector", comment: "Mac Resize toolbar"), systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(String(localized: "Show or hide the options (⌥⌘I)", comment: "Mac Resize toolbar"))
            .accessibilityValue(model.showsInspector ? String(localized: "Shown", comment: "VoiceOver: a panel is shown")
                                                     : String(localized: "Hidden", comment: "VoiceOver: a panel is hidden"))
            .accessibilityIdentifier("resize.inspector")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            switch model.stage {
            case .editing:
                Button(String(localized: "Cancel", comment: "Mac Resize toolbar: leave without resizing"), action: cancel)
                    .accessibilityIdentifier("resize.cancel")
                Button(model.commandTitle, action: model.run)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
                    .disabled(model.isLoading || model.reachable.isEmpty)
                    .accessibilityIdentifier("resize.go")
            case .running(let done, let total):
                HStack(spacing: 6) {
                    ProgressView(value: Double(done), total: Double(max(1, total))).frame(width: 80)
                    Text("Resizing \(done + 1) of \(total)", comment: "Mac Resize toolbar: progress").font(.system(size: 12)).monospacedDigit()
                }
                Button(String(localized: "Stop", comment: "Mac Resize toolbar: stop the run"), action: model.stop)
                    .accessibilityIdentifier("resize.stop")
            case .removing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Removing originals…", comment: "Mac Resize toolbar: the originals are being removed").font(.system(size: 12))
                }
            case .finished(let summary):
                if let folder = summary.folder {
                    Button(String(localized: "Show in Finder", comment: "Mac Resize toolbar: open the folder of resized files")) {
                        NSWorkspace.shared.open(folder)
                    }
                    .accessibilityIdentifier("resize.reveal")
                }
                Button(String(localized: "Done", comment: "Mac Resize toolbar: leave after a run"), action: close)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
                    .accessibilityIdentifier("resize.done")
            }
        }
    }

    /// Back, Cancel, Esc: leave. A run keeps going (Activity says how it ends);
    /// only Stop stops it.
    private func cancel() { close() }
}

// MARK: - Preview

/// Before | After with a draggable divider; the zoom popup and the photo's
/// name and position on it.
private struct MacResizePreviewView: View {
    @Bindable var model: MacResizeModel
    /// Where the divider is, 0…1 across.
    @State private var split = 0.5

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                MacTheme.Editor.panel
                if let before = model.before, let after = model.after {
                    picture(before, geometry.size)
                    picture(after, geometry.size)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: max(0, width * (1 - split))).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    divider(height: geometry.size.height)
                        .position(x: width * split, y: geometry.size.height / 2)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            split = min(0.95, max(0.05, value.location.x / max(1, width)))
                        })
                } else if let problem = model.previewProblem {
                    Text(problem).font(.system(size: 12)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .multilineTextAlignment(.center).frame(maxWidth: 360)
                } else {
                    ProgressView().controlSize(.small)
                }
                overlays
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Before and after", comment: "Mac Resize: the preview"))
        }
    }

    private func picture(_ image: CGImage, _ size: CGSize) -> some View {
        Image(decorative: image, scale: 2)
            .resizable()
            .interpolation(model.zoom == .actual ? .none : .high)
            .aspectRatio(contentMode: model.zoom == .actual ? .fill : .fit)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private func divider(height: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.white).frame(width: 2, height: height)
            Circle().fill(Color.white).frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.black))
        }
        .contentShape(Rectangle().inset(by: -10))
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Divider", comment: "Mac Resize: the before/after divider"))
        .accessibilityValue("\(Int((split * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            split = min(0.95, max(0.05, split + (direction == .increment ? 0.05 : -0.05)))
        }
        .accessibilityIdentifier("resize.divider")
    }

    @ViewBuilder
    private var overlays: some View {
        let row = model.rows.first { $0.id == model.previewId }
        VStack {
            HStack {
                if let row {
                    pill(String(localized: "Original · \(String(row.width))×\(String(row.height)) · \(ByteCountFormatter.string(fromByteCount: row.bytes, countStyle: .file))",
                                comment: "Mac Resize: the before label"))
                }
                Spacer()
                if let row, !row.isUnreachable {
                    let format = model.outputFormat(row) == .heic ? "HEIC" : "JPEG"
                    let estimate = model.estimate(row).map { " · ~" + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
                    pill(String(localized: "Resized · \(model.preset.name) · \(format) \(ExportCopy.qualityText(model.quality))\(estimate)",
                                comment: "Mac Resize: the after label"))
                }
            }
            Spacer()
            HStack {
                Menu {
                    ForEach(MacResizeZoom.allCases) { zoom in
                        Button(zoom.title) { model.zoom = zoom }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.zoom.title).font(.system(size: 12))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(MacTheme.Editor.label)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(String(localized: "Zoom", comment: "Mac Resize: the preview zoom"))
                .accessibilityValue(model.zoom.title)
                .accessibilityIdentifier("resize.zoom")
                Spacer()
                if let row, let index = model.rows.firstIndex(of: row) {
                    pill(String(localized: "\(row.name) · \(index + 1) of \(model.rows.count)", comment: "Mac Resize: which photo the preview shows"))
                }
            }
        }
        .padding(12)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MacTheme.Editor.label)
            .monospacedDigit()
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Table

/// Name · Source · Dimensions · Original · Estimated · Saved, a total row
/// under it. Clicking a row puts it in the preview.
private struct MacResizeTable: View {
    @Bindable var model: MacResizeModel

    var body: some View {
        VStack(spacing: 0) {
            Table(model.rows, selection: Binding(get: { model.previewId }, set: { model.previewId = $0 })) {
                TableColumn(String(localized: "Name", comment: "Mac Resize: table column")) { row in
                    HStack(spacing: 8) {
                        MacResizeThumbnail(id: row.id, model: model)
                        Text(row.name).fontWeight(.medium).lineLimit(1)
                    }
                }
                .width(min: 100, ideal: 130)
                TableColumn(String(localized: "Source", comment: "Mac Resize: table column")) { row in
                    Label(row.sourceName, systemImage: Self.symbol(row.kind)).labelStyle(.titleAndIcon).lineLimit(1)
                        .foregroundStyle(row.isUnreachable ? MacTheme.Editor.secondaryText : MacTheme.Editor.label)
                }
                .width(min: 80, ideal: 105)
                TableColumn(String(localized: "Dimensions", comment: "Mac Resize: table column")) { row in
                    let target = model.target(row)
                    Group {
                        if row.isUnreachable {
                            Text("Not on this Mac", comment: "Mac Resize: a server-only photo is skipped")
                                .foregroundStyle(MacTheme.Editor.secondaryText)
                        } else {
                            Text(verbatim: "\(row.width)×\(row.height) ").foregroundStyle(MacTheme.Editor.secondaryText)
                                + Text(verbatim: "→ \(Int(target.width))×\(Int(target.height))").foregroundStyle(MacTheme.Editor.label)
                        }
                    }
                    .monospacedDigit().lineLimit(1)
                }
                .width(min: 120, ideal: 145)
                TableColumn(String(localized: "Original", comment: "Mac Resize: table column")) { row in
                    Text(ByteCountFormatter.string(fromByteCount: row.bytes, countStyle: .file)).monospacedDigit()
                        .foregroundStyle(MacTheme.Editor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 52, ideal: 60)
                TableColumn(String(localized: "Estimated", comment: "Mac Resize: table column")) { row in
                    Text(model.estimate(row).map { "~" + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                        .monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 52, ideal: 64)
                TableColumn(String(localized: "Saved", comment: "Mac Resize: table column")) { row in
                    Text(saved(row)).monospacedDigit().fontWeight(.semibold)
                        .foregroundStyle(MacTheme.Editor.channelGreen)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 44, ideal: 52)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("resize.table")
            Divider()
            total
            if let skipped = model.rows.first(where: \.isUnreachable) {
                let count = model.rows.filter(\.isUnreachable).count
                Text(MacInflect.string("^[\(count) photo](inflect: true) only on \(skipped.sourceName) won’t be resized — its original isn’t on this Mac.",
                                       comment: "Mac Resize: server-only photos are skipped"))
                    .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("resize.skipped")
            }
        }
    }

    private var total: some View {
        HStack(spacing: 0) {
            Text(model.reachable.count == model.rows.count
                 ? MacInflect.string("^[\(model.rows.count) photo](inflect: true) from ^[\(model.sourceCount) source](inflect: true)",
                                     comment: "Mac Resize: the total row's label")
                 : String(localized: "\(model.reachable.count) of \(model.rows.count) photos", comment: "Mac Resize: the total row when some photos are skipped"))
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)).frame(width: 130, alignment: .trailing)
            Text(model.totalEstimate.map { "~" + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                .frame(width: 130, alignment: .trailing)
            Text(totalSaved).foregroundStyle(MacTheme.Editor.channelGreen).frame(width: 124, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .frame(height: 30)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("resize.total")
    }

    private func saved(_ row: MacResizeModel.Row) -> String {
        guard let estimate = model.estimate(row), row.bytes > 0 else { return "—" }
        return Self.percent(saved: row.bytes - estimate, of: row.bytes)
    }

    private var totalSaved: String {
        guard let estimate = model.totalEstimate, model.totalBytes > 0 else { return "—" }
        return Self.percent(saved: model.totalBytes - estimate, of: model.totalBytes)
    }

    /// "−97%"; a file that grows reads "+12%".
    static func percent(saved: Int64, of total: Int64) -> String {
        let fraction = Double(saved) / Double(total)
        let value = Int((fraction * 100).rounded())
        return value >= 0 ? "−\(value)%" : "+\(-value)%"
    }

    static func symbol(_ kind: MacResizeModel.Kind) -> String {
        switch kind {
        case .photos: "photo.on.rectangle"
        case .file: "folder"
        case .drive: "externaldrive"
        case .server: "server.rack"
        }
    }
}

/// A row's small picture, off the main actor.
/// (Table cells are hosted apart from the page: no environment objects
/// reach them, so the model hands the picture over.)
private struct MacResizeThumbnail: View {
    let id: String
    let model: MacResizeModel
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFill()
            } else {
                MacTheme.Editor.fill
            }
        }
        .frame(width: 20, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.Editor.thumbnailRadius))
        .task(id: id) { image = await model.thumbnail(id) }
    }
}

// MARK: - Inspector

private struct MacResizeInspector: View {
    @Bindable var model: MacResizeModel
    @Binding var choosesFolder: Bool

    private var isEditing: Bool { model.stage == .editing }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                group(String(localized: "Size", comment: "Mac Resize inspector")) {
                    Picker(String(localized: "Size", comment: "Mac Resize inspector"), selection: Binding(
                        get: { model.presetId },
                        set: { id in
                            model.presetId = id
                            // A preset of the user's carries its own quality and format.
                            if let preset = model.sizes.customPresets.first(where: { $0.id == id }) {
                                model.quality = FileExportQuality.clamped(preset.quality)
                                model.format = preset.format
                            }
                        })) {
                        ForEach(model.sizes.allPresets) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("resize.size")
                    Text(MacResizeWords.presetLine(model.preset))
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                }
                Divider().padding(.vertical, 12)
                group(String(localized: "Quality and Format", comment: "Mac Resize inspector")) {
                    HStack(spacing: 8) {
                        Text("Quality", comment: "Mac Resize inspector").foregroundStyle(MacTheme.Editor.secondaryText)
                            .frame(width: 56, alignment: .leading)
                        Slider(value: $model.quality, in: FileExportQuality.range, step: FileExportQuality.step)
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "Quality", comment: "Mac Resize inspector"))
                            .accessibilityIdentifier("resize.quality")
                        Text(ExportCopy.qualityText(model.quality)).font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(MacTheme.Editor.secondaryText).frame(width: 44, alignment: .trailing)
                    }
                    row(String(localized: "Format", comment: "Mac Resize inspector")) {
                        Picker(String(localized: "Format", comment: "Mac Resize inspector"), selection: $model.format) {
                            ForEach([PhotoOutputFormat.preserve, .jpeg, .heic], id: \.self) { Text(ExportCopy.formatName($0)).tag($0) }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("resize.format")
                    }
                    row(String(localized: "Metadata", comment: "Mac Resize inspector")) {
                        Picker(String(localized: "Metadata", comment: "Mac Resize inspector"), selection: $model.metadata) {
                            Text("All", comment: "Mac Resize: keep all metadata").tag(MetadataLevel.all)
                            Text("All Except Location", comment: "Mac export: metadata level without GPS").tag(MetadataLevel.noLocation)
                            Text("None", comment: "Mac Resize: no metadata").tag(MetadataLevel.noMetadata)
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("resize.metadata")
                    }
                }
                Divider().padding(.vertical, 12)
                group(String(localized: "Save To", comment: "Mac Resize inspector")) {
                    Menu {
                        Button(MacResizeFolder.shotDexResized.name) { model.useDefaultFolder() }
                        Button(String(localized: "Choose Folder…", comment: "Mac Resize: pick where resized files go")) { choosesFolder = true }
                    } label: {
                        Label(model.folder.name, systemImage: "folder")
                    }
                    .accessibilityIdentifier("resize.saveTo")
                    Text("Library photos go back to Photos. Folder and NAS photos go to \(model.folder.bookmark == nil ? String(localized: "Pictures › ShotDex Resized", comment: "Mac Resize: the default folder path") : model.folder.name), never into the folder they came from.",
                         comment: "Mac Resize: where the resized files go")
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().padding(.vertical, 12)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(String(localized: "Remove originals after resizing", comment: "Mac Resize: also delete the originals"),
                           isOn: $model.removesOriginals)
                        .toggleStyle(.checkbox)
                        .tint(MacTheme.Editor.accent)
                        .accessibilityIdentifier("resize.removeOriginals")
                    Text(model.removalWords)
                        .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 22)
                }
                if case .finished(let summary) = model.stage {
                    finished(summary).padding(.top, 16)
                } else {
                    estimateCard.padding(.top, 16)
                }
            }
            .font(.system(size: 13))
            .padding(16)
            .disabled(!isEditing)
        }
        .background(MacTheme.Editor.panelSolid)
    }

    /// "194.3 MB → ~9.4 MB" with a bar.
    private var estimateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)).foregroundStyle(MacTheme.Editor.secondaryText)
                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
                Text(model.totalEstimate.map { "~" + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                    .font(.system(size: 15, weight: .semibold))
            }
            .monospacedDigit()
            GeometryReader { geometry in
                let fraction = model.totalEstimate.map { model.totalBytes > 0 ? min(1, Double($0) / Double(model.totalBytes)) : 0 } ?? 0
                ZStack(alignment: .leading) {
                    Capsule().fill(MacTheme.Editor.sliderTrack)
                    Capsule().fill(MacTheme.Editor.channelGreen).frame(width: max(geometry.size.width * 0.05, geometry.size.width * fraction))
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            Text("A fast estimate — the final size may differ slightly.", comment: "Mac Resize: the estimate is approximate")
                .font(.system(size: 11)).foregroundStyle(MacTheme.Editor.secondaryText)
        }
        .padding(12)
        .background(MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("resize.estimate")
    }

    /// What the run did: "8 saved · 185 MB smaller", and what went wrong.
    private func finished(_ summary: MacResizeModel.Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(String(localized: "\(summary.saved) saved", comment: "Mac Resize: photos written")
                  + (summary.originalBytes > summary.savedBytes
                     ? " · " + String(localized: "\(ByteCountFormatter.string(fromByteCount: summary.originalBytes - summary.savedBytes, countStyle: .file)) smaller",
                                      comment: "Mac Resize: how much smaller the copies are")
                     : ""),
                  systemImage: "checkmark.circle")
                .font(.system(size: 13, weight: .semibold))
            if summary.wroteToPhotos > 0 {
                Text("\(summary.wroteToPhotos) went back to Photos.", comment: "Mac Resize: copies added to Photos")
            }
            if summary.removedOriginals > 0 {
                Text("^[\(summary.removedOriginals) original](inflect: true) removed.", comment: "Mac Resize: originals removed")
            }
            if summary.keptNoTrash > 0 {
                Text("^[\(summary.keptNoTrash) original](inflect: true) kept — the drive has no Trash.", comment: "Mac Resize: originals on a drive without a Trash were kept")
            }
            if summary.keptInPhotos {
                Text("You kept the originals in Photos.", comment: "Mac Resize: the user said Don't Allow in Photos' dialog")
            }
            if summary.keptBecauseStopped {
                Text("Originals kept because the run was stopped.", comment: "Mac Resize: Stop, so nothing was removed")
            }
            if summary.removeFailed {
                Text("The originals couldn’t be removed. The resized copies are saved.", comment: "Mac Resize: removing failed")
                    .foregroundStyle(MacTheme.redText)
            }
            if summary.failed > 0 {
                Text("^[\(summary.failed) photo](inflect: true) couldn’t be resized:", comment: "Mac Resize: failures")
                    .foregroundStyle(MacTheme.redText)
                ForEach(Array(summary.failures.prefix(3).enumerated()), id: \.offset) { _, failure in
                    Text("\(failure.name) — \(failure.reason)").fixedSize(horizontal: false, vertical: true)
                }
                if summary.failures.count > 3 {
                    Text("and \(summary.failures.count - 3) more", comment: "Mac Resize: more failures than listed")
                }
            }
            if summary.skipped > 0 {
                Text("^[\(summary.skipped) photo](inflect: true) skipped — not on this Mac.", comment: "Mac Resize: server-only photos skipped")
            }
            if summary.stopped {
                Text("Stopped. Photos already saved stay.", comment: "Mac Resize: the run was stopped")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(MacTheme.Editor.label)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.Editor.fill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("resize.summary")
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(MacTheme.Editor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(MacTheme.Editor.secondaryText).frame(width: 62, alignment: .leading)
            content()
        }
    }
}

enum MacResizeWords {
    /// "Long edge 2048 · Fit", "1080 × 1350 · Fill", "Original pixels".
    static func presetLine(_ preset: ResizePreset) -> String {
        switch preset.kind {
        case .original: String(localized: "Original pixels", comment: "Mac Settings › Editing: a preset that keeps the size")
        case .longEdge:
            String(localized: "Long edge \(String(preset.longEdge ?? 0)) · Fit", comment: "Mac Resize: a long-edge preset, fitted")
        case .exact:
            "\(String(preset.width ?? 0)) × \(String(preset.height ?? 0)) · "
                + (preset.cropMode == .fill ? String(localized: "Fill", comment: "Mac Settings › Editing: exact size, cropped to fill")
                                            : String(localized: "Fit", comment: "Mac Settings › Editing: exact size, fitted inside"))
        }
    }
}

extension MacResizeWords {
    /// Why one photo was not resized, in words that say what to do.
    static func reason(_ error: Error) -> String {
        if error is MacResizeWriter.SameFolder {
            return String(localized: "the Save To folder is where this photo lives. Choose another folder.", comment: "Mac Resize: a failure reason")
        }
        if let editing = error as? PhotoEditingError, editing == .missingSource || editing == .unavailable {
            return String(localized: "its original isn’t readable on this Mac.", comment: "Mac Resize: a failure reason")
        }
        if error is PhotoEditingError {
            return String(localized: "ShotDex couldn’t read or render it.", comment: "Mac Resize: a failure reason")
        }
        switch (error as? CocoaError)?.code {
        case .fileWriteOutOfSpace?: return String(localized: "the disk is full.", comment: "Mac Resize: a failure reason")
        case .fileWriteNoPermission?, .fileWriteVolumeReadOnly?:
            return String(localized: "the Save To folder is read-only.", comment: "Mac Resize: a failure reason")
        case .fileNoSuchFile?:
            return String(localized: "the Save To folder isn’t reachable.", comment: "Mac Resize: a failure reason")
        default:
            return String(localized: "it couldn’t be written.", comment: "Mac Resize: a failure reason")
        }
    }

    /// Activity's line for a finished run: "185 MB smaller · 3 originals removed".
    static func activityLine(_ summary: MacResizeModel.Summary) -> String {
        var parts: [String] = []
        if summary.originalBytes > summary.savedBytes {
            parts.append(String(localized: "\(ByteCountFormatter.string(fromByteCount: summary.originalBytes - summary.savedBytes, countStyle: .file)) smaller",
                                comment: "Mac Resize: how much smaller the copies are"))
        }
        if summary.failed > 0 { parts.append(String(localized: "\(summary.failed) not resized", comment: "Mac Activity: Resize failures")) }
        if summary.removedOriginals > 0 { parts.append(String(localized: "\(summary.removedOriginals) originals removed", comment: "Mac Activity: Resize removals")) }
        if summary.removeFailed { parts.append(String(localized: "originals couldn’t be removed", comment: "Mac Activity: Resize removal failed")) }
        if summary.stopped { parts.append(String(localized: "stopped", comment: "Mac Activity: a Resize run was stopped")) }
        return parts.joined(separator: " · ")
    }
}
