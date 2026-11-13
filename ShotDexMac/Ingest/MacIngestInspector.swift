import AppKit
import SwiftUI

/// Where the card's photos go (board `MAC_Ingest`'s inspector, FS-20 §6):
/// the destination source and its folders, what happens after, and what
/// Import will do — or why it can't yet.
struct MacIngestInspector: View {
    @Bindable var model: IngestModel
    let readiness: IngestReadiness?
    @Environment(MacDependencies.self) private var dependencies
    @State private var keyword = ""
    @FocusState private var isTypingKeyword: Bool
    /// Bumped after a popup item that runs an action rather than choosing
    /// (New Folder…, Choose Folder…, Save as Preset…): the popup is built
    /// again, so it shows the real choice, not the item that was clicked.
    @State private var popupGeneration = 0
    @State private var asksPresetName = false
    @State private var presetName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                destination
                divider
                backup
                divider
                fileNames
                divider
                metadata
                divider
                afterImport
                summary.padding(.top, 16)
            }
            .padding(16)
        }
        .disabled(model.isRunning)
        .onReceive(NotificationCenter.default.publisher(for: .macIngestCommitFields)) { _ in addKeyword() }
        .onAppear {
            // Remembered on, with the folder gone from the settings: off, rather than a backup that silently never runs.
            if model.settings.backsUp, model.settings.backupFolder == nil { model.settings.backsUp = false }
        }
        .alert(String(localized: "Save Metadata Preset", comment: "Mac Import from Card: name the metadata preset"), isPresented: $asksPresetName) {
            TextField(String(localized: "Preset Name", comment: "Mac Import from Card: metadata preset name field"), text: $presetName)
            Button(replacesPreset ? String(localized: "Replace", comment: "Mac Import from Card: save over a metadata preset of the same name")
                                  : String(localized: "Save", comment: "Mac Import from Card: save the metadata preset"), action: savePreset)
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(String(localized: "Cancel", comment: "Mac Import from Card: don't save the preset"), role: .cancel) {}
        } message: {
            if replacesPreset {
                Text("A preset named “\(presetName.trimmingCharacters(in: .whitespaces))” already exists. Replace it with these fields?",
                     comment: "Mac Import from Card: saving a metadata preset under a name in use")
            } else {
                Text("Creator, Copyright and Keywords are saved under this name.", comment: "Mac Import from Card: what a metadata preset keeps")
            }
        }
    }

    private var replacesPreset: Bool {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        return model.settings.metadataPresets.contains { $0.name == name }
    }

    private var divider: some View { Divider().padding(.vertical, 14) }

    // MARK: Destination

    @ViewBuilder
    private var destination: some View {
        heading(String(localized: "Destination", comment: "Mac Import from Card inspector section"))
        if model.destinations.isEmpty {
            Text("Add a folder or drive in Sources first: imported photos join it.",
                 comment: "Mac Import from Card: no folder source to import into")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Add Folder…", comment: "Mac menu: File › Add Folder…")) {
                NotificationCenter.default.post(name: .macAddFolder, object: nil)
            }
            .buttonStyle(MacPushButtonStyle(isDefault: false))
            .padding(.top, 8)
        } else {
            Picker(selection: destinationChoice) {
                ForEach(model.destinations, id: \.id) { source in
                    Label(source.name, systemImage: MacSidebar.symbol(forSourceKind: source.kind)).tag(Optional(source.id))
                }
                Divider()
                Text("New Folder…", comment: "Mac Import from Card: pick a folder that becomes a source and the destination")
                    .tag(Optional(Self.newFolderTag))
            } label: {
                Text("Destination", comment: "Mac Import from Card inspector section")
            }
            .labelsHidden()
            .id(popupGeneration)
            if let caption = destinationCaption {
                caption
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            HStack(spacing: 8) {
                Text("Folders", comment: "Mac Import from Card: the folders photos are filed into")
                    .font(.system(size: 13))
                    .frame(width: 58, alignment: .leading)
                Picker(selection: $model.settings.folders) {
                    ForEach(Self.folderPresets, id: \.template) { preset in
                        Text(preset.title).tag(preset.template)
                    }
                    if !Self.folderPresets.contains(where: { $0.template == model.settings.folders }) {
                        Text(IngestCopy.foldersSummary(model.settings.folders)).tag(model.settings.folders)
                    }
                } label: {
                    Text("Folders", comment: "Mac Import from Card: the folders photos are filed into")
                }
                .labelsHidden()
            }
            .padding(.top, 12)
            if let folder = model.exampleFolder {
                Text(String(localized: "Example: \(folder)", comment: "Mac Import from Card: the folder the first photo goes into"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .padding(.leading, 66)
            }
        }
    }

    /// `Joins the T7 RAW Archive source · 1.31 TB free`, or that it is unplugged.
    private var destinationCaption: Text? {
        guard let source = model.destination, let drive = readiness?.destination else { return nil }
        guard drive.isConnected else {
            return Text("\(source.name) isn't connected.", comment: "Mac Import from Card: the destination drive is unplugged")
                .foregroundStyle(MacTheme.redText)
        }
        let joins = String(localized: "Joins the \(source.name) source", comment: "Mac Import from Card: imported photos become part of this source")
        guard let free = drive.freeBytes else { return Text(joins) }
        return Text(joins + " · " + String(localized: "\(IngestCopy.bytes(free)) free", comment: "Mac Import from Card: room left on the destination"))
    }

    static let folderPresets: [(title: String, template: IngestFolderTemplate)] = [
        (String(localized: "Year / Date", comment: "Mac Import from Card folders: 2026/2026-10-03"), .yearDate),
        (String(localized: "Date", comment: "Mac Import from Card folders: 2026-10-03"), IngestFolderTemplate(pattern: "{date}")),
        (String(localized: "None", comment: "Mac Import from Card folders: everything in the destination itself"), IngestFolderTemplate(pattern: "")),
    ]

    // MARK: New Folder…

    static let newFolderTag = "ingest.newFolder"

    /// The destination popup, whose last item opens a folder panel instead
    /// of choosing (FS-20 §6: a new folder becomes a source).
    private var destinationChoice: Binding<String?> {
        Binding {
            model.settings.destinationSourceId
        } set: { choice in
            guard choice == Self.newFolderTag else {
                model.settings.destinationSourceId = choice
                return
            }
            popupGeneration += 1
            chooseNewDestination()
        }
    }

    private func chooseNewDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Import Here", comment: "Mac Import from Card: the New Folder… panel's button")
        panel.message = String(localized: "Choose or create the folder imported photos go into. It becomes a source in the library.",
                               comment: "Mac Import from Card: New Folder… panel message")
        let done: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            addDestination(url)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }

    private func addDestination(_ url: URL) {
        let sources = dependencies.sourcesModel
        let roots = dependencies.folderRoots
        let path = url.standardizedFileURL.path
        // A folder that already is a source: chosen, not refused as an overlap.
        if let known = model.destinations.first(where: { roots.root($0.id)?.standardizedFileURL.path == path }) {
            model.settings.destinationSourceId = known.id
            return
        }
        Task {
            await sources.addFolder(url, includesSubfolders: true, pairsRawAndJpeg: true)
            if let failure = sources.failure {
                sources.failure = nil
                NotificationCenter.default.post(name: .macToast, object: failure.message)
                return
            }
            // One small read of the sources table, after a panel the user just closed.
            model.loadDestinations()
            if let added = model.destinations.first(where: { roots.root($0.id)?.standardizedFileURL.path == path }) {
                model.settings.destinationSourceId = added.id
            }
        }
    }

    // MARK: Backup

    static let chooseBackupTag = "ingest.chooseBackup"

    /// Also copy to a backup drive (FS-20 §6): any folder, copied and
    /// verified like the main copy, never added to the library.
    @ViewBuilder
    private var backup: some View {
        heading(String(localized: "Backup", comment: "Mac Import from Card inspector section"))
        Toggle(isOn: $model.settings.backsUp) {
            Text("Also copy to a backup drive", comment: "Mac Import from Card: also copy every photo to a second folder")
                .font(.system(size: 13))
        }
        .toggleStyle(.checkbox)
        .onChange(of: model.settings.backsUp) { _, isOn in
            // Turned on with nowhere to copy to: ask where at once.
            if isOn, model.settings.backupFolder == nil { chooseBackupFolder() }
        }
        if model.settings.backsUp {
            Picker(selection: backupChoice) {
                if let folder = model.settings.backupFolder {
                    Label(folder.title, systemImage: folder.isOnExternalDrive ? "externaldrive" : "folder").tag(Optional(folder.id.uuidString))
                }
                if model.settings.backupFolder != nil { Divider() }
                Text("Choose Folder…", comment: "Mac Import from Card: pick the backup folder").tag(Optional(Self.chooseBackupTag))
            } label: {
                Text("Backup Destination", comment: "Mac Import from Card: where the backup copies go")
            }
            .labelsHidden()
            .id(popupGeneration)
            .padding(.top, 8)
        }
        Group {
            if model.settings.backsUp, model.settings.backupFolder == nil {
                Text("Choose the folder that gets the backup copies.", comment: "Mac Import from Card: backup ticked, no folder yet")
                    .foregroundStyle(.secondary)
            } else if model.settings.backsUp, let drive = readiness?.backup, !drive.isConnected {
                Text("\(drive.name) isn't connected. Connect it or turn off the backup.",
                     comment: "Mac Import from Card: the backup folder's drive is unplugged")
                    .foregroundStyle(MacTheme.redText)
            } else {
                Text("Copied and verified the same way. Not added to the library.", comment: "Mac Import from Card: what the backup copy is")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 6)
    }

    private var backupChoice: Binding<String?> {
        Binding {
            model.settings.backupFolder?.id.uuidString
        } set: { choice in
            guard choice == Self.chooseBackupTag else { return }
            popupGeneration += 1
            chooseBackupFolder()
        }
    }

    private func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Back Up Here", comment: "Mac Import from Card: the backup folder panel's button")
        panel.message = String(localized: "Choose the folder that gets a second, verified copy of every imported photo.",
                               comment: "Mac Import from Card: backup folder panel message")
        let done: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                // Cancelled with nowhere chosen: the backup stays off.
                if model.settings.backupFolder == nil { model.settings.backsUp = false }
                return
            }
            Task {
                // Volume lookups and the bookmark off the main thread: a NAS can be slow to answer.
                let folder = await Task.detached(priority: .userInitiated) { () -> ExportFolder? in
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
                    guard var folder = try? ExportFolderStore.folder(for: url) else { return nil }
                    // Security-scoped, as a folder source's: the backup is written after a relaunch too.
                    guard let bookmark = try? SourceBookmark.make(for: url) else { return nil }
                    folder.bookmark = bookmark
                    return folder
                }.value
                if let folder {
                    model.settings.backupFolder = folder
                    model.settings.backsUp = true
                } else {
                    if model.settings.backupFolder == nil { model.settings.backsUp = false }
                    NotificationCenter.default.post(name: .macToast, object: String(localized: "ShotDex can't keep using \(url.lastPathComponent). Choose another folder.",
                                                                                     comment: "Mac Import from Card: the backup folder could not be remembered"))
                }
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }

    // MARK: File Names

    static let customNameTag = "ingest.customName"

    /// A preset, or a template typed with tokens (FS-20 §6, AC-25): the
    /// same eight chips as Export, and the first checked photo's new name.
    @ViewBuilder
    private var fileNames: some View {
        HStack(alignment: .center) {
            sectionTitle(String(localized: "File Names", comment: "Mac Import from Card inspector section"))
            Spacer(minLength: 8)
            Picker(selection: namePresetChoice) {
                ForEach(IngestSettings.namePresets, id: \.pattern) { template in
                    Text(IngestCopy.nameTitle(template)).tag(template.pattern)
                }
                if !IngestSettings.namePresets.contains(model.settings.template) {
                    Divider()
                    Text("Custom", comment: "Mac Import from Card: a file name template of the user's own").tag(Self.customNameTag)
                }
            } label: {
                Text("File Name Preset", comment: "Mac Import from Card: the file name preset popup")
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)
        }
        .padding(.bottom, 8)
        MacFileNameField(pattern: $model.settings.nameTemplate)
            .frame(height: 28)
            .accessibilityLabel(String(localized: "File Name Template", comment: "Mac Import from Card: the file name template field"))
        MacFlowLayout(spacing: 6) {
            ForEach(FileNameChip.all, id: \.self) { chip in
                Button(ExportCopy.chipTitle(chip)) {
                    model.settings.nameTemplate = chip.appended(to: model.settings.nameTemplate).pattern
                }
                .buttonStyle(MacChipButtonStyle())
                .accessibilityLabel(ExportCopy.insertChip(chip))
            }
        }
        .padding(.top, 8)
        if let example = model.exampleName {
            Text(String(localized: "Example: \(example)", comment: "Mac Import from Card: the first checked photo's new name"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 6)
        }
    }

    private var namePresetChoice: Binding<String> {
        Binding {
            IngestSettings.namePresets.contains(model.settings.template) ? model.settings.nameTemplate : Self.customNameTag
        } set: { choice in
            guard choice != Self.customNameTag else { return }
            model.settings.nameTemplate = choice
        }
    }

    // MARK: Metadata

    static let noPresetTag = "ingest.noPreset"
    static let savePresetTag = "ingest.savePreset"
    static let deletePresetTag = "ingest.deletePreset"

    /// Creator, Copyright and Keywords, written to a `.xmp` beside each
    /// copy (FS-20 §6), and the named presets that fill them.
    @ViewBuilder
    private var metadata: some View {
        HStack(alignment: .center) {
            sectionTitle(String(localized: "Metadata", comment: "Mac Import from Card inspector section"))
            Spacer(minLength: 8)
            Picker(selection: presetChoice) {
                Text("None", comment: "Mac Import from Card: no metadata preset").tag(Self.noPresetTag)
                if model.settings.matchingMetadataPreset == nil, !model.settings.metadata.isEmpty {
                    Text("Custom", comment: "Mac Import from Card: metadata of the user's own, not saved as a preset").tag("")
                }
                if !model.settings.metadataPresets.isEmpty { Divider() }
                ForEach(model.settings.metadataPresets, id: \.name) { preset in
                    Text(preset.name).tag(preset.name)
                }
                if !model.settings.metadata.isEmpty {
                    Divider()
                    Text("Save as Preset…", comment: "Mac Import from Card: keep these fields under a name").tag(Self.savePresetTag)
                }
                if let preset = model.settings.matchingMetadataPreset {
                    Text("Delete “\(preset.name)”", comment: "Mac Import from Card: forget a saved metadata preset").tag(Self.deletePresetTag)
                }
            } label: {
                Text("Metadata Preset", comment: "Mac Import from Card: the metadata preset popup")
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)
            .id(popupGeneration)
        }
        .padding(.bottom, 8)
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                fieldLabel(String(localized: "Creator", comment: "Mac Import from Card metadata field"))
                TextField(String(localized: "Creator", comment: "Mac Import from Card metadata field"), text: $model.settings.metadata.creator)
                    .textFieldStyle(.plain)
                    .macField()
                    .accessibilityLabel(String(localized: "Creator", comment: "Mac Import from Card metadata field"))
            }
            GridRow {
                fieldLabel(String(localized: "Copyright", comment: "Mac Import from Card metadata field"))
                TextField(String(localized: "Copyright", comment: "Mac Import from Card metadata field"), text: $model.settings.metadata.copyright)
                    .textFieldStyle(.plain)
                    .macField()
                    .accessibilityLabel(String(localized: "Copyright", comment: "Mac Import from Card metadata field"))
            }
            GridRow(alignment: .top) {
                fieldLabel(String(localized: "Keywords", comment: "Mac Import from Card metadata field"))
                    .frame(height: 28)
                keywordsField
            }
        }
        Text("Written to an .xmp sidecar next to each copy. ShotDex never edits file contents: the photos are copied byte for byte.",
             comment: "Mac Import from Card: where the metadata goes")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 66, alignment: .trailing)
            .accessibilityHidden(true)
    }

    /// The keywords as chips with ×, and a field that adds one on Return
    /// or a comma.
    private var keywordsField: some View {
        MacFlowLayout(spacing: 4) {
            ForEach(Array(model.settings.metadata.keywords.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 2) {
                    Text(word).font(.system(size: 12))
                    Button {
                        if model.settings.metadata.keywords.indices.contains(index) { model.settings.metadata.keywords.remove(at: index) }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Remove Keyword \(word)", comment: "Mac Import from Card: remove a keyword chip"))
                }
                .padding(.leading, 8)
                .padding(.trailing, 3)
                .frame(height: 20)
                .background(MacTheme.fill, in: Capsule())
            }
            TextField(String(localized: "Add Keyword", comment: "Mac Import from Card: type a keyword"), text: $keyword)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(minWidth: 70)
                .frame(height: 20)
                .focused($isTypingKeyword)
                .onSubmit(addKeyword)
                // A word typed and left: kept, not dropped.
                .onChange(of: isTypingKeyword) { _, isTyping in if !isTyping { addKeyword() } }
                .onChange(of: keyword) { _, typed in
                    if typed.contains(",") { addKeyword() }
                }
                .accessibilityLabel(String(localized: "Add Keyword", comment: "Mac Import from Card: type a keyword"))
        }
        .padding(3)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MacTheme.separator))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Keywords", comment: "Mac Import from Card metadata field"))
    }

    private func addKeyword() {
        for word in keyword.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !word.isEmpty {
            if !model.settings.metadata.keywords.contains(word) { model.settings.metadata.keywords.append(word) }
        }
        keyword = ""
    }

    private var presetChoice: Binding<String> {
        Binding {
            if let preset = model.settings.matchingMetadataPreset { return preset.name }
            return model.settings.metadata.isEmpty ? Self.noPresetTag : ""
        } set: { choice in
            switch choice {
            case Self.noPresetTag:
                model.settings.metadata = IngestMetadataPreset()
            case Self.savePresetTag:
                popupGeneration += 1
                presetName = model.settings.metadata.creator
                asksPresetName = true
            case Self.deletePresetTag:
                if let preset = model.settings.matchingMetadataPreset {
                    model.settings.metadataPresets.removeAll { $0.name == preset.name }
                }
            case "":
                break
            default:
                if let preset = model.settings.metadataPresets.first(where: { $0.name == choice }) {
                    model.settings.metadata = preset
                }
            }
        }
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !model.settings.metadata.isEmpty else { return }
        var preset = model.settings.metadata
        preset.name = name
        // A name used again replaces that preset.
        model.settings.metadataPresets.removeAll { $0.name == name }
        model.settings.metadataPresets.append(preset)
        model.settings.metadata = preset
    }

    // MARK: After Import

    @ViewBuilder
    private var afterImport: some View {
        heading(String(localized: "After Import", comment: "Mac Import from Card inspector section"))
        Toggle(isOn: $model.settings.ejectsAfterImport) {
            Text("Eject \(model.card.name) after import", comment: "Mac Import from Card: eject the card once every copy is verified")
                .font(.system(size: 13))
        }
        .toggleStyle(.checkbox)
    }

    // MARK: Summary

    /// `811 photos · 24.6 GB` and what Import does — or what stops it.
    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if readiness?.blocker == .nothingChecked {
                Text("Check the photos you want to import.", comment: "Mac Import from Card: nothing ticked yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let blocker = readiness?.footer {
                Text(blocker)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.redText)
            } else {
                Text(String(localized: "\(model.checkedCount) photos · \(IngestCopy.bytes(model.checkedBytes))",
                            comment: "Mac Import from Card: what Import copies"))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(String(localized: "Copied to \(model.destination?.name ?? ""), then each copy is read back and checked against the card before it counts as imported.",
                            comment: "Mac Import from Card: what happens on Import"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 10))
    }

    /// A heading on a row with a popup beside it: the row carries the gap below.
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A token chip under the name template (board `MAC_Ingest`): neutral fill,
/// 12pt, pressed darker — never the accent, which is Import's.
struct MacChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(configuration.isPressed ? MacTheme.pressed : MacTheme.fill, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}

