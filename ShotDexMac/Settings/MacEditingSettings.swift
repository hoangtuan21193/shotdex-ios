import ShotDexKit
import SwiftUI

/// Settings › Editing (board `MAC_SettingsEditing`, FS-18.04 §3c): which file
/// of a RAW + JPEG pair the editor opens, what the Save and Export sheet
/// starts with, and the presets it offers.
struct MacEditingSettings: View {
    @AppStorage(MacEditingDefaults.editsJPEGKey) private var editsJPEG = false
    @AppStorage(SettingsKeys.shareMetadataLevel) private var metadataLevel = MetadataLevel.all.rawValue
    @State private var defaults = MacExportChoices.defaultChoices()
    @State private var sizes = CompressionPresetStore()
    @State private var signatures = SignaturePresetStore()
    /// What the pane opened with, after its own repairs: only a change from
    /// it is the user's, and only that sends the Export sheet back to these.
    @State private var openedWith: MacExportChoices?
    @State private var nameText = ""
    @FocusState private var editsName: Bool

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Picker(String(localized: "RAW + JPEG Pairs", comment: "Mac Settings › Editing row"), selection: $editsJPEG) {
                        Text("Edit the RAW", comment: "Mac Settings › Editing: RAW + JPEG pair choice").tag(false)
                        Text("Edit the JPEG", comment: "Mac Settings › Editing: RAW + JPEG pair choice").tag(true)
                    }
                    .popup()
                    .accessibilityIdentifier("settings.editing.pairs")
                } label: {
                    Text("RAW + JPEG Pairs", comment: "Mac Settings › Editing row")
                    Text("Which file the editor opens for a photo not edited yet. Edited photos keep the file they were edited on.",
                         comment: "Mac Settings › Editing row explanation")
                }
            } header: {
                Text("RAW", comment: "Mac Settings › Editing group")
            } footer: {
                Text("Exports keep the original’s color profile unless you pick sRGB, Display P3 or Adobe RGB in the Export sheet.",
                     comment: "Mac Settings › Editing footer")
            }
            Section {
                LabeledContent(String(localized: "Size", comment: "Mac Settings › Export Defaults row")) {
                    Picker(String(localized: "Size", comment: "Mac Settings › Export Defaults row"), selection: Binding(
                        get: { defaults.files.presetId },
                        set: { id in
                            defaults.files.presetId = id
                            // A preset of the user's carries its own format and quality.
                            if let preset = sizes.customPresets.first(where: { $0.id == id }) {
                                defaults.files.format = preset.format
                                defaults.files.quality = FileExportQuality.clamped(preset.quality)
                            }
                        })) {
                        ForEach(sizes.allPresets) { Text($0.name).tag($0.id) }
                    }
                    .popup()
                    .accessibilityIdentifier("settings.editing.size")
                }
                LabeledContent(String(localized: "Format and Quality", comment: "Mac Settings › Export Defaults row")) {
                    MacFormatQualityMenu(format: $defaults.files.format, quality: $defaults.files.quality)
                }
                LabeledContent {
                    // Written back on Return or leaving the field; an empty one is the original name.
                    TextField(FileNameTemplate.originalName.pattern, text: $nameText)
                        .focused($editsName)
                        .onSubmit(commitName)
                        .onChange(of: editsName) { _, focused in if !focused { commitName() } }
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityIdentifier("settings.editing.fileNames")
                } label: {
                    Text("File Names", comment: "Mac Settings › Export Defaults row")
                    Text(MacEditingDefaults.example(nameText.trimmingCharacters(in: .whitespaces).isEmpty
                                                    ? FileNameTemplate.originalName.pattern : nameText, format: defaults.files.format))
                        .accessibilityIdentifier("settings.editing.example")
                }
                LabeledContent(String(localized: "If a File Exists", comment: "Mac Settings › Export Defaults row")) {
                    Picker(String(localized: "If a File Exists", comment: "Mac Settings › Export Defaults row"), selection: $defaults.files.conflictPolicy) {
                        ForEach(FileExportConflictPolicy.allCases, id: \.self) { Text(ExportCopy.policy($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings.editing.ifExists")
                }
                LabeledContent {
                    Picker(String(localized: "Metadata When Sharing", comment: "Mac Settings › Export Defaults row"), selection: $metadataLevel) {
                        Text("All Metadata", comment: "Mac export: metadata level").tag(MetadataLevel.all.rawValue)
                        Text("All Except Location", comment: "Mac export: metadata level without GPS").tag(MetadataLevel.noLocation.rawValue)
                        Text("No Metadata", comment: "Mac export: metadata level").tag(MetadataLevel.noMetadata.rawValue)
                    }
                    .popup()
                    .accessibilityIdentifier("settings.editing.metadata")
                } label: {
                    Text("Metadata When Sharing", comment: "Mac Settings › Export Defaults row")
                    Text("Each share and export can change it", comment: "Mac Settings › Export Defaults row explanation")
                }
                // Share on the Mac sends the files as they are: nothing would stamp them yet.
                MacLaterSettingsRow(title: String(localized: "Watermark When Sharing", comment: "Mac Settings › Export Defaults row")) {
                    Picker(String(localized: "Watermark When Sharing", comment: "Mac Settings › Export Defaults row"), selection: .constant(0)) {
                        Text("Off", comment: "Mac Settings › Export Defaults: no watermark").tag(0)
                    }
                    .labelsHidden()
                }
            } header: {
                Text("Export Defaults", comment: "Mac Settings › Editing group")
            } footer: {
                Text("The Export sheet starts with these, then remembers your last choices there — until you change one here. Metadata always starts here.",
                     comment: "Mac Settings › Editing footer")
            }
            MacPresetsSection(sizes: sizes, signatures: signatures)
        }
        .formStyle(.grouped)
        .onChange(of: defaults) { _, new in
            new.saveAsDefault()
            // A default changed on purpose: the sheet opens with it next time,
            // not with what it remembered from before.
            if new != openedWith { UserDefaults.standard.removeObject(forKey: MacExportChoices.key) }
        }
        .onAppear {
            #if DEBUG
            // `-ShotDexEditingSettingsTest`: each click-test run starts from nothing remembered.
            if ProcessInfo.processInfo.arguments.contains("-ShotDexEditingSettingsTest"), !MacEditingDefaults.testWasReset {
                MacEditingDefaults.testWasReset = true
                for key in [SettingsKeys.compressionPresets, MacExportChoices.defaultsKey, MacExportChoices.key,
                            MacEditingDefaults.editsJPEGKey, SettingsKeys.shareMetadataLevel] {
                    UserDefaults.standard.removeObject(forKey: key)
                }
                defaults = MacExportChoices()
                editsJPEG = false
                metadataLevel = MetadataLevel.all.rawValue
            }
            #endif
            sizes.reload()
            signatures.reload()
            // A Size whose preset was deleted reads Original, as the sheet does.
            if !sizes.allPresets.contains(where: { $0.id == defaults.files.presetId }) {
                defaults.files.presetId = ResizePreset.original.id
            }
            openedWith = defaults
            nameText = defaults.files.nameTemplate
        }
        // The Export sheet (another window) changed the presets: read them again.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            sizes.reload()
            signatures.reload()
        }
    }
}

