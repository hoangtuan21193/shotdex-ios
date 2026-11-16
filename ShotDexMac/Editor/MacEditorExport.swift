import AppKit
import ShotDexKit
import SwiftUI

// MARK: - Choices

/// Save as Copy · Export Files (FS-18.03 §4, D16): there is no "Save Edit" —
/// edits save on their own.
enum MacExportOutput: String, Codable, CaseIterable, Sendable {
    case copy
    case files
}

/// What the Save and Export sheet remembers for next time (FS-03.07b §3):
/// the iPhone's export choices, the watermark row and which output. Metadata
/// and Version are not here: they start at the Settings level and at Edited.
struct MacExportChoices: Codable, Equatable, Sendable {
    var output = MacExportOutput.copy
    var files = FileExportSettings()
    var watermark = WatermarkSettings()

    init() {}

    /// Lossy, one field at a time, like `FileExportSettings`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MacExportChoices()
        output = (try? container.decode(MacExportOutput.self, forKey: .output)) ?? defaults.output
        files = (try? container.decode(FileExportSettings.self, forKey: .files)) ?? defaults.files
        watermark = (try? container.decode(WatermarkSettings.self, forKey: .watermark)) ?? defaults.watermark
    }

    private enum CodingKeys: String, CodingKey { case output, files, watermark }

    static let key = "mac.export.choices"

    static func remembered(_ defaults: UserDefaults = .standard) -> MacExportChoices {
        // Nothing remembered yet: Settings › Editing › Export Defaults.
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(MacExportChoices.self, from: $0) } ?? defaultChoices(defaults)
    }

    func remember(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// A named set of choices — the header's Preset popup and Save Preset….
struct MacExportPreset: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var choices: MacExportChoices

    static let key = "mac.export.presets"

    static func all(_ defaults: UserDefaults = .standard) -> [MacExportPreset] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(LossyArray<MacExportPreset>.self, from: data) else { return [] }
        return decoded.elements
    }

    static func save(_ presets: [MacExportPreset], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: key) }
    }
}

/// One export the editor runs: everything worked out on the main actor,
/// so the file work needs nothing else.
struct MacExportRequest: Sendable {
    var output: MacExportOutput
    var mode: FileExportMode
    var version: FileExportVersion
    var preset: ResizePreset
    var format: PhotoOutputFormat
    var quality: Double
    var colorSpace: ExportColorSpace
    var metadata: MetadataLevel
    var template: FileNameTemplate
    var policy: FileExportConflictPolicy
    var dateFolders: Bool
    /// Export Files: the folder, resolved and reachable.
    var folder: URL?
    var folderTitle: String
    var watermark: WatermarkStamp?
}

/// What came of an export, said in the toolbar.
enum MacExportNote: Equatable {
    /// Writing now: the toolbar offers Stop.
    case running(String)
    case written(URL)
    case skipped(String)
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Exports running now, for Activity › Background (FS-18.03 §4: progress is
/// in Activity, never modal).
@MainActor
@Observable
final class MacExportActivity {
    struct Run: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var detail: String
        /// The photo's file name, for the line a failure leaves.
        var name = ""
        /// Ended without a file: kept, so a failure on a photo the user has
        /// left (or an editor since closed) is still said somewhere.
        var failed = false
    }

    private(set) var runs: [Run] = []

    func begin(title: String, detail: String, name: String) -> UUID {
        // A new export: older failures have been seen or are moot.
        runs.removeAll(where: \.failed)
        let run = Run(title: title, detail: detail, name: name)
        runs.append(run)
        return run.id
    }

    func end(_ id: UUID, note: MacExportNote) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        if case .failed(let words) = note {
            runs[index].failed = true
            runs[index].title = String(localized: "Couldn't export \(runs[index].name)", comment: "Mac Activity › Background: an export failed")
            runs[index].detail = words
        } else {
            runs.remove(at: index)
        }
    }
}

// MARK: - Running

extension MacEditorModel {
    /// The names this export would write over (Replace asks first, FS-03.07b §6).
    func exportClashes(_ request: MacExportRequest) async -> Int {
        guard request.output == .files, request.policy == .replace, let folder = request.folder,
              let source = exportSource, let item = exportItem(request) else { return 0 }
        return await Task.detached(priority: .userInitiated) {
            let isAccessing = folder.startAccessingSecurityScopedResource()
            defer { if isAccessing { folder.stopAccessingSecurityScopedResource() } }
            return Self.plan(request, item: Self.dated(item, source: source), source: source, folder: folder).plan.replaceCount
        }.value
    }

    /// What the folder will do to this export's name, said before the click:
    /// Skip leaves it out; a name that is the original's own is numbered.
    func exportOutcome(_ request: MacExportRequest) async -> String? {
        guard request.output == .files, let folder = request.folder,
              let source = exportSource, let item = exportItem(request) else { return nil }
        return await Task.detached(priority: .utility) { () -> String? in
            let isAccessing = folder.startAccessingSecurityScopedResource()
            defer { if isAccessing { folder.stopAccessingSecurityScopedResource() } }
            let dated = Self.dated(item, source: source)
            let (plan, _, keepsOriginal) = Self.plan(request, item: dated, source: source, folder: folder)
            guard let entry = plan.entries.first else { return nil }
            let name = entry.outputs.first?.name ?? dated.filename
            if entry.isSkipped {
                return String(localized: "“\(name)” is already in the folder: Skip leaves this photo out.",
                              comment: "Mac export footer: If a File Exists is Skip and the name is taken")
            }
            if keepsOriginal {
                return String(localized: "Saved as “\(name)”: the original keeps its name.",
                              comment: "Mac export footer: numbered so the original is never replaced")
            }
            return nil
        }.value
    }

    /// Renders and writes the open photo, off the main actor and on the
    /// export's own renderer, so the editor's previews never queue behind it.
    /// The run outlives the sheet and a photo change; its result stays in the
    /// toolbar, and a failure in Activity too. Returns false when nothing started.
    @discardableResult
    func export(_ request: MacExportRequest, activity: MacExportActivity) -> Bool {
        guard !isExporting, let source = exportSource, let item = exportItem(request) else { return false }
        flushSave()
        isExporting = true
        exportNote = .running(item.filename)
        let recipe = request.version == .original ? PhotoEditRecipe.identity : recipe
        let renderer = exportRenderer
        let runId = activity.begin(
            title: request.output == .copy
                ? String(localized: "Saving a copy of \(item.filename)", comment: "Mac Activity › Background: Save as Copy is writing")
                : String(localized: "Exporting \(item.filename)", comment: "Mac Activity › Background: Export Files is writing"),
            detail: request.output == .copy
                ? String(localized: "Beside the original", comment: "Mac Activity › Background: where Save as Copy writes")
                : request.folderTitle,
            name: item.filename)
        exportTask = Task { [weak self] in
            // `write` is nonisolated: it runs off the main actor, and Stop
            // (this task's cancel) reaches its cancellation checks.
            let note = await Self.write(request, item: Self.dated(item, source: source), source: source, recipe: recipe, renderer: renderer)
            activity.end(runId, note: note)
            guard let self else { return }
            self.isExporting = false
            self.exportNote = note
        }
        return true
    }