/// The name template as a token field (board `MAC_Ingest`): tokens are
/// chips, the user's own text is plain text between them. Typing adds text;
/// a chip button adds a token at the end; Delete removes a chip whole.
struct MacFileNameField: NSViewRepresentable {
    @Binding var pattern: String

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        field.tokenStyle = .rounded
        // Nothing the user types splits off a chip: text stays text.
        field.tokenizingCharacterSet = CharacterSet(charactersIn: "\u{0}")
        field.font = .systemFont(ofSize: 13)
        // A white field with a hairline, as the board's other fields.
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.objectValue = Self.objects(for: pattern)
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.binding = $pattern
        // Only when the pattern changed from outside (a chip, a preset):
        // re-setting it while the user types would move the caret.
        guard Self.pattern(of: field.objectValue) != pattern else { return }
        field.objectValue = Self.objects(for: pattern)
    }

    func makeCoordinator() -> Coordinator { Coordinator(binding: $pattern) }

    /// A token as the field holds it; plain text is an `NSString`.
    final class TokenObject: NSObject {
        let token: FileNameTemplate.Token
        init(_ token: FileNameTemplate.Token) { self.token = token }
    }

    static func objects(for pattern: String) -> [Any] {
        FileNameTemplate(pattern).segments.map { segment -> Any in
            switch segment {
            case .literal(let text): text as NSString
            case .token(let token): TokenObject(token)
            }
        }
    }

    static func pattern(of value: Any?) -> String {
        guard let objects = value as? [Any] else { return (value as? String) ?? "" }
        return FileNameTemplate(segments: objects.compactMap { object in
            if let token = object as? TokenObject { return .token(token.token) }
            if let text = object as? String { return .literal(text) }
            return nil
        }).pattern
    }

    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var binding: Binding<String>

        init(binding: Binding<String>) { self.binding = binding }

        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
            if let token = representedObject as? TokenObject { return ExportCopy.tokenTitle(token.token) }
            return representedObject as? String
        }

        func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
            representedObject is TokenObject ? .rounded : .none
        }

        func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
            editingString as NSString
        }

        /// A chip is not edited as text: double-clicking it does nothing.
        func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
            representedObject as? String
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTokenField else { return }
            commit(field)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTokenField else { return }
            commit(field)
        }

        private func commit(_ field: NSTokenField) {
            let pattern = MacFileNameField.pattern(of: field.objectValue)
            if pattern != binding.wrappedValue { binding.wrappedValue = pattern }
        }
    }
}

extension View {
    /// A text field in the board's look (`MAC_STYLE`): 28pt, 13pt text,
    /// the content ground, a hairline, radius 8.
    func macField() -> some View {
        font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MacTheme.separator))
    }
}