extension MacEditingSettings {
    private func commitName() {
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        // Never an empty name: the sheet could not export with it.
        defaults.files.nameTemplate = trimmed.isEmpty ? FileNameTemplate.originalName.pattern : trimmed
        nameText = defaults.files.nameTemplate
    }
}

/// The Mac's own editing choices (FS-18.04 §3c).
enum MacEditingDefaults {
    /// A RAW + JPEG pair opens its JPEG in the editor (off: the RAW).
    static let editsJPEGKey = "mac.editing.pairsEditJPEG"

    static var editsJPEG: Bool { UserDefaults.standard.bool(forKey: editsJPEGKey) }

    #if DEBUG
    @MainActor static var testWasReset = false
    #endif

    /// Photos whose edit was made on the JPEG of their pair: they keep
    /// opening it whatever the setting says later, so the edit stays on the
    /// file it was made for.
    static let twinEditedKey = "mac.editing.editedOnJPEG"

    static func editsTwin(_ photoId: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: twinEditedKey) ?? []).contains(photoId)
    }

    static func unmarkTwinEdited(_ photoId: String) {
        var ids = UserDefaults.standard.stringArray(forKey: twinEditedKey) ?? []
        guard let index = ids.firstIndex(of: photoId) else { return }
        ids.remove(at: index)
        UserDefaults.standard.set(ids, forKey: twinEditedKey)
    }

    static func markTwinEdited(_ photoId: String) {
        var ids = UserDefaults.standard.stringArray(forKey: twinEditedKey) ?? []
        guard !ids.contains(photoId) else { return }
        ids.append(photoId)
        UserDefaults.standard.set(ids, forKey: twinEditedKey)
    }

    /// "Example: 2026-09-28_DSC04218.jpg", from a sample photo.
    static func example(_ pattern: String, format: PhotoOutputFormat) -> String {
        let values = FileNameValues(original: "DSC04218", captureDate: sampleDate, camera: "ILCE-7M4", lens: "FE 24mm F1.4 GM")
        let base = FileNameTemplate(pattern).baseName(for: values, sequence: 1, sequenceWidth: 3)
        let ext = format == .heic ? "heic" : "jpg"
        return String(localized: "Example: \(base).\(ext)", comment: "Mac Settings › Export Defaults: the name a file would get")
    }

    private static let sampleDate = DateComponents(calendar: .current, year: 2026, month: 9, day: 28, hour: 17, minute: 5).date ?? Date()
}

