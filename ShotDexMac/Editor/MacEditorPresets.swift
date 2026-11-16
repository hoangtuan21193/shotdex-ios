import AppKit
import ShotDexKit
import SwiftUI

/// Presets and History (board `MAC_EditPresets`, FS-18.03 §1g): the panel in
/// the sidebar's place. Looks — the user's and the built-in film looks —
/// preview on the photo under the pointer and apply on a click; Snapshots keep
/// named states of this photo; History lists every step of the session and
/// jumps to any of them.
struct MacEditorPresetsPanel: View {
    @Bindable var model: MacEditorModel
    @State private var search = ""
    @State private var open: Set<String> = ["mine", "film"]
    @State private var naming: Naming?
    @State private var name = ""
    @State private var deleting: LookPreset?
    @State private var asksClearHistory = false
    @State private var updating: LookPreset?
    @State private var deletingSnapshot: EditorSnapshot?

    private enum Naming: Equatable {
        case newLook, rename(LookPreset), snapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                presets
                snapshots
                history
            }
            .padding(.top, 8)
        }
        .frame(width: 228)
        .background(MacTheme.Editor.inspector)
        .onAppear { model.loadLooks(); model.loadFilterThumbnails() }
        .onDisappear { model.preview(nil, name: nil) }
        .alert(alertTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField(String(localized: "Name", comment: "Mac editor presets: a name field"), text: $name)
            Button(String(localized: "Save", comment: "Mac editor presets")) { commitName() }
            Button(String(localized: "Cancel", comment: "Mac editor presets"), role: .cancel) { naming = nil }
        }
        .confirmationDialog(String(localized: "Delete “\(deleting?.name ?? "")”?", comment: "Mac editor presets: Delete Look… asks"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(String(localized: "Delete Look", comment: "Mac editor presets"), role: .destructive) {
                if let deleting { model.deleteLook(deleting) }
                deleting = nil
            }
        } message: {
            Text("Photos already edited with it keep their edits.", comment: "Mac editor presets: what deleting a look does not undo")
        }
        .confirmationDialog(String(localized: "Forget these steps?", comment: "Mac editor history: Clear asks"),
                            isPresented: $asksClearHistory) {
            Button(String(localized: "Clear Steps", comment: "Mac editor history"), role: .destructive) { model.clearHistory() }
        } message: {
            Text("You won't be able to Undo past this point. The photo stays as it is, and Revert to Original still works.",
                 comment: "Mac editor history: what Clear does")
        }
        .confirmationDialog(String(localized: "Replace “\(updating?.name ?? "")” with this photo's settings?", comment: "Mac editor presets: Update asks"),
                            isPresented: Binding(get: { updating != nil }, set: { if !$0 { updating = nil } })) {
            Button(String(localized: "Replace", comment: "Mac editor presets: confirm Update")) {
                if let updating { model.updateLook(updating) }
                updating = nil
            }
        } message: {
            Text("Photos already edited with it keep their edits; it applies the new settings from now on.", comment: "Mac editor presets: what Update does")
        }
        .confirmationDialog(String(localized: "Delete “\(deletingSnapshot?.name ?? "")”?", comment: "Mac editor snapshots: Delete asks"),
                            isPresented: Binding(get: { deletingSnapshot != nil }, set: { if !$0 { deletingSnapshot = nil } })) {
            Button(String(localized: "Delete Snapshot", comment: "Mac editor snapshots"), role: .destructive) {
                if let deletingSnapshot { model.deleteSnapshot(deletingSnapshot) }
                deletingSnapshot = nil
            }
        } message: {
            Text("The photo's edit stays as it is.", comment: "Mac editor snapshots: what deleting does not touch")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Presets and History", comment: "Mac editor: the left panel"))
    }

    private var alertTitle: String {
        switch naming {
        case .newLook: String(localized: "Save Look", comment: "Mac editor presets: name a new look")
        case .rename: String(localized: "Rename Look", comment: "Mac editor presets")
        case .snapshot: String(localized: "New Snapshot", comment: "Mac editor presets: name a snapshot")
        case nil: ""
        }
    }

    private func commitName() {
        switch naming {
        case .newLook: model.saveLook(named: name)
        case .rename(let preset): model.renameLook(preset, to: name)
        case .snapshot: model.addSnapshot(named: name)
        case nil: break
        }
        naming = nil
    }

    // MARK: Presets

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private func matches(_ name: String) -> Bool { query.isEmpty || name.localizedCaseInsensitiveContains(query) }

    @ViewBuilder
    private var presets: some View {
        head(String(localized: "Presets", comment: "Mac editor: the presets group")) {
            Button { name = model.suggestedLookName; naming = .newLook } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 20, height: 20).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(String(localized: "Save This Photo's Look", comment: "Mac editor presets: + tooltip"))
                .accessibilityLabel(String(localized: "Save This Photo's Look", comment: "Mac editor presets"))
                .accessibilityIdentifier("editor.presets.add")
        }
        // Said where the + was pressed, not at the foot of a long list.
        if let note = model.presetNote {
            Text(note).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.bottom, 4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("editor.presets.note")
        }
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(String(localized: "Search Presets", comment: "Mac editor presets: the search field"), text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .accessibilityIdentifier("editor.presets.search")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(MacTheme.Editor.field, in: RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius))
        .overlay(RoundedRectangle(cornerRadius: MacTheme.Editor.buttonRadius).strokeBorder(MacTheme.Editor.fieldStroke))
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 4)
        HStack(spacing: 8) {
            Text("Amount", comment: "Mac editor presets: how much of the look").font(.system(size: 12)).foregroundStyle(.secondary)
            MacEditorSlider(value: model.recipe.filterIntensity, range: 0...1, isBipolar: false,
                            begin: model.beginChange, change: { v in model.change { $0.filterIntensity = v } }, end: model.endChange,
                            reset: { model.apply { $0.filterIntensity = 1 } })
                .accessibilityLabel(String(localized: "Amount", comment: "Mac editor presets"))
                .accessibilityIdentifier("editor.presets.amount")
            Text("\(Int((model.recipe.filterIntensity * 100).rounded()))").font(.system(size: 12).monospacedDigit()).frame(width: 28, alignment: .trailing)
        }
        .padding(.leading, 6).padding(.trailing, 4)
        .frame(height: 28)
        // Nothing to scale without a look.
        .disabled(model.recipe.filter == .original && model.recipe.lutID == nil)
        .opacity(model.recipe.filter == .original && model.recipe.lutID == nil ? 0.45 : 1)
        .help(String(localized: "How strongly the look applies", comment: "Mac editor presets: Amount tooltip"))
        group("mine", String(localized: "My Looks", comment: "Mac editor presets: the user's looks"), count: model.myLooks.count) {
            let looks = model.myLooks.filter { matches($0.name) }
            if looks.isEmpty {
                Text(query.isEmpty ? "Save a look with + to use it on other photos." : "No looks match.", comment: "Mac editor presets: empty My Looks")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 4)
            }
            ForEach(looks) { preset in lookRow(preset) }
        }
        ForEach(FilmLookCategory.allCases) { category in
            let filters = PhotoFilter.all(in: category).filter { $0 != .original && matches(model.filterName($0)) }
            group(category.rawValue, category.displayName, count: filters.count) {
                ForEach(filters) { filter in filterRow(filter) }
            }
        }
        Color.clear.frame(height: 12)
    }

    private func lookRow(_ preset: LookPreset) -> some View {
        presetRow(name: preset.name, applied: model.isApplied(preset), thumbnail: preset.recipe.filter == .original ? nil : model.filterThumbnails[preset.recipe.filter],
                  id: "editor.presets.look",
                  hover: { model.preview($0 ? model.lookPreview(preset) : nil, name: preset.name) },
                  apply: { model.applyLook(preset) })
            .contextMenu {
                Button(String(localized: "Apply Look", comment: "Mac editor presets menu")) { model.applyLook(preset) }
                Divider()
                Button(String(localized: "Rename…", comment: "Mac editor presets menu")) { name = preset.name; naming = .rename(preset) }
                Button(String(localized: "Update with Current Settings…", comment: "Mac editor presets menu")) { updating = preset }
                Button(String(localized: "Duplicate", comment: "Mac editor presets menu")) { model.duplicateLook(preset) }
                Divider()
                Button(String(localized: "Share…", comment: "Mac editor presets menu")) { share(preset) }
                Menu(String(localized: "Export As", comment: "Mac editor presets menu")) {
                    Button(String(localized: "ShotDex Look (.shotdexlook)", comment: "Mac editor presets export")) { export(preset, asXMP: false) }
                    Button(String(localized: "Lightroom Preset (.xmp)", comment: "Mac editor presets export")) { export(preset, asXMP: true) }
                    Button(String(localized: "3D LUT (.cube)", comment: "Mac editor presets export")) {}
                        .disabled(true)
                }
                Divider()
                Button(String(localized: "Delete Look…", comment: "Mac editor presets menu"), role: .destructive) { deleting = preset }
            }
    }

    private func filterRow(_ filter: PhotoFilter) -> some View {
        presetRow(name: model.filterName(filter), applied: model.recipe.filter == filter && model.recipe.lutID == nil,
                  thumbnail: model.filterThumbnails[filter], id: "editor.presets.film",
                  hover: { model.preview($0 ? model.filterPreview(filter) : nil, name: model.filterName(filter)) },
                  apply: { model.applyFilter(filter) })
            .contextMenu {
                Button(String(localized: "Apply Look", comment: "Mac editor presets menu")) { model.applyFilter(filter) }
                Button(String(localized: "Remove Look", comment: "Mac editor presets menu: back to no look")) { model.applyFilter(.original) }
                    .disabled(model.recipe.filter != filter)
            }
    }

    private func presetRow(name: String, applied: Bool, thumbnail: CGImage?, id: String,
                           hover: @escaping (Bool) -> Void, apply: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Group {
                if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().scaledToFill() } else { MacTheme.Editor.control }
            }
            .frame(width: 36, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.Editor.thumbnailRadius))
            Text(name).font(.system(size: 13)).lineLimit(1)
            Spacer()
            if applied {
                // Board: a white ✓ — the accent is kept for what commits.
                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(MacTheme.Editor.label)
                    .accessibilityLabel(String(localized: "Applied", comment: "Mac editor presets, VoiceOver"))
            }
        }
        .padding(.leading, 22).padding(.trailing, 8)
        .frame(height: 28)
        .contentShape(Rectangle())
        .onHover(perform: hover)
        .onTapGesture(perform: apply)
        // Return / Space too, when the row has the keys.
        .focusable()
        .onKeyPress(.return) { apply(); return .handled }
        .onKeyPress(.space) { apply(); return .handled }
        .padding(.horizontal, 6)
        .help(String(localized: "Point to preview · click to apply · right-click for more", comment: "Mac editor presets: row tooltip"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(applied ? String(localized: "Applied", comment: "Mac editor presets, VoiceOver") : "")
        .accessibilityAddTraits(applied ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }

    private func group<Content: View>(_ id: String, _ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        let isOpen = open.contains(id) || !query.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if open.contains(id) { open.remove(id) } else { open.insert(id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(count.formatted()).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.leading, 6).padding(.trailing, 8)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOpen ? String(localized: "Expanded", comment: "Mac editor group, VoiceOver")
                                       : String(localized: "Collapsed", comment: "Mac editor group, VoiceOver"))
            .accessibilityIdentifier("editor.presets.group.\(id)")
            if isOpen { content() }
        }
    }

    private func head<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
    }

    // MARK: Files

    private func export(_ preset: LookPreset, asXMP: Bool) {
        guard let file = model.exportLook(preset, asXMP: asXMP) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.lastPathComponent
        panel.message = asXMP ? LookXMPWriter.notAffiliated : ""
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // Replace in one step: a failed copy leaves the old file where it was.
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: file)
                } else {
                    try FileManager.default.copyItem(at: file, to: url)
                }
            } catch {
                Task { @MainActor in model.reportExportFailure() }
            }
        }
    }

    private func share(_ preset: LookPreset) {
        guard let file = model.exportLook(preset, asXMP: false), let window = NSApp.keyWindow, let view = window.contentView else { return }
        let picker = NSSharingServicePicker(items: [file])
        picker.show(relativeTo: CGRect(x: 240, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .maxX)
    }

    // MARK: Snapshots

    @ViewBuilder
    private var snapshots: some View {
        head(String(localized: "Snapshots", comment: "Mac editor: named states of this photo")) {
            Button { name = model.suggestedSnapshotName; naming = .snapshot } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 20, height: 20).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(String(localized: "New Snapshot", comment: "Mac editor presets"))
                .accessibilityLabel(String(localized: "New Snapshot", comment: "Mac editor presets"))
                .accessibilityIdentifier("editor.snapshots.add")
        }
        if model.snapshots.isEmpty {
            Text("Keep a version of this photo's edit with +.", comment: "Mac editor: no snapshots yet")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 4)
        }
        ForEach(model.snapshots) { snapshot in
            HStack(spacing: 8) {
                Image(systemName: "camera").font(.system(size: 14)).foregroundStyle(.secondary)
                Text(snapshot.name).font(.system(size: 13)).lineLimit(1)
                Spacer()
                Text(snapshot.createdAt.formatted(.dateTime.month(.abbreviated).day())).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
            .onHover { model.preview($0 ? snapshot.recipe : nil, name: snapshot.name) }
            .onTapGesture { model.applySnapshot(snapshot) }
            .contextMenu {
                Button(String(localized: "Apply Snapshot", comment: "Mac editor snapshots menu")) { model.applySnapshot(snapshot) }
                Button(String(localized: "Delete Snapshot…", comment: "Mac editor snapshots menu"), role: .destructive) { deletingSnapshot = snapshot }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("editor.snapshots.row")
        }
        Color.clear.frame(height: 12)
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        let steps = model.historySteps
        let current = model.historyIndex
        head(String(localized: "History", comment: "Mac editor: this session's steps")) {
            Button(String(localized: "Clear", comment: "Mac editor history")) { asksClearHistory = true }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).frame(height: 18).contentShape(Rectangle())
                .disabled(steps.count <= 1)
                .accessibilityIdentifier("editor.history.clear")
        }
        // Newest at the top; steps after the one shown are greyed (Redo reaches them).
        ForEach(steps.reversed(), id: \.index) { step in
            let isCurrent = step.index == current, isUndone = step.index > current
            let parts = MacHistoryWords.split(step.label)
            HStack(spacing: 6) {
                Text(parts.name).font(.system(size: 12)).lineLimit(1)
                    .foregroundStyle(isUndone ? MacTheme.Editor.dim : MacTheme.Editor.label)
                Spacer(minLength: 4)
                Text(parts.value).font(.system(size: 11).monospacedDigit()).lineLimit(1)
                    .foregroundStyle(isUndone ? MacTheme.Editor.dim : MacTheme.Editor.secondaryText)
            }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(isCurrent ? MacTheme.Editor.rowSelected : Color.clear, in: RoundedRectangle(cornerRadius: MacTheme.Editor.controlRadius))
                .contentShape(Rectangle())
                .onTapGesture { model.jumpHistory(to: step.index) }
                .help(isUndone ? String(localized: "Undone — a new edit replaces these steps", comment: "Mac editor history: a greyed step") : "")
                .padding(.horizontal, 6)
                .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("editor.history.step")
        }
        .padding(.bottom, 12)
    }
}

/// A history step's words: "Exposure +0.65" → "Exposure" and "+0.65" (board: the value on the right).
enum MacHistoryWords {
    static func split(_ label: String) -> (name: String, value: String) {
        guard let space = label.lastIndex(of: " ") else { return (label, "") }
        let tail = String(label[label.index(after: space)...])
        guard let first = tail.first, "+−-0123456789".contains(first) else { return (label, "") }
        return (String(label[..<space]), tail)
    }
}