    /// Stop in the toolbar: the part file is removed, nothing is written.
    func cancelExport() { exportTask?.cancel() }

    /// The open photo as the plan sees it. No file stat here: this runs on
    /// the main actor, and a slow mount must not hold it.
    private func exportItem(_ request: MacExportRequest) -> FileExportItem? {
        guard let source = exportSource else { return nil }
        let name = details.fileName.isEmpty ? source.url.lastPathComponent : details.fileName
        return FileExportItem(
            id: currentId, filename: name, captureDate: details.captureDate ?? .distantPast,
            camera: details.camera, lens: details.lens, kind: .photo,
            // The bytes are the file the editor reads: its own name and extension.
            files: [FileExportSourceFile(key: "photo", filename: source.url.lastPathComponent, role: .photo, isRAW: source.isRAW)],
            pixelWidth: source.pixelWidth, pixelHeight: source.pixelHeight)
    }

    /// A photo the index has no date for is dated by its file, never by today.
    nonisolated private static func dated(_ item: FileExportItem, source: PhotoRenderSourceInfo) -> FileExportItem {
        guard item.captureDate == .distantPast else { return item }
        let values = try? source.url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return FileExportItem(id: item.id, filename: item.filename,
                              captureDate: values?.creationDate ?? values?.contentModificationDate ?? Date(),
                              camera: item.camera, lens: item.lens, kind: item.kind, files: item.files,
                              pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight)
    }

    nonisolated private static func renderExtension(_ item: FileExportItem, _ request: MacExportRequest) -> String {
        KitExportRenderer.format(for: item, requested: request.format).fileExtension
    }

    /// The names, worked out against the folder as it is now. The original
    /// itself is never a name to replace: in its own folder a clash with it
    /// is always numbered (Keep Both), whatever the sheet says.
    nonisolated private static func plan(_ request: MacExportRequest, item: FileExportItem, source: PhotoRenderSourceInfo,
                                         folder: URL) -> (plan: FileExportPlan, directory: URL, keepsOriginal: Bool) {
        let sub = FileExportPlan.folder(for: item, dateFolders: request.dateFolders)
        let directory = sub.isEmpty ? folder : folder.appendingPathComponent(sub, isDirectory: true)
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        let renderExtension = renderExtension(item, request)
        func make(_ policy: FileExportConflictPolicy) -> FileExportPlan {
            FileExportPlan.make(items: [item], mode: request.mode, template: request.template, policy: policy,
                                dateFolders: request.dateFolders, includesLivePhotoVideo: false,
                                renderExtension: { _ in renderExtension }, existing: [sub: existing])
        }
        let original = source.url.lastPathComponent.lowercased()
        let isOriginalsFolder = sameItem(directory, source.url.deletingLastPathComponent())
        let plan = make(request.policy)
        if isOriginalsFolder, plan.entries.contains(where: { entry in entry.outputs.contains { $0.name.lowercased() == original } }) {
            return (make(.keepBoth), directory, true)
        }
        return (plan, directory, false)
    }

    nonisolated private static func write(_ request: MacExportRequest, item: FileExportItem, source: PhotoRenderSourceInfo,
                                          recipe: PhotoEditRecipe, renderer: PhotoRenderService) async -> MacExportNote {
        let manager = FileManager.default
        do {
            switch request.output {
            case .copy:
                let folder = source.url.deletingLastPathComponent()
                let existing = Set((try? manager.contentsOfDirectory(atPath: folder.path)) ?? [])
                let fileExtension = OutputNaming.copyExtension(of: item.filename, format: request.format,
                                                               encodesHEIC: KitExportRenderer.supportsHEICEncoding)
                let name = OutputNaming.editedCopy(of: item.filename, fileExtension: fileExtension, existing: existing)
                let target = folder.appendingPathComponent(name)
                try await place(target, replacing: false, original: source.url) { part in
                    try await render(request, source: source, recipe: recipe, renderer: renderer,
                                     format: fileExtension == "heic" ? .heic : .jpeg, to: part)
                }
                return .written(target)
            case .files:
                guard let folder = request.folder else {
                    return .failed(String(localized: "Choose a folder to export to.", comment: "Mac export: no folder"))
                }
                let isAccessing = folder.startAccessingSecurityScopedResource()
                defer { if isAccessing { folder.stopAccessingSecurityScopedResource() } }
                let (plan, directory, _) = plan(request, item: item, source: source, folder: folder)
                guard let entry = plan.entries.first else { return .failed(cantWrite) }
                if entry.isSkipped {
                    return .skipped(String(localized: "Skipped — \(item.filename) is already in the folder.",
                                           comment: "Mac export: If a File Exists is Skip and the name is taken"))
                }
                let renderExtension = renderExtension(item, request)
                var last: URL?
                for output in entry.outputs {
                    let target = directory.appendingPathComponent(output.name)
                    try await place(target, replacing: output.replaces, original: source.url) { part in
                        if output.source != nil {
                            // Unmodified Original: the bytes as they are.
                            try manager.copyItem(at: source.url, to: part)
                        } else {
                            try await render(request, source: source, recipe: recipe, renderer: renderer,
                                             format: renderExtension == "heic" ? .heic : .jpeg, to: part)
                        }
                    }
                    last = target
                }
                return last.map(MacExportNote.written) ?? .failed(cantWrite)
            }
        } catch is CancellationError {
            return .skipped(String(localized: "Stopped — nothing was written.", comment: "Mac export: Stop was clicked"))
        } catch {
            return .failed(failure(error, output: request.output))
        }
    }

    nonisolated private static var cantWrite: String {
        String(localized: "ShotDex couldn't write the file. Check the folder and try again.", comment: "Mac export: the write failed")
    }

