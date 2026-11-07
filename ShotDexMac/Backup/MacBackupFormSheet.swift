import IOKit.ps
import SwiftUI

/// New Backup / Edit on the Mac (boards `MAC_BackupNew`, `MAC_BackupOrganize`,
/// FS-22.06 §5.3): one 640×560 sheet; Organize is a second page inside it.
/// No Only on Wi‑Fi row (Q-M2); Only on Power Adapter on a Mac with a
/// battery.
struct MacBackupFormSheet: View {
    @Bindable var model: BackupFormModel
    var saved: (BackupJob) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MacDependencies.self) private var dependencies
    @State private var page = Page.main
    @State private var choosingFolder = false

    enum Page { case main, organize }

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .main: main
            case .organize:
                MacBackupOrganizePage(organize: $model.settings.organize, back: { page = .main },
                                      subtitle: organizeSubtitle, previewRoot: organizeRoot,
                                      affectsNewOnly: model.isEditing)
            }
        }
        .frame(width: 640, height: 560)
        .tint(MacTheme.accent)
        .sheet(isPresented: $choosingFolder) {
            if let server = model.connection {
                MacServerFolderPicker(server: server, password: dependencies.fileServers.password(for: server.id) ?? "",
                                      start: model.folder ?? server.folder) { model.folder = $0 }
            }
        }
        .onAppear {
            #if DEBUG
            // `-ShotDexSection backupOrganize`: the board's page, Day on Custom….
            if MacDemoLibrary.section == "backupOrganize" {
                model.settings.organize.dayStyle = .custom
                page = .organize
            }
            #endif
            // The Mac has no Only on Wi‑Fi row: every network will do (Q-M2).
            model.settings.onlyOnWiFi = false
            if !Self.hasBattery { model.settings.onlyWhileCharging = false }
        }
    }

    /// "Photos Library → NAS Home" under Organize's title.
    private var organizeSubtitle: String? {
        guard let source = model.sources.first(where: { $0.id == model.sourceId })?.name,
              let server = model.connection?.name else { return nil }
        return "\(source) → \(server)"
    }

    /// "Backup folder on NAS Home", the preview's top row.
    private var organizeRoot: String? {
        model.connection.map { String(localized: "Backup folder on \($0.name)", comment: "Organize preview: the backup's root folder on a server") }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isEditing
                     ? String(localized: "Edit Backup", comment: "Mac Backup sheet title: editing")
                     : String(localized: "New Backup", comment: "Mac Backup sheet title")).font(.headline)
                Text("Copies a whole library to a folder on your server and keeps it up to date.",
                     comment: "Mac New Backup: one-line explanation")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 12)
            Form {
                Section {
                    Picker(String(localized: "Source:", comment: "Mac New Backup: row label"), selection: Binding(
                        get: { model.sourceId ?? "" }, set: { model.choose(source: $0) })) {
                        ForEach(model.sources) { source in
                            Text(source.isOnline ? source.name
                                 : String(localized: "\(source.name) (Offline)", comment: "Mac New Backup: a source that is not connected"))
                                .tag(source.id)
                        }
                    }
                    .disabled(model.isEditing)
                    if !model.isPhotosSource {
                        Toggle(String(localized: "Back Up the Whole Source", comment: "Backup: the whole FS-19 source"),
                               isOn: Binding(get: { model.sourceFolder == "" }, set: { model.sourceFolder = $0 ? "" : nil }))
                    }
                }
                Section {
                    Picker(String(localized: "Connection:", comment: "Mac New Backup: row label"), selection: Binding(
                        get: { model.connectionId ?? "" }, set: { model.choose(connection: $0) })) {
                        ForEach(model.connections, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .disabled(model.isEditing)
                    LabeledContent(String(localized: "Folder:", comment: "Mac New Backup: row label")) {
                        HStack {
                            Button(String(localized: "Choose…", comment: "Mac New Backup: browse the server for a folder")) { choosingFolder = true }
                                .disabled(model.connection == nil)
                            Text(model.folder.map { $0.isEmpty ? "/" : $0 }
                                 ?? String(localized: "No folder chosen", comment: "Mac New Backup: no destination folder yet"))
                                .foregroundStyle(model.folder == nil ? .secondary : .primary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                } footer: {
                    Text("Photos already in this folder — from any device — are skipped.", comment: "Mac New Backup: destination footer")
                }
                Section {
                    LabeledContent(String(localized: "Organize:", comment: "Mac New Backup: row label")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(BackupOrganizeText.summary(model.settings.organize))
                                Text(BackupOrganizeText.sampleTree(model.settings.organize).replacingOccurrences(of: " › ", with: "/"))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let saved = model.editing?.settings.organize, saved != model.settings.organize {
                                    Text("Changing this affects new photos only. Photos already copied stay where they are.",
                                         comment: "Organize, Edit Backup: a change does not move what was copied (FS-22.01 §2)")
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer()
                            Button(String(localized: "Organize…", comment: "Mac New Backup: open the Organize page")) { page = .organize }
                        }
                    }
                }
                Section {
                    Picker(String(localized: "What to Copy:", comment: "Mac New Backup: row label"), selection: $model.settings.content) {
                        ForEach(BackupSettings.Content.allCases, id: \.self) { Text(BackupOrganizeText.content($0)).tag($0) }
                    }
                    Toggle(String(localized: "Include Edited Versions", comment: "Backup: also copy the edited version"),
                           isOn: $model.settings.includesEditedVersions)
                } footer: {
                    Text(model.summary).monospacedDigit()
                }
                if Self.hasBattery {
                    Section {
                        Toggle(String(localized: "Only on Power Adapter", comment: "Mac Backup: run only when plugged in"),
                               isOn: $model.settings.onlyWhileCharging)
                    } footer: {
                        Text("Not a one-time copy: after the first backup, every new photo and video is copied by itself.",
                             comment: "Mac New Backup: automatic backup footer")
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if model.duplicateError {
                    Text("This backup already exists.", comment: "Backup: same source, connection and folder").foregroundStyle(.red)
                } else if !model.canStart {
                    Text("Choose a folder to start.", comment: "Mac New Backup: why Start is off").foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.isEditing ? String(localized: "Save", comment: "Mac Backup sheet: save an edited job")
                                       : String(localized: "Start", comment: "Mac Backup sheet: create and start the job")) {
                    if let job = model.save() {
                        saved(job)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStart)
            }
            .padding(20)
        }
    }

    /// A MacBook, not a desktop: only then is there a power adapter to wait for.
    static var hasBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }
}

/// Choose a folder on a connection: one list of the current folder's
/// subfolders, Up, and Choose.
struct MacServerFolderPicker: View {
    let server: FileServer
    let password: String
    let start: String
    /// The client to list with — a locked one where other work shares the
    /// connection (FS-19.07 §5); nil makes a plain one.
    var client: (any RemoteFileClient)? = nil
    var chosen: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var folders: [String] = []
    @State private var error: String?
    @State private var isLoading = false
    @State private var listingClient: (any RemoteFileClient)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { go(to: (path as NSString).deletingLastPathComponent) } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel(String(localized: "Enclosing Folder", comment: "Mac folder picker: go up"))
                    .disabled(path.isEmpty || path == "/")
                Text(verbatim: "\(server.name) › \(path.isEmpty ? "/" : path)").font(.headline).lineLimit(1).truncationMode(.head)
            }
            List(folders, id: \.self) { name in
                Button { go(to: (path as NSString).appendingPathComponent(name)) } label: {
                    Label(name, systemImage: "folder")
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if isLoading { ProgressView() }
                if let error { Text(error).foregroundStyle(.secondary).padding() }
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Choose", comment: "Mac folder picker: use this folder")) {
                    chosen(path)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
        .task {
            let client = self.client ?? RemoteFileClientFactory.make(for: server, password: password)
            listingClient = client
            do { try await client.connect() } catch { self.error = error.localizedDescription }
            go(to: start)
        }
        .onDisappear { if let listingClient { Task { await listingClient.disconnect() } } }
    }

    private func go(to folder: String) {
        path = folder
        guard let client = listingClient else { return }
        isLoading = true
        Task {
            do {
                folders = try await client.folderNames(in: folder).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                error = nil
            } catch {
                folders = []
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