extension MacExportChoices {
    /// Settings › Editing › Export Defaults: what the sheet starts with
    /// before it has remembered anything.
    static let defaultsKey = "mac.export.defaults"

    static func defaultChoices(_ store: UserDefaults = .standard) -> MacExportChoices {
        store.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(MacExportChoices.self, from: $0) } ?? MacExportChoices()
    }

    func saveAsDefault(_ store: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { store.set(data, forKey: Self.defaultsKey) }
    }
}

/// "Same as Original · 80%": one popup for the format and the quality.
struct MacFormatQualityMenu: View {
    @Binding var format: PhotoOutputFormat
    @Binding var quality: Double

    static let qualities: [Double] = [0.6, 0.7, 0.8, 0.9, 1]

    /// The step a preset's own quality (85%) sits closest to, for the tick.
    private var nearest: Double { Self.qualities.min { abs($0 - quality) < abs($1 - quality) } ?? 0.8 }

    var body: some View {
        Menu {
            Section(String(localized: "Format", comment: "Mac Settings › Export Defaults: format group")) {
                ForEach([PhotoOutputFormat.preserve, .jpeg, .heic], id: \.self) { choice in
                    Toggle(ExportCopy.formatName(choice), isOn: Binding(get: { format == choice }, set: { if $0 { format = choice } }))
                }
            }
            Section(String(localized: "Quality", comment: "Mac Settings › Export Defaults: quality group")) {
                ForEach(Self.qualities, id: \.self) { value in
                    Toggle(ExportCopy.qualityText(value), isOn: Binding(get: { nearest == value }, set: { if $0 { quality = value } }))
                }
            }
        } label: {
            Text("\(ExportCopy.formatName(format)) · \(ExportCopy.qualityText(quality))")
        }
        .frame(width: 200)
        .accessibilityIdentifier("settings.editing.format")
    }
}

// MARK: - Presets

/// Presets: the Resize presets the Export sheet's Size offers, and the
/// watermark presets made in the editor. Built-ins carry a lock and cannot
/// be removed or changed.
private struct MacPresetsSection: View {
    let sizes: CompressionPresetStore
    let signatures: SignaturePresetStore
    @State private var selection: MacPresetRow.ID?
    @State private var editing: MacPresetEdit?
    @State private var asksDelete = false