    /// What went wrong, in words that say what to do.
    nonisolated private static func failure(_ error: Error, output: MacExportOutput) -> String {
        if error is WouldTouchOriginal {
            return String(localized: "Not written: that name is the original photo. Pick another name or folder.",
                          comment: "Mac export: the export would have written over the original")
        }
        if error is PhotoEditingError {
            return String(localized: "ShotDex couldn't render this photo. Undo the last change or try another format.",
                          comment: "Mac export: the render or encode failed")
        }
        switch (error as? CocoaError)?.code {
        case .fileWriteOutOfSpace?:
            return String(localized: "The disk is full. Free some space or choose another folder.", comment: "Mac export: no space")
        case .fileWriteNoPermission?, .fileWriteVolumeReadOnly?:
            return output == .copy
                ? String(localized: "The original's folder is read-only. Use Export Files to write somewhere else.",
                         comment: "Mac export: Save as Copy cannot write beside the original")
                : String(localized: "This folder is read-only. Choose another folder.", comment: "Mac export: no permission")
        case .fileNoSuchFile?, .fileWriteUnknown?:
            return output == .copy
                ? String(localized: "The original's folder isn't reachable. Connect its drive and try again.",
                         comment: "Mac export: Save as Copy, the drive went away")
                : String(localized: "The folder isn't reachable. Connect its drive or choose another folder.",
                         comment: "Mac export: the destination went away")
        default:
            return cantWrite
        }
    }

    /// One file or folder, however it is reached — a symlink, a second mount
    /// path — by its file-system identity; by path when that is unreadable.
    nonisolated static func sameItem(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let left = try? a.resourceValues(forKeys: key).fileResourceIdentifier,
           let right = try? b.resourceValues(forKeys: key).fileResourceIdentifier {
            return left.isEqual(right)
        }
        return a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    fileprivate struct WouldTouchOriginal: Error {}

    /// Written under a hidden part name of its own and moved into place, so a
    /// failure never leaves half a file under the real name. Replace swaps
    /// the new file in whole (`replaceItemAt`): the old one goes only once
    /// the new one is there (FS-03.07b §6). The original is never a target.
    nonisolated private static func place(_ target: URL, replacing: Bool, original: URL,
                                          write: (URL) async throws -> Void) async throws {
        let manager = FileManager.default
        guard !sameItem(target, original) else { throw WouldTouchOriginal() }
        // Date Folders: made only now, so a skip or a failed render leaves no empty folder.
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let part = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString.prefix(8)).shotdex-part")
        do {
            try await write(part)
            try Task.checkCancellation()
            if replacing, manager.fileExists(atPath: target.path) {
                _ = try manager.replaceItemAt(target, withItemAt: part)
            } else {
                try manager.moveItem(at: part, to: target)
            }
        } catch {
            try? manager.removeItem(at: part)
            throw error
        }
    }

    /// The edit, then the size, the stamp and the Color Space — last, so the
    /// stamp is drawn in the profile written (FS-03.07b §3a).
    nonisolated private static func render(_ request: MacExportRequest, source: PhotoRenderSourceInfo, recipe: PhotoEditRecipe,
                                           renderer: PhotoRenderService, format: PhotoOutputFormat, to url: URL) async throws {
        var result = try await renderer.render(source: source, recipe: recipe)
        if request.preset.kind != .original {
            result = await renderer.resize(result, preset: request.preset, cropAnchor: .center)
        }
        result.watermark = request.watermark
        if let space = request.colorSpace.cgColorSpace { result = result.converted(to: space) }
        try Task.checkCancellation()
        try await renderer.write(result, to: url, format: format, quality: request.quality, metadata: request.metadata)
    }

    /// The pixel size a choice writes: the cropped photo at the preset.
    func exportPixelSize(_ preset: ResizePreset) -> CGSize? {
        guard let source = exportSource else { return nil }
        var width = Double(source.pixelWidth), height = Double(source.pixelHeight)
        switch source.orientation {
        case .left, .leftMirrored, .right, .rightMirrored: swap(&width, &height)
        default: break
        }
        width *= recipe.crop.rect.width
        height *= recipe.crop.rect.height
        guard width >= 1, height >= 1 else { return nil }
        let target = preset.targetPixelSize(sourceWidth: Int(width.rounded()), sourceHeight: Int(height.rounded()))
        return target.width > 0 && target.height > 0 ? target : CGSize(width: width.rounded(), height: height.rounded())
    }

    /// About how many bytes the file will be.
    func estimatedExportBytes(_ request: MacExportRequest) async -> Int64? {
        guard let source = exportSource else { return nil }
        if request.output == .files, request.mode == .unmodifiedOriginal {
            let url = source.url
            return await Task.detached(priority: .utility) {
                (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            }.value
        }
        let options = PhotoExportOptions(format: request.format == .preserve ? .jpeg : request.format, quality: request.quality,
                                         preset: request.preset, metadata: request.metadata, cropAnchor: .center)
        let recipe = request.version == .original ? PhotoEditRecipe.identity : recipe
        return (try? await exportRenderer.estimatedEncodedByteCount(source: source, recipe: recipe, options: options)).map(Int64.init)
    }

    /// The words a watermark's tokens are filled with for this photo.
    var exportTokenValues: OverlayTokenValues {
        let date = details.captureDate.map { $0.formatted(date: .abbreviated, time: .omitted) }
        return OverlayTokenValues(
            camera: details.camera, lens: details.lens,
            focal: details.focalLength.map { "\(Int($0.rounded())) mm" },
            aperture: details.aperture.map { "f/\($0.formatted(.number.precision(.fractionLength(0...1))))" },
            shutter: details.shutter.map { "\($0) s" },
            iso: details.iso.map { "ISO \($0)" },
            date: date,
            filename: details.fileName)
    }

    /// The photo the editor shows, for the watermark card.
    var exportPreview: CGImage? { preview }
}

// MARK: - Sheet

/// "Save and Export" (board `MAC_Export`, FS-18.03 §4): one sheet of
/// 640×560 over the editor, its body scrolling. Opened by Export in the
/// toolbar and ⇧⌘E.
struct MacEditorExportSheet: View {
    @Bindable var model: MacEditorModel
    @Binding var isPresented: Bool
    @Environment(MacDependencies.self) private var dependencies

    @State private var choices = MacExportChoices.remembered()
    @State private var metadata = MetadataLevel.sharingDefault()
    @State private var version = FileExportVersion.edited
    @State private var presets = MacExportPreset.all()
    @State private var folders = ExportFolderStore()
    @State private var signatures = SignaturePresetStore()
    @State private var sizes = CompressionPresetStore()
    @State private var folderState: ExportFolderState?
    @State private var freeLine: String?
    @State private var estimate: Int64?
    @State private var watermarkPreview: CGImage?
    @State private var asksPresetName = false
    @State private var presetName = ""
    @State private var editsWatermark = false
    @State private var asksReplace = false
    @State private var choosesFolder = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var resolveTask: Task<Void, Never>?
    /// What Export will do with the name, read from the folder: Skip, or a
    /// number added so the original is never replaced.
    @State private var outcomeLine: String?
    /// Export was clicked: a second click before the sheet goes starts nothing.
    @State private var isStarting = false
    @State private var folderNote: String?
    @State private var pendingRequest: MacExportRequest?
    /// The choices as the sheet opened (defaults or remembered, plus repairs).
    @State private var openedWith: MacExportChoices?

