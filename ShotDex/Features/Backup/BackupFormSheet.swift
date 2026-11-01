import SwiftUI

/// New Backup / Edit (FS-22.01 §2, board `PH_BackupNew` 2/5).
struct BackupFormSheet: View {
    @State var model: BackupFormModel
    /// Called with the saved job; the list starts it.
    var onSaved: (BackupJob) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.appAccent) private var accent
    @State private var path: [Route] = []

    enum Route: Hashable {
        case organize
        case customMonth
        case customDay
        case serverFolder(FolderPickerRoute)
        case sourceFolder(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                sourceSection
                destinationSection
                organizeSection
                contentSection
                whenSection
            }
            .navigationTitle(model.isEditing
                ? String(localized: "Edit Backup", comment: "Backup form title when editing")
                : String(localized: "New Backup", comment: "Backup form title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Backup form: close without saving")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing
                        ? String(localized: "Save", comment: "Backup form: save changes")
                        : String(localized: "Start", comment: "Backup form: create the job and start it")) {
                        if let job = model.save() {
                            onSaved(job)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canStart)
                    .accessibilityLabel(model.isEditing
                        ? String(localized: "Save Backup", comment: "VoiceOver: save the backup form")
                        : String(localized: "Start Backup", comment: "VoiceOver: start the backup"))
                }
            }
            .alert(String(localized: "This backup already exists.", comment: "Backup form: same source, connection and folder"), isPresented: $model.duplicateError) {
                Button(String(localized: "OK", comment: "Dismiss alert"), role: .cancel) {}
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .organize:
                    BackupOrganizeScreen(settings: $model.settings, previewRoot: previewRoot) { path.append($0 == .month ? .customMonth : .customDay) }
                case .customMonth:
                    BackupCustomDateScreen(organize: $model.settings.organize, part: .month, previewRoot: previewRoot)
                case .customDay:
                    BackupCustomDateScreen(organize: $model.settings.organize, part: .day, previewRoot: previewRoot)
                case .sourceFolder(let path):
                    BackupSourceFolderScreen(sourceId: model.sourceId ?? "", folder: path, sourceName: model.source?.name ?? "") { chosen in
                        model.sourceFolder = chosen
                        self.path = []
                    } open: { child in
                        self.path.append(.sourceFolder(child))
                    } close: {
                        self.path = []
                    }
                case .serverFolder(let route):
                    ServerBrowserScreen(model: route.model) { chosen in
                        path = []
                        model.folder = chosen
                        Task { await route.model.session.close() }
                    }
                }
            }
        }
    }

    private var previewRoot: String {
        String(localized: "\(model.folder.map { $0.isEmpty ? "/" : $0 } ?? String(localized: "Backup folder", comment: "Organize preview: root when no folder is chosen yet"))  ·  on \(model.connection?.name ?? "")", comment: "Organize preview: the root line of the folder tree")
    }

    // MARK: Sections

    private var sourceSection: some View {
        Section(String(localized: "Source", comment: "Backup form section")) {
            ForEach(model.sources) { option in
                Button {
                    model.choose(source: option.id)
                } label: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Label(option.name, systemImage: option.systemImage)
                            .foregroundStyle(option.isOnline ? .primary : .secondary)
                        Spacer()
                        Text(option.isOnline
                            ? option.count.formatted()
                            : String(localized: "Offline", comment: "Backup form: a source that is not connected"))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: "checkmark")
                            .foregroundStyle(accent)
                            .opacity(model.sourceId == option.id ? 1 : 0)
                    }
                }
                .tint(.primary)
                .disabled(model.isEditing && model.sourceId != option.id)
                .accessibilityAddTraits(model.sourceId == option.id ? .isSelected : [])
            }
            if !model.isPhotosSource, model.sourceId != nil {
                NavigationLink(value: Route.sourceFolder("")) {
                    LabeledContent(String(localized: "Folder", comment: "Backup form row: which folder of the source is backed up")) {
                        chooseValue(model.sourceFolder.map { $0.isEmpty ? String(localized: "Whole Source", comment: "Backup form: the entire folder or drive source") : $0 })
                    }
                }
            }
        }
    }

    /// The chosen value, or a tinted "Choose…" while nothing is chosen.
    @ViewBuilder
    private func chooseValue(_ value: String?) -> some View {
        if let value {
            Text(value).lineLimit(1).truncationMode(.head)
        } else {
            // The rows tint themselves .primary; the accent is set outright.
            Text(String(localized: "Choose…", comment: "Backup form: nothing chosen yet")).foregroundStyle(accent)
        }
    }

    private var destinationSection: some View {
        Section {
            if model.connections.isEmpty {
                NavigationLink {
                    FileServerFormScreen(draft: FileServerDraft()) { saved in
                        model.reloadChoices()
                        model.choose(connection: saved.id)
                    }
                } label: {
                    Text(String(localized: "Add a Server", comment: "Backup form: no connection yet"))
                }
            } else {
                Picker(String(localized: "Connection", comment: "Backup form row: which server"), selection: Binding(
                    get: { model.connectionId ?? "" },
                    set: { model.choose(connection: $0) }
                )) {
                    ForEach(model.connections) { server in
                        Text(server.name).tag(server.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isEditing)

                Button {
                    browseFolder()
                } label: {
                    LabeledContent(String(localized: "Folder", comment: "Backup form row: folder on the server")) {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            chooseValue(model.folder.map { $0.isEmpty ? "/" : $0 })
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .tint(.primary)
                .disabled(model.connection == nil)
            }
        } header: {
            Text(String(localized: "Destination", comment: "Backup form section"))
        } footer: {
            // FS-22.05 §1: duplicates are matched across the whole folder.
            Text(String(localized: "Photos already in this folder — from another iPhone or copied earlier — are skipped.", comment: "Backup form: footer under the destination folder"))
        }
    }

    private var organizeSection: some View {
        Section {
            NavigationLink(value: Route.organize) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Organize", comment: "Backup form row: how folders are laid out"))
                    Text(BackupOrganizeText.summary(model.settings.organize))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(String(localized: "Folders on \(model.connection?.name ?? "")", comment: "Backup form section header"))
        } footer: {
            Text(String(localized: "\(BackupOrganizeText.sampleTree(model.settings.organize)). Tap Organize to change the folders, the names and where videos and RAW files go.", comment: "Backup form footer: an example path"))
        }
    }

    private var contentSection: some View {
        Section {
            ForEach(BackupSettings.Content.allCases, id: \.self) { content in
                Button {
                    model.settings.content = content
                } label: {
                    HStack {
                        Text(BackupOrganizeText.content(content))
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundStyle(accent)
                            .opacity(model.settings.content == content ? 1 : 0)
                    }
                }
                .tint(.primary)
                .accessibilityAddTraits(model.settings.content == content ? .isSelected : [])
            }
            Toggle(String(localized: "Include Edited Versions", comment: "Backup form switch: also copy the edited render"), isOn: $model.settings.includesEditedVersions)
        } header: {
            Text(String(localized: "What to Copy", comment: "Backup form section"))
        } footer: {
            Text("\(model.summary). \(String(localized: "Full-size originals, RAW included; iCloud photos download first.", comment: "Backup form footer"))")
        }
    }

    private var whenSection: some View {
        Section {
            Toggle(String(localized: "Only on Wi‑Fi", comment: "Backup form switch"), isOn: $model.settings.onlyOnWiFi)
            Toggle(String(localized: "Only While Charging", comment: "Backup form switch"), isOn: $model.settings.onlyWhileCharging)
        } header: {
            Text(String(localized: "Automatic Backup", comment: "Backup form section: the job keeps running on its own"))
        } footer: {
            Text(String(localized: "Not a one-time copy: after the first backup, every new photo and video is copied to the server by itself. You don't need to start it again.", comment: "Backup form footer: explains continuous backup"))
        }
    }

    private func browseFolder() {
        guard let server = model.connection else { return }
        let session = ServerBrowseSession(server: server, client: RemoteFileClientFactory.make(
            for: server, password: dependencies.fileServers.password(for: server.id) ?? ""
        ))
        let dependencies = dependencies
        let picker = ServerBrowserModel(session: session, start: model.folder ?? server.folder, mode: .chooseFolder) { folder in
            ServerFolderModel(
                session: session, folder: folder, cache: dependencies.serverThumbnails,
                downloads: dependencies.serverDownloads,
                existingAssetIds: { PhotoKitAssetCreator.existingAssetIds($0) }
            )
        }
        path.append(.serverFolder(FolderPickerRoute(model: picker)))
    }
}