    private var rows: [MacPresetRow] {
        sizes.allPresets.map { MacPresetRow.resize($0) } + signatures.presets.map { MacPresetRow.watermark($0) }
    }

    private var selected: MacPresetRow? { rows.first { $0.id == selection } }

    var body: some View {
        Section {
            VStack(spacing: 0) {
                header
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    line(row, index: index)
                }
                Divider()
                bar
            }
            .listRowInsets(EdgeInsets())
        } header: {
            HStack {
                Text("Presets", comment: "Mac Settings › Editing group")
                Spacer()
                Text("\(sizes.allPresets.count) resize · \(signatures.presets.count) watermark",
                     comment: "Mac Settings › Editing: how many presets of each kind")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        } footer: {
            Text("Built-in presets can’t be removed. Watermark presets come from the editor’s Markup tools. Custom presets stay on this Mac.",
                 comment: "Mac Settings › Editing: presets footer")
        }
        .sheet(item: $editing) { edit in
            MacPresetEditor(edit: edit, sizes: sizes, signatures: signatures) { selection = $0 }
        }
        .confirmationDialog(String(localized: "Delete “\(selected?.name ?? "")”?", comment: "Mac Settings › Editing: confirm removing a preset"),
                            isPresented: $asksDelete) {
            Button(String(localized: "Delete", comment: "Mac Settings › Editing: remove the preset"), role: .destructive, action: delete)
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
        } message: {
            if case .watermark? = selected {
                Text("It goes from the Export sheet’s Text list; exports already made keep their stamp. This can’t be undone.",
                     comment: "Mac Settings › Editing: what deleting a watermark preset does")
            } else {
                Text("Export choices that use it go back to Original size. Files already exported stay as they are. This can’t be undone.",
                     comment: "Mac Settings › Editing: what deleting a resize preset does")
            }
        }
    }