    /// Two columns in 640 less the 24pt margins and the 20pt gutter, as the
    /// board splits them: Destination and Photo 320, File Name and Watermark 252.
    private static let leftWidth: CGFloat = 320
    private static let rightWidth: CGFloat = 252
    /// Row labels: 100 on the left (the environment's default), 72 on the narrower right.
    private static let rightLabel: CGFloat = 72
    /// A popup's width in a row; narrower when a note follows it.
    private static let popupWidth: CGFloat = 150
    private static let shortPopupWidth: CGFloat = 96

    private var settings: FileExportSettings { choices.files }
    private var isCopy: Bool { choices.output == .copy }
    private var rendersPhoto: Bool { isCopy || settings.mode == .currentVersion }
    private var sizePreset: ResizePreset { sizes.allPresets.first { $0.id == settings.presetId } ?? .original }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.horizontal, .top], 24)
                .padding(.bottom, 14)
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        if isCopy { besideOriginal } else { destination }
                        photo
                    }
                    .frame(width: Self.leftWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 18) {
                        if !isCopy { fileName }
                        watermark
                    }
                    .frame(width: Self.rightWidth, alignment: .leading)
                    .environment(\.macExportLabelWidth, Self.rightLabel)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 640, height: 560)
        .preferredColorScheme(.dark)
        .tint(MacTheme.Editor.label)
        .onAppear(perform: appear)
        .onChange(of: choices) { _, new in
            // What the sheet opened with is not a choice: Settings › Export
            // Defaults keep applying until the user changes something here.
            if new != openedWith || UserDefaults.standard.data(forKey: MacExportChoices.key) != nil { new.remember() }
            refresh()
        }
        // Settings › Editing (another window) changed the presets: read them again.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            signatures.reload()
            sizes.reload()
        }
        .onChange(of: metadata) { _, _ in refresh() }
        .onChange(of: version) { _, _ in refresh() }
        // Edit… rewrote the text of the preset in use: the card and Export follow.
        .onChange(of: signatures.presets) { _, _ in refresh() }
        .onDisappear {
            refreshTask?.cancel()
            resolveTask?.cancel()
        }
        .alert(String(localized: "Save Preset", comment: "Mac export: name a preset"), isPresented: $asksPresetName) {
            TextField(String(localized: "Name", comment: "Mac export: preset name field"), text: $presetName)
            Button(presetExists ? String(localized: "Replace", comment: "Mac export: overwrite the preset of that name")
                                : String(localized: "Save", comment: "Mac export: save the preset")) { savePreset() }
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(String(localized: "Cancel", comment: "Mac export"), role: .cancel) {}
        } message: {
            Text(presetExists
                 ? String(localized: "A preset named “\(presetName.trimmingCharacters(in: .whitespaces))” exists. Replace it with these choices?",
                          comment: "Mac export: Save Preset, the name is taken")
                 : String(localized: "Saves these choices under a name, to pick from Preset next time. Metadata always starts at your Settings level.",
                          comment: "Mac export: what Save Preset keeps"))
        }
        .confirmationDialog(ExportCopy.replaceTitle(1, folder: folderTitle), isPresented: $asksReplace) {
            Button(ExportCopy.replace, role: .destructive) { if let pendingRequest { run(pendingRequest) } }
            Button(String(localized: "Cancel", comment: "Mac export"), role: .cancel) {}
        }
        .fileImporter(isPresented: $choosesFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            Task {
                // Bookmark and volume name read off the main actor: a slow drive must not hold the sheet.
                let picked = await Task.detached(priority: .userInitiated) { () -> ExportFolder? in
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
                    return try? ExportFolderStore.folder(for: url)
                }.value
                if let picked {
                    folders.remember(picked)
                    folderNote = nil
                } else {
                    folderNote = ExportCopy.folderGone
                }
                resolveFolder()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save and Export", comment: "Mac export sheet title").font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Text("Preset", comment: "Mac export: the preset popup's label").font(.system(size: 12)).foregroundStyle(.secondary)
                Picker(String(localized: "Preset", comment: "Mac export: the preset popup's label"), selection: Binding(
                    get: { presets.first { $0.choices == choices }?.id },
                    set: { id in if let preset = presets.first(where: { $0.id == id }) { choices = preset.choices } })) {
                    if !presets.contains(where: { $0.choices == choices }) {
                        Text("Custom", comment: "Mac export: choices that match no preset").tag(UUID?.none)
                    }
                    ForEach(presets) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
                .frame(width: 150)
                .accessibilityIdentifier("export.preset")
            }
            HStack(alignment: .top, spacing: 16) {
                MacEditorSegments(options: MacExportOutput.allCases, selection: $choices.output, id: "export.output") {
                    switch $0 {
                    case .copy: String(localized: "Save as Copy", comment: "Mac export: write a copy beside the original")
                    case .files: String(localized: "Export Files", comment: "Mac export: write files to a folder")
                    }
                }
                .frame(width: 236)
                Text(isCopy
                     ? String(localized: "Edits already save on their own. Save as Copy adds \(copyName) beside the photo; ShotDex never edits the original.",
                              comment: "Mac export: what Save as Copy does")
                     : String(localized: "Edits already save on their own. Export Files writes to the folder you choose; ShotDex never edits the original.",
                              comment: "Mac export: what Export Files does"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "DSCF4127.RAF · Fujifilm X-T5 · in “2026 Japan”".
    private var subtitle: String {
        var parts = [model.details.fileName]
        if let camera = model.details.camera { parts.append(camera) }
        if let source = model.details.sourceName {
            parts.append(String(localized: "in “\(source)”", comment: "Mac export subtitle: the source the photo is in"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// `DSCF4127 (edited).jpg`.
    private var copyName: String {
        let name = model.details.fileName
        let ext = OutputNaming.copyExtension(of: name, format: settings.format, encodesHEIC: KitExportRenderer.supportsHEICEncoding)
        return "\((name as NSString).deletingPathExtension) (edited).\(ext)"
    }

    // MARK: Destination

    private var besideOriginal: some View {
        section(String(localized: "Destination", comment: "Mac export section")) {
            row(String(localized: "Save To", comment: "Mac export row")) {
                Text("Beside the original", comment: "Mac export: Save as Copy writes next to the photo").font(.system(size: 12))
            }
        }
    }

    private var destination: some View {
        section(ExportCopy.destination) {
            row(String(localized: "Save To", comment: "Mac export row")) {
                Picker(String(localized: "Save To", comment: "Mac export row"), selection: Binding(
                    get: { folders.current?.id },
                    set: { id in
                        if let folder = folders.recents.first(where: { $0.id == id }) { folders.use(folder); resolveFolder() }
                    })) {
                    if folders.recents.isEmpty { Text(ExportCopy.noFolder).tag(UUID?.none) }
                    ForEach(folders.recents) { Text($0.title).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
                .accessibilityIdentifier("export.saveTo")
            }
            rowDivider
            row(ExportCopy.folder) {
                HStack(spacing: 8) {
                    Image(systemName: folders.current?.isOnExternalDrive == true ? "externaldrive" : "folder")
                        .foregroundStyle(MacTheme.Editor.accent)
                    Text(folderLine).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(folderState == .notConnected ? .secondary : .primary)
                    Spacer(minLength: 4)
                    Button(String(localized: "Choose…", comment: "Mac export: pick the folder")) { choosesFolder = true }
                        .accessibilityIdentifier("export.chooseFolder")
                }
            }
            if let folderNote {
                Text(folderNote).font(.system(size: 11)).foregroundStyle(MacTheme.redText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
            rowDivider
            row("") {
                HStack(spacing: 8) {
                    Toggle(ExportCopy.dateFolders, isOn: $choices.files.dateFolders)
                        .toggleStyle(.checkbox).tint(MacTheme.Editor.accent)
                        .accessibilityIdentifier("export.dateFolders")
                    if settings.dateFolders {
                        Text(dateFolderExample).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            rowDivider
            row(ExportCopy.ifFileExists) {
                Picker(ExportCopy.ifFileExists, selection: $choices.files.conflictPolicy) {
                    ForEach(FileExportConflictPolicy.allCases, id: \.self) { Text(ExportCopy.policy($0)).tag($0) }
                }
                .labelsHidden().frame(width: Self.popupWidth, alignment: .leading)
                .accessibilityIdentifier("export.ifExists")
            }
        }
    }

    private var folderTitle: String { folders.current?.name ?? ExportCopy.noFolder }

    private var folderLine: String {
        guard let folder = folders.current else { return ExportCopy.noFolder }
        return folderState == .notConnected ? "\(folder.name) — \(ExportCopy.notConnected)" : folder.name
    }

    /// `2026/2026-09-28`.
    private var dateFolderExample: String {
        let date = model.details.captureDate ?? Date()
        return "\(FileNameTemplate.format(date, "yyyy", .current))/\(FileNameTemplate.format(date, "yyyy-MM-dd", .current))"
    }

    // MARK: Photo

    private var photo: some View {
        section(String(localized: "Photo", comment: "Mac export section")) {
            if !isCopy {
                row(ExportCopy.exportAs) {
                    Picker(ExportCopy.exportAs, selection: $choices.files.mode) {
                        ForEach(FileExportMode.allCases, id: \.self) { Text(ExportCopy.mode($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: Self.popupWidth, alignment: .leading)
                    .accessibilityIdentifier("export.exportAs")
                }
                if rendersPhoto { rowDivider }
            }
            if rendersPhoto {
                // Save as Copy is the edit, by name: `(edited)`. Version is Export Files' choice.
                if !isCopy {
                    row(ExportCopy.version) {
                        Picker(ExportCopy.version, selection: $version) {
                            ForEach(FileExportVersion.allCases, id: \.self) { Text(ExportCopy.version($0)).tag($0) }
                        }
                        .labelsHidden().frame(width: Self.popupWidth, alignment: .leading)
                        .accessibilityIdentifier("export.version")
                    }
                    rowDivider
                }
                row(ExportCopy.size) {
                    HStack(spacing: 8) {
                        Picker(ExportCopy.size, selection: Binding(
                            get: { sizePreset.id },
                            set: { id in
                                choices.files.presetId = id
                                // A preset of the user's carries its own quality (FS-03.07b §3a).
                                if let preset = sizes.customPresets.first(where: { $0.id == id }) {
                                    choices.files.quality = FileExportQuality.clamped(preset.quality)
                                }
                            })) {
                            ForEach(sizes.allPresets) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden().frame(width: Self.shortPopupWidth, alignment: .leading)
                        .accessibilityIdentifier("export.size")
                        if sizePreset.kind == .longEdge {
                            Text("long edge", comment: "Mac export: the size is the long edge").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                rowDivider
                row(ExportCopy.format) {
                    Picker(ExportCopy.format, selection: $choices.files.format) {
                        ForEach([PhotoOutputFormat.preserve, .jpeg, .heic], id: \.self) { Text(ExportCopy.formatName($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: Self.popupWidth, alignment: .leading)
                    .accessibilityIdentifier("export.format")
                }
                rowDivider
                row(ExportCopy.colorSpace) {
                    HStack(spacing: 8) {
                        Picker(ExportCopy.colorSpace, selection: $choices.files.colorSpace) {
                            ForEach(ExportColorSpace.allCases, id: \.self) { Text(ExportCopy.colorSpaceName($0)).tag($0) }
                        }
                        .labelsHidden().frame(width: Self.shortPopupWidth, alignment: .leading)
                        .accessibilityIdentifier("export.colorSpace")
                        if settings.colorSpace == .original {
                            Text("keeps the photo’s profile", comment: "Mac export: what Color Space Original does")
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                rowDivider
                row(ExportCopy.quality) {
                    HStack(spacing: 8) {
                        Slider(value: $choices.files.quality, in: FileExportQuality.range, step: FileExportQuality.step)
                            .controlSize(.small)
                            .accessibilityIdentifier("export.quality")
                        Text(ExportCopy.qualityText(settings.quality))
                            .font(.system(size: 12)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                rowDivider
                row(ExportCopy.metadata) {
                    Picker(ExportCopy.metadata, selection: $metadata) {
                        Text("All Metadata", comment: "Mac export: metadata level").tag(MetadataLevel.all)
                        Text("All Except Location", comment: "Mac export: metadata level without GPS").tag(MetadataLevel.noLocation)
                        Text("No Metadata", comment: "Mac export: metadata level").tag(MetadataLevel.noMetadata)
                    }
                    .labelsHidden().frame(width: Self.popupWidth, alignment: .leading)
                    .accessibilityIdentifier("export.metadata")
                }
            } else {
                Text(ExportCopy.originalsAsTheyAre)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
            }
        }
    }

    // MARK: File Name

    private var fileName: some View {
        section(String(localized: "File Name", comment: "Mac export section")) {
            row(ExportCopy.name) {
                Picker(ExportCopy.name, selection: Binding(
                    get: { FileNameTemplate.builtIns.contains(FileNameTemplate(settings.nameTemplate)) ? settings.nameTemplate : "" },
                    set: { pattern in
                        choices.files.nameTemplate = pattern.isEmpty ? settings.customNameTemplate : pattern
                    })) {
                    ForEach(FileNameTemplate.builtIns, id: \.self) { Text(ExportCopy.templateTitle($0)).tag($0.pattern) }
                    Text(ExportCopy.custom).tag("")
                }
                .labelsHidden().frame(width: Self.popupWidth, alignment: .leading)
                .accessibilityIdentifier("export.name")
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField(String(localized: "Name", comment: "Mac export: the file name template field"), text: Binding(
                    get: { settings.nameTemplate },
                    set: { typed in
                        choices.files.nameTemplate = typed
                        if !FileNameTemplate.builtIns.contains(FileNameTemplate(typed)) { choices.files.customNameTemplate = typed }
                    }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .accessibilityIdentifier("export.nameField")
                MacExportChipFlow(spacing: 6) {
                    ForEach(FileNameChip.all, id: \.self) { chip in
                        Button(ExportCopy.chipTitle(chip)) {
                            let appended = chip.appended(to: settings.nameTemplate).pattern
                            choices.files.nameTemplate = appended
                            if !FileNameTemplate.builtIns.contains(FileNameTemplate(appended)) { choices.files.customNameTemplate = appended }
                        }
                        .buttonStyle(MacExportChipStyle())
                        .accessibilityLabel(ExportCopy.insertChip(chip))
                        .accessibilityIdentifier("export.chip.\(ExportCopy.chipTitle(chip))")
                    }
                }
                HStack(spacing: 4) {
                    Text("Example:", comment: "Mac export: the first file's name follows").foregroundStyle(.secondary)
                    Text(exampleName).lineLimit(1).truncationMode(.middle)
                }
                .font(.system(size: 12))
                .accessibilityElement(children: .combine)
            }
            .padding(10)
        }
    }

    private var exampleName: String {
        let values = FileNameValues(original: (model.details.fileName as NSString).deletingPathExtension,
                                    captureDate: model.details.captureDate ?? Date(),
                                    camera: model.details.camera, lens: model.details.lens)
        let base = FileNameTemplate(settings.nameTemplate).baseName(for: values, sequence: 1, sequenceWidth: 3)
        let ext = rendersPhoto
            ? OutputNaming.copyExtension(of: model.details.fileName, format: settings.format, encodesHEIC: KitExportRenderer.supportsHEICEncoding)
            : (model.details.fileName as NSString).pathExtension
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    // MARK: Watermark

    private var watermark: some View {
        section(String(localized: "Watermark", comment: "Mac export section")) {
            row("") {
                HStack {
                    Toggle(String(localized: "Add Watermark", comment: "Mac export: stamp the watermark"), isOn: $choices.watermark.isEnabled)
                        .toggleStyle(.checkbox).tint(MacTheme.Editor.accent)
                        .disabled(!rendersPhoto)
                        .accessibilityIdentifier("export.addWatermark")
                    Spacer(minLength: 4)
                    Button(String(localized: "Edit…", comment: "Mac export: edit the watermark's text")) { editsWatermark = true }
                        .accessibilityIdentifier("export.editWatermark")
                        .popover(isPresented: $editsWatermark, arrowEdge: .trailing) {
                            MacExportWatermarkEditor(store: signatures, presetID: $choices.watermark.presetID,
                                                     isEnabled: $choices.watermark.isEnabled, isPresented: $editsWatermark)
                        }
                }
            }
            if choices.watermark.isEnabled && rendersPhoto {
                rowDivider
                row(String(localized: "Text", comment: "Mac export: which watermark")) {
                    Picker(String(localized: "Text", comment: "Mac export: which watermark"), selection: $choices.watermark.presetID) {
                        if signatures.presets.isEmpty {
                            Text("None — Edit… to write one", comment: "Mac export: no watermark saved yet").tag(UUID?.none)
                        }
                        ForEach(signatures.presets) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .frame(width: Self.popupWidth, alignment: .leading)
                    .accessibilityIdentifier("export.watermarkText")
                }
                rowDivider
                row(String(localized: "Placement", comment: "Mac export: where the watermark goes")) {
                    Picker(String(localized: "Placement", comment: "Mac export: where the watermark goes"),
                           selection: $choices.watermark.placement.anchor) {
                        ForEach(WatermarkAnchor.allCases) { Text(MacExportWords.anchor($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: Self.popupWidth, alignment: .leading)
                    .accessibilityIdentifier("export.placement")
                }
                rowDivider
                row(String(localized: "Size", comment: "Mac export: the watermark's size")) {
                    HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { choices.watermark.placement.size ?? naturalSize },
                            set: { choices.watermark.placement.size = $0 }),
                               in: WatermarkPlacement.sizeRange, step: WatermarkPlacement.sizeStep)
                            .controlSize(.small)
                            .accessibilityIdentifier("export.watermarkSize")
                        Text((choices.watermark.placement.size ?? naturalSize).formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 12)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                rowDivider
                row(String(localized: "Opacity", comment: "Mac export: the watermark's opacity")) {
                    HStack(spacing: 8) {
                        Slider(value: $choices.watermark.placement.opacity, in: WatermarkPlacement.opacityRange,
                               step: WatermarkPlacement.opacityStep)
                            .controlSize(.small)
                            .accessibilityIdentifier("export.watermarkOpacity")
                        Text(choices.watermark.placement.opacity.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 12)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            }
            if rendersPhoto {
                rowDivider
                previewCard
            }
        }
    }

    private var naturalSize: Double {
        stampTemplate.flatMap(PhotoRenderService.watermarkNaturalSize) ?? 0.04
    }

    /// The photo with the stamp where it will land, and what the file will be.
    private var previewCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let watermarkPreview {
                    Image(decorative: watermarkPreview, scale: 1).resizable().scaledToFit()
                } else {
                    Rectangle().fill(MacTheme.Editor.fill)
                }
            }
            .frame(width: 96, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.Editor.thumbnailRadius))
            .accessibilityHidden(true)
            Text(fileLine).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .accessibilityIdentifier("export.previewCard")
    }

    /// "2048 × 1365 px · JPEG 80% · about 1.1 MB".
    private var fileLine: String {
        var parts: [String] = []
        if let size = model.exportPixelSize(sizePreset) {
            parts.append("\(Int(size.width).formatted()) × \(Int(size.height).formatted()) px")
        }
        let format = KitExportRenderer.format(for: FileExportItem(id: "", filename: model.details.fileName, captureDate: Date(),
                                                                  kind: .photo, files: []), requested: settings.format)
        parts.append("\(format == .heic ? "HEIC" : "JPEG") \(ExportCopy.qualityText(settings.quality))")
        if let estimate {
            parts.append(String(localized: "about \(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file))",
                                comment: "Mac export: the file's estimated size"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button(String(localized: "Save Preset…", comment: "Mac export: keep these choices under a name")) {
                presetName = ""
                asksPresetName = true
            }
            .accessibilityIdentifier("export.savePreset")
            VStack(alignment: .leading, spacing: 1) {
                Text(summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let line = disabledReason ?? outcomeLine {
                    Text(line).foregroundStyle(disabledReason != nil ? MacTheme.redText : .secondary).lineLimit(2)
                        .accessibilityIdentifier("export.reason")
                }
            }
            .font(.system(size: 11))
            Spacer(minLength: 8)
            Button(String(localized: "Cancel", comment: "Mac export")) { isPresented = false }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("export.cancel")
            Button {
                Task { await confirmAndRun() }
            } label: {
                Text(isCopy ? String(localized: "Save Copy", comment: "Mac export: the commit button for Save as Copy")
                            : String(localized: "Export", comment: "Mac export: the commit button"))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(MacPushButtonStyle(isDefault: true, defaultWeight: .medium))
            .disabled(!canExport || isStarting || model.isExporting)
            .accessibilityIdentifier("export.go")
        }
    }

    /// "1 photo · about 1.1 MB · 412 GB free on “T7”".
    private var summary: String {
        var parts = [String(localized: "1 photo", comment: "Mac export footer: one photo")]
        if let estimate {
            parts.append(String(localized: "about \(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file))",
                                comment: "Mac export: the file's estimated size"))
        }
        if !isCopy, folderState == .notConnected, let folder = folders.current {
            parts.append(ExportCopy.connectDrive(folder.place))
        } else if let freeLine {
            parts.append(freeLine)
        }
        return parts.joined(separator: " · ")
    }

    private var canExport: Bool { disabledReason == nil }

    /// Why Export is off, said in the footer instead of a silent grey button.
    private var disabledReason: String? {
        if model.isExporting {
            return String(localized: "Still saving the last export — Export is back when it finishes.",
                          comment: "Mac export footer: an export of this editor is running")
        }
        guard model.load == .ready else { return String(localized: "The photo is still opening.", comment: "Mac export footer") }
        if choices.watermark.isEnabled && rendersPhoto && request.watermark == nil {
            return stampTemplate == nil
                ? String(localized: "Write the watermark with Edit…, or turn it off.", comment: "Mac export footer: no watermark text")
                : String(localized: "The watermark has no words for this photo.", comment: "Mac export footer: every token empty")
        }
        if isCopy { return nil }
        if folders.current == nil { return String(localized: "Choose a folder.", comment: "Mac export footer: no folder yet") }
        switch folderState {
        case .available: break
        case .notConnected?: return ExportCopy.connectDrive(folders.current?.place ?? "")
        case .gone?: return ExportCopy.folderGone
        case nil: return String(localized: "Opening the folder…", comment: "Mac export footer: the folder is being checked")
        }
        if settings.nameTemplate.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "Enter a file name.", comment: "Mac export footer: the name template is empty")
        }
        return nil
    }

    // MARK: Work

    private var stampTemplate: WatermarkStamp? {
        guard let id = choices.watermark.presetID, let preset = signatures.presets.first(where: { $0.id == id }) else { return nil }
        return WatermarkStamp(preset: preset, placement: choices.watermark.placement)
    }

    private var request: MacExportRequest {
        var folderURL: URL?
        if case .available(let url) = folderState { folderURL = url }
        let stamp = choices.watermark.isEnabled && rendersPhoto ? stampTemplate.flatMap { template -> WatermarkStamp? in
            guard case .stamp(let stamp) = WatermarkPlan.decide(template, values: model.exportTokenValues) else { return nil }
            return stamp
        } : nil
        return MacExportRequest(
            output: choices.output, mode: isCopy ? .currentVersion : settings.mode, version: isCopy ? .edited : version,
            preset: sizePreset, format: settings.format, quality: settings.quality, colorSpace: settings.colorSpace,
            metadata: metadata, template: FileNameTemplate(settings.nameTemplate), policy: settings.conflictPolicy,
            dateFolders: settings.dateFolders, folder: folderURL, folderTitle: folders.current?.title ?? "",
            watermark: stamp)
    }

    private func appear() {
        #if DEBUG
        // `-ShotDexExportTest`: a folder in the app's temporary directory, so a
        // click-test exports without the system folder picker.
        if ProcessInfo.processInfo.arguments.contains("-ShotDexExportTest") {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexExportTest", isDirectory: true)
            // Each run starts the same: an empty folder, nothing remembered.
            if !MacExportWords.testWasReset {
                MacExportWords.testWasReset = true
                try? FileManager.default.removeItem(at: folder)
                UserDefaults.standard.removeObject(forKey: MacExportChoices.key)
                UserDefaults.standard.removeObject(forKey: MacExportPreset.key)
                UserDefaults.standard.removeObject(forKey: MacExportChoices.defaultsKey)
                choices = MacExportChoices()
                presets = []
            }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try? folders.remember(folder)
        }
        #endif
        // No watermark picked, or the one picked was deleted: the first there is.
        if !signatures.presets.contains(where: { $0.id == choices.watermark.presetID }) {
            choices.watermark.presetID = signatures.presets.first?.id
        }
        openedWith = choices
        resolveFolder()
        refresh()
    }

    /// The folder's bookmark opened off the main actor: a pulled drive or a
    /// sleeping share may take seconds to say no.
    private func resolveFolder() {
        guard let folder = folders.current else { folderState = nil; refresh(); return }
        folderState = nil
        resolveTask?.cancel()
        resolveTask = Task {
            let opened = await Task.detached(priority: .userInitiated) { ExportFolderStore.open(folder) }.value
            guard !Task.isCancelled, folders.current?.id == folder.id else { return }
            folderState = folders.apply(folder, url: opened.url, isStale: opened.isStale)
            refresh()
        }
    }

    /// The size estimate, the free space and the watermark card, off the main actor.
    private func refresh() {
        refreshTask?.cancel()
        let request = request
        let isCopy = isCopy
        let place = isCopy ? model.exportSource?.url.deletingLastPathComponent() : request.folder
        let stamp = request.watermark
        let preview = model.exportPreview
        refreshTask = Task {
            // A slider drag or a typed name sends many changes: only the last is measured.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let bytes = await model.estimatedExportBytes(request)
            guard !Task.isCancelled else { return }
            estimate = bytes
            let free = await Task.detached(priority: .utility) { () -> String? in
                guard let place else { return nil }
                let isAccessing = place.startAccessingSecurityScopedResource()
                defer { if isAccessing { place.stopAccessingSecurityScopedResource() } }
                guard let values = try? place.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeNameKey]),
                      let free = values.volumeAvailableCapacityForImportantUsage, free > 0 else { return nil }
                return ExportCopy.freeOn(free, place: values.volumeName ?? place.lastPathComponent)
            }.value
            guard !Task.isCancelled else { return }
            freeLine = free
            let outcome = await model.exportOutcome(request)
            guard !Task.isCancelled else { return }
            outcomeLine = outcome
            let card = await Task.detached(priority: .utility) { MacExportWords.card(preview, stamp: stamp) }.value
            guard !Task.isCancelled else { return }
            watermarkPreview = card
        }
    }

    private var presetExists: Bool {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && presets.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let index = presets.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            presets[index].choices = choices
        } else {
            presets.append(MacExportPreset(name: name, choices: choices))
        }
        MacExportPreset.save(presets)
    }

    /// The request is fixed at the click: the Replace question and the run
    /// are about the same choices, whatever changes in between.
    private func confirmAndRun() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let request = request
        if await model.exportClashes(request) > 0 {
            pendingRequest = request
            asksReplace = true
        } else {
            run(request)
        }
    }

    private func run(_ request: MacExportRequest) {
        refreshTask?.cancel()
        // Closes only when the export started.
        if model.export(request, activity: dependencies.exports) { isPresented = false }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { content() }
                .background(MacTheme.Editor.cardFill, in: RoundedRectangle(cornerRadius: MacTheme.Editor.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.cardRadius).strokeBorder(MacTheme.Editor.hairline))
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        MacExportRow(title: title, content: content())
    }

    private var rowDivider: some View { Divider().padding(.leading, 10) }
}

/// The watermark's words, written here (Mac has no signature editor yet):
/// one text layer, its name the text itself.
private struct MacExportWatermarkEditor: View {
    let store: SignaturePresetStore
    @Binding var presetID: UUID?
    /// Saving words turns the stamp on: that is why they were written.
    @Binding var isEnabled: Bool
    @Binding var isPresented: Bool
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Watermark Text", comment: "Mac export: the watermark editor's title").font(.system(size: 13, weight: .semibold))
            TextField(String(localized: "© 2026 Your Name", comment: "Mac export: watermark text placeholder"), text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .accessibilityIdentifier("export.watermarkField")
                .onSubmit(save)
            Text("Tokens like {camera} or {date} are filled in for each photo.", comment: "Mac export: the watermark text takes tokens")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(String(localized: "Save", comment: "Mac export: keep the watermark text"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("export.watermarkSave")
            }
        }
        .padding(16)
        .onAppear {
            text = store.presets.first { $0.id == presetID }?.layers.first { $0.kind == .text }?.text ?? ""
        }
    }

    private func save() {
        let words = text.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return }
        // Settings may have changed the presets since this sheet read them.
        store.reload()
        if var preset = store.presets.first(where: { $0.id == presetID }),
           let index = preset.layers.firstIndex(where: { $0.kind == .text }) {
            preset.layers[index].text = words
            if preset.layers.count == 1 { preset.name = words }
            store.upsert(preset)
        } else {
            var layer = PhotoOverlay(kind: .text)
            layer.text = words
            let preset = SignaturePreset(name: words, createdAt: Date(), layers: [layer])
            store.upsert(preset)
            presetID = preset.id
        }
        isEnabled = true
        isPresented = false
    }
}

/// The token chips: as many to a line as fit.
private struct MacExportChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 260
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(width, widest), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

private struct MacExportChipStyle: ButtonStyle {
    /// The board's token pill.
    static let radius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(MacTheme.Editor.label)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(configuration.isPressed ? MacTheme.Editor.pressed : MacTheme.Editor.fill,
                        in: RoundedRectangle(cornerRadius: Self.radius))
            .contentShape(RoundedRectangle(cornerRadius: Self.radius))
    }
}

enum MacExportWords {
    #if DEBUG
    /// `-ShotDexExportTest` cleared the remembered choices this launch.
    @MainActor static var testWasReset = false
    #endif

    static func anchor(_ anchor: WatermarkAnchor) -> String {
        switch anchor {
        case .topLeft: String(localized: "Top Left", comment: "Watermark placement")
        case .top: String(localized: "Top", comment: "Watermark placement")
        case .topRight: String(localized: "Top Right", comment: "Watermark placement")
        case .left: String(localized: "Left", comment: "Watermark placement")
        case .center: String(localized: "Center", comment: "Watermark placement")
        case .right: String(localized: "Right", comment: "Watermark placement")
        case .bottomLeft: String(localized: "Bottom Left", comment: "Watermark placement")
        case .bottom: String(localized: "Bottom", comment: "Watermark placement")
        case .bottomRight: String(localized: "Bottom Right", comment: "Watermark placement")
        }
    }

    /// The watermark card's picture: the editor's frame, small, stamped.
    nonisolated static func card(_ preview: CGImage?, stamp: WatermarkStamp?) -> CGImage? {
        guard let preview else { return nil }
        var image = CIImage(cgImage: preview)
        let scale = min(1, 240 / max(image.extent.width, image.extent.height))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if let stamp { image = PhotoRenderService.applyWatermark(stamp, to: image) }
        return CIContext().createCGImage(image, from: image.extent.integral)
    }
}

/// One row of a section card (board: 30pt, label 13pt). A row with no title
/// gives its whole width to the control — a checkbox under the labels.
private struct MacExportRow<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.macExportLabelWidth) private var labelWidth

    var body: some View {
        HStack(spacing: 8) {
            if !title.isEmpty {
                Text(title).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: labelWidth, alignment: .leading)
            }
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
    }
}

extension EnvironmentValues {
    /// The label column of the export sheet's rows: 100 left, 72 right.
    @Entry var macExportLabelWidth: CGFloat = 100
}