    /// Board: header 28 with column dividers, Name 220 · Type 110 · Details.
    private var header: some View {
        HStack(spacing: 0) {
            Text("Name", comment: "Mac Settings › Editing: presets column").padding(.leading, 12).frame(width: 220, alignment: .leading)
            Divider().frame(height: 14)
            Text("Type", comment: "Mac Settings › Editing: presets column").padding(.leading, 10).frame(width: 110, alignment: .leading)
            Divider().frame(height: 14)
            Text("Details", comment: "Mac Settings › Editing: presets column").padding(.leading, 10).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(height: 28)
        .background(MacTheme.rowAlternate)
    }

    private func line(_ row: MacPresetRow, index: Int) -> some View {
        let isSelected = row.id == selection
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(row.name).lineLimit(1).foregroundStyle(.primary)
                if row.isBuiltIn {
                    Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Built-in", comment: "VoiceOver: a preset that cannot be removed"))
                }
            }
            .font(.system(size: 13))
            .padding(.leading, 12)
            .frame(width: 221, alignment: .leading)
            Text(row.type).padding(.leading, 10).frame(width: 111, alignment: .leading)
            Text(row.detail).monospacedDigit().lineLimit(1).truncationMode(.middle)
                .padding(.leading, 10).padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(height: 28)
        .background(isSelected ? MacTheme.rowSelection : (index % 2 == 1 ? MacTheme.rowAlternate : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { selection = row.id }
        .onTapGesture(count: 2) {
            selection = row.id
            if !row.isBuiltIn { editing = row.edit }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("settings.preset.\(row.name)")
    }

    private var bar: some View {
        HStack(spacing: 2) {
            Button { editing = .newResize } label: { Image(systemName: "plus").frame(width: 24, height: 22) }
                .buttonStyle(.borderless)
                .help(String(localized: "Add a resize preset", comment: "Mac Settings › Editing: + under the presets"))
                .accessibilityLabel(String(localized: "Add Preset", comment: "Mac Settings › Editing"))
                .accessibilityIdentifier("settings.preset.add")
            Divider().frame(height: 14)
            Button { asksDelete = true } label: { Image(systemName: "minus").frame(width: 24, height: 22) }
                .buttonStyle(.borderless)
                .disabled(selected == nil || selected?.isBuiltIn == true || selected?.keepsImages == true)
                .help(selected?.keepsImages == true
                      ? String(localized: "This watermark has a picture that edited photos still use; remove it in the editor’s Markup tools", comment: "Mac Settings › Editing: − is off for a watermark with an image")
                      : String(localized: "Delete the selected preset", comment: "Mac Settings › Editing: − under the presets"))
                .accessibilityLabel(String(localized: "Remove Preset", comment: "Mac Settings › Editing"))
                .accessibilityIdentifier("settings.preset.remove")
            Spacer()
            Button(String(localized: "Edit…", comment: "Mac Settings › Editing: change the selected preset")) {
                editing = selected?.edit
            }
            .controlSize(.small)
            .disabled(selected == nil || selected?.isBuiltIn == true)
            .accessibilityIdentifier("settings.preset.edit")
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(MacTheme.rowAlternate)
    }

    private func delete() {
        guard let selected, !selected.isBuiltIn, !selected.keepsImages else { return }
        sizes.reload()
        signatures.reload()
        switch selected {
        case .resize(let preset): sizes.delete(id: preset.id)
        case .watermark(let preset): signatures.delete(id: preset.id)
        }
        selection = nil
    }
}

/// One row of the presets table.
enum MacPresetRow: Identifiable {
    case resize(ResizePreset)
    case watermark(SignaturePreset)

    var id: String {
        switch self {
        case .resize(let preset): "resize-\(preset.id)"
        case .watermark(let preset): "watermark-\(preset.id)"
        }
    }

    var name: String {
        switch self {
        case .resize(let preset): preset.name
        case .watermark(let preset): preset.name
        }
    }

    var isBuiltIn: Bool {
        if case .resize(let preset) = self { return preset.isBuiltIn }
        return false
    }

    /// A watermark with a picture in it: deleting the preset would delete the
    /// picture's file, which photos stamped in the editor still draw from.
    var keepsImages: Bool {
        if case .watermark(let preset) = self { return preset.layers.contains { $0.imageID != nil } }
        return false
    }

    var type: String {
        switch self {
        case .resize: String(localized: "Resize", comment: "Mac Settings › Editing: preset type")
        case .watermark: String(localized: "Watermark", comment: "Mac Settings › Editing: preset type")
        }
    }

    /// "Long edge 2048 px · JPEG 80%", "“© Linh Pham” · bottom left".
    var detail: String {
        switch self {
        case .resize(let preset): return MacPresetWords.resize(preset)
        case .watermark(let preset):
            let text = preset.layers.first { $0.kind == .text }?.text
            return text.map { "“\($0)”" } ?? String(localized: "\(preset.layers.count) layers", comment: "Mac Settings › Editing: a watermark with no text")
        }
    }

    var edit: MacPresetEdit? {
        switch self {
        case .resize(let preset): preset.isBuiltIn ? nil : .resize(preset)
        case .watermark(let preset): .watermark(preset)
        }
    }
}

enum MacPresetWords {
    static func resize(_ preset: ResizePreset) -> String {
        let size: String
        switch preset.kind {
        case .original: size = String(localized: "Original pixels", comment: "Mac Settings › Editing: a preset that keeps the size")
        case .longEdge: size = String(localized: "Long edge \(String(preset.longEdge ?? 0)) px", comment: "Mac Settings › Editing: a long-edge preset")
        case .exact:
            let crop = preset.cropMode == .fill
                ? String(localized: "Fill", comment: "Mac Settings › Editing: exact size, cropped to fill")
                : String(localized: "Fit", comment: "Mac Settings › Editing: exact size, fitted inside")
            size = "\(preset.width ?? 0) × \(preset.height ?? 0) · \(crop)"
        }
        let format = preset.format == .heic ? "HEIC" : "JPEG"
        return "\(size) · \(format) \(ExportCopy.qualityText(preset.quality))"
    }
}

// MARK: - Editor sheet

enum MacPresetEdit: Identifiable {
    case newResize
    case resize(ResizePreset)
    case watermark(SignaturePreset)

    var id: String {
        switch self {
        case .newResize: "new"
        case .resize(let preset): "resize-\(preset.id)"
        case .watermark(let preset): "watermark-\(preset.id)"
        }
    }
}

/// Add Preset / Edit…: a resize preset's name, size, format and quality, or
/// a watermark preset's name and words.
private struct MacPresetEditor: View {
    let edit: MacPresetEdit
    let sizes: CompressionPresetStore
    let signatures: SignaturePresetStore
    let saved: (MacPresetRow.ID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = ResizePresetKind.longEdge
    @State private var longEdge = 2400
    @State private var width = 2400
    @State private var height = 1600
    @State private var cropMode = ResizeCropMode.fit
    @State private var format = PhotoOutputFormat.jpeg
    @State private var quality = 0.8
    @State private var words = ""

    private var isWatermark: Bool { if case .watermark = edit { return true } else { return false } }
    /// A watermark of pictures only has no words to edit.
    private var hasText: Bool {
        if case .watermark(let preset) = edit { return preset.layers.contains { $0.kind == .text } }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding([.horizontal, .top], 20)
            Form {
                TextField(String(localized: "Name", comment: "Mac Settings › preset editor"), text: $name)
                    .accessibilityIdentifier("preset.name")
                if isWatermark {
                    if hasText {
                        TextField(String(localized: "Text", comment: "Mac Settings › preset editor: the watermark's words"), text: $words)
                            .accessibilityIdentifier("preset.text")
                    }
                } else {
                    Picker(String(localized: "Size", comment: "Mac Settings › preset editor"), selection: $kind) {
                        Text("Long Edge", comment: "Mac Settings › preset editor: size kind").tag(ResizePresetKind.longEdge)
                        Text("Exact Size", comment: "Mac Settings › preset editor: size kind").tag(ResizePresetKind.exact)
                        Text("Original Pixels", comment: "Mac Settings › preset editor: size kind").tag(ResizePresetKind.original)
                    }
                    .accessibilityIdentifier("preset.kind")
                    if kind == .longEdge {
                        TextField(String(localized: "Long Edge (px)", comment: "Mac Settings › preset editor"), value: $longEdge, format: .number)
                            .accessibilityIdentifier("preset.longEdge")
                    } else if kind == .exact {
                        TextField(String(localized: "Width (px)", comment: "Mac Settings › preset editor"), value: $width, format: .number)
                            .accessibilityIdentifier("preset.width")
                        TextField(String(localized: "Height (px)", comment: "Mac Settings › preset editor"), value: $height, format: .number)
                            .accessibilityIdentifier("preset.height")
                        Picker(String(localized: "Crop", comment: "Mac Settings › preset editor"), selection: $cropMode) {
                            Text("Fit Inside", comment: "Mac Settings › preset editor: exact size, the whole photo fitted inside").tag(ResizeCropMode.fit)
                            Text("Crop to Fill", comment: "Mac Settings › preset editor: exact size, cropped to fill it").tag(ResizeCropMode.fill)
                        }
                        .accessibilityIdentifier("preset.crop")
                    }
                    Picker(String(localized: "Format", comment: "Mac Settings › preset editor"), selection: $format) {
                        ForEach([PhotoOutputFormat.preserve, .jpeg, .heic], id: \.self) { Text(ExportCopy.formatName($0)).tag($0) }
                    }
                    .accessibilityIdentifier("preset.format")
                    LabeledContent(String(localized: "Quality", comment: "Mac Settings › preset editor")) {
                        HStack {
                            Slider(value: $quality, in: FileExportQuality.range, step: FileExportQuality.step)
                                .accessibilityIdentifier("preset.quality")
                            Text(ExportCopy.qualityText(quality)).monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if let problem { Text(problem).font(.caption).foregroundStyle(MacTheme.redText) }
                Spacer()
                Button(String(localized: "Cancel", comment: "Mac sheet: cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("preset.cancel")
                Button(String(localized: "Save", comment: "Mac Settings › preset editor: keep the preset"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(MacPushButtonStyle(isDefault: true, defaultWeight: .medium))
                    .disabled(problem != nil)
                    .accessibilityIdentifier("preset.save")
            }
            .padding(20)
        }
        .frame(width: 420)
        .onAppear(perform: load)
    }

    private var title: String {
        switch edit {
        case .newResize: String(localized: "New Resize Preset", comment: "Mac Settings › preset editor title")
        case .resize: String(localized: "Edit Resize Preset", comment: "Mac Settings › preset editor title")
        case .watermark: String(localized: "Edit Watermark", comment: "Mac Settings › preset editor title")
        }
    }

    /// Why Save is off, said beside it.
    private var problem: String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return String(localized: "Give it a name.", comment: "Mac Settings › preset editor: empty name")
        }
        if takenNames.contains(trimmed.lowercased()) {
            return String(localized: "Another preset has this name.", comment: "Mac Settings › preset editor: duplicate name")
        }
        if isWatermark {
            return hasText && words.trimmingCharacters(in: .whitespaces).isEmpty
                ? String(localized: "Write the watermark’s words.", comment: "Mac Settings › preset editor: empty text") : nil
        }
        switch kind {
        case .longEdge where !(64...20_000).contains(longEdge),
             .exact where !(64...20_000).contains(width) || !(64...20_000).contains(height):
            return String(localized: "Sizes run from 64 to 20,000 px.", comment: "Mac Settings › preset editor: size out of range")
        default:
            return nil
        }
    }

    /// Names of the other presets of its kind, any case.
    private var takenNames: Set<String> {
        switch edit {
        case .newResize: Set(sizes.allPresets.map { $0.name.lowercased() })
        case .resize(let preset): Set(sizes.allPresets.filter { $0.id != preset.id }.map { $0.name.lowercased() })
        case .watermark(let preset): Set(signatures.presets.filter { $0.id != preset.id }.map { $0.name.lowercased() })
        }
    }

    private func load() {
        switch edit {
        case .newResize:
            name = String(localized: "New Preset", comment: "Mac Settings › preset editor: a new preset's name")
        case .resize(let preset):
            name = preset.name
            kind = preset.kind
            longEdge = preset.longEdge ?? 2400
            width = preset.width ?? 2400
            height = preset.height ?? 1600
            cropMode = preset.cropMode
            format = preset.format
            quality = preset.quality
        case .watermark(let preset):
            name = preset.name
            words = preset.layers.first { $0.kind == .text }?.text ?? ""
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch edit {
        case .newResize, .resize:
            sizes.reload()
            var preset: ResizePreset
            if case .resize(let existing) = edit {
                preset = sizes.customPresets.first { $0.id == existing.id } ?? existing
            } else {
                preset = ResizePreset(name: trimmed, kind: kind)
            }
            preset.name = trimmed
            preset.kind = kind
            preset.longEdge = kind == .longEdge ? longEdge : nil
            preset.width = kind == .exact ? width : nil
            preset.height = kind == .exact ? height : nil
            preset.cropMode = cropMode
            preset.format = format
            preset.quality = FileExportQuality.clamped(quality)
            sizes.upsert(preset)
            saved(MacPresetRow.resize(preset).id)
        case .watermark(let original):
            // The layers as stored now, not as this sheet opened them.
            signatures.reload()
            var preset = signatures.presets.first { $0.id == original.id } ?? original
            preset.name = trimmed
            if let index = preset.layers.firstIndex(where: { $0.kind == .text }) {
                preset.layers[index].text = words.trimmingCharacters(in: .whitespaces)
            }
            signatures.upsert(preset)
            saved(MacPresetRow.watermark(preset).id)
        }
        dismiss()
    }
}

private extension View {
    /// A popup of the pane: 200 wide, one column down the board.
    func popup() -> some View { labelsHidden().frame(width: 200) }
}
