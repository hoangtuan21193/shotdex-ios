import ShotDexKit
import SwiftUI

/// Export… of an edit made on server photos (FS-17.06 §6): pick one or more
/// places, say what happens to the original, run, and see what arrived.
/// Tier A — a form and a report, like the upload sheet.
struct ServerExportSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State var model: ServerExportModel
    /// Everything arrived (and Share, if chosen, was dismissed).
    var onFinished: () -> Void

    @State private var isConfirmingReplace = false
    @State private var isPickingFolder = false
    @State private var folderPath: [FolderPickerRoute] = []
    /// Choose Another Folder after a refusal, rather than the first pick.
    @State private var picksAfterRefusal = false

    var body: some View {
        NavigationStack(path: $folderPath) {
            content
                .navigationTitle(String(localized: "Export", comment: "Server export sheet title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(for: FolderPickerRoute.self) { route in
                    ServerBrowserScreen(model: route.model) { chosen in
                        pick(route, chosen)
                    }
                }
        }
        .interactiveDismissDisabled(model.stage == .exporting)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, model.stage == .exporting { model.cancel() }
        }
        .onChange(of: model.stage) { _, stage in
            guard stage == .done else { return }
            if model.report.shareFiles.isEmpty {
                onFinished()
            } else {
                // Last, over this sheet; the run ends when it closes.
                PhotoShareSheet.present(items: model.report.shareFiles, onFinished: onFinished)
            }
        }
        .alert(replaceTitle, isPresented: $isConfirmingReplace) {
            Button(String(localized: "Replace", comment: "Server export: confirm replacing originals"), role: .destructive) { model.export() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The originals are deleted and can't be recovered.", comment: "Server export: replace originals confirmation")
        }
        .confirmationDialog(
            String(localized: "Choose a Connection", comment: "Server export: pick the connection for Other Folder"),
            isPresented: $isPickingFolder
        ) {
            ForEach(dependencies.fileServerCatalog.servers) { server in
                Button(server.name) { openPicker(on: server) }
            }
        }
        .task { dependencies.fileServerCatalog.reload() }
    }

    private var replaceTitle: String {
        String(localized: "Replace ^[\(model.photos.count) original](inflect: true) on \(model.originServer.name)?",
               comment: "Server export: replace originals confirmation title")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch model.stage {
        case .choosing:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Export", comment: "Server export: run")) {
                    if model.needsReplaceConfirmation { isConfirmingReplace = true } else { model.export() }
                }
                .disabled(!model.canExport)
            }
        case .exporting:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { model.cancel() }
            }
        case .finishedWithFailures, .done:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .choosing: chooseForm
        case .exporting: progressForm
        case .finishedWithFailures, .done: resultForm
        }
    }

    // MARK: Choose

    private var chooseForm: some View {
        Form {
            Section {
                row(.originalFolder,
                    title: String(localized: "Original Folder", comment: "Server export destination"),
                    detail: "\(model.originServer.name) · \(model.originFolder.isEmpty ? "/" : model.originFolder)")
                row(.photosLibrary,
                    title: String(localized: "Photos Library", comment: "Server export destination"),
                    detail: String(localized: "A new photo with the edit. The original stays on the server.", comment: "Server export: Photos Library row detail"))
                otherFolderRow
                row(.share,
                    title: String(localized: "Share", comment: "Server export destination"),
                    detail: String(localized: "Opens after the others finish.", comment: "Server export: Share row detail"))
            } header: {
                Text("Save To", comment: "Server export: destinations section")
            }

            if let presets = model.resizePresets {
                Section {
                    Picker(String(localized: "Size", comment: "Server export: Resize preset"), selection: Binding(
                        get: { model.resizePreset?.id },
                        set: { id in model.resizePreset = presets.first { $0.id == id } }
                    )) {
                        ForEach(presets) { preset in
                            Text(preset.name).tag(Optional(preset.id))
                        }
                    }
                } footer: {
                    Text("The long side of each exported photo. The originals keep their size.", comment: "Server export: Resize footer")
                }
            }

            if model.destinations.contains(.originalFolder) {
                Section {
                    Picker(String(localized: "Original", comment: "Server export: what happens to the original"), selection: $model.placement) {
                        Text("Save as New File", comment: "Server export: keep the original, write _edited").tag(ServerEditPlacement.newFile)
                        Text("Replace Original", comment: "Server export: overwrite the original").tag(ServerEditPlacement.replaceOriginal)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(!model.canReplaceOriginals)
                } header: {
                    Text("In the Original Folder", comment: "Server export: placement section")
                } footer: {
                    if model.hasRAWOriginal {
                        Text("Originals in RAW stay — edits are saved as JPEG or HEIC.", comment: "Server export: why Replace Original is off")
                    } else if model.placement == .newFile {
                        Text("Saved next to the original with “_edited” added to the name.", comment: "Server export: new file naming")
                    }
                }
            }

            Section {
                Picker(String(localized: "Format", comment: "Server export: output format"), selection: $model.format) {
                    Text("JPEG").tag(ServerExportFormat.jpeg)
                    Text("HEIC").tag(ServerExportFormat.heic)
                }
                .pickerStyle(.segmented)
                .disabled(model.placement == .replaceOriginal && model.destinations.contains(.originalFolder))
            } footer: {
                Text("^[\(model.photos.count) photo](inflect: true) · \(model.format == .jpeg ? "JPEG" : "HEIC")",
                     comment: "Server export summary: photos and format")
            }
        }
    }

    private func row(_ choice: ServerExportModel.Choice, title: String, detail: String) -> some View {
        Button {
            model.toggle(choice)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if model.destinations.contains(choice) {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.destinations.contains(choice) ? .isSelected : [])
    }

    private var otherFolderRow: some View {
        Button {
            picksAfterRefusal = false
            if model.otherFolder == nil || !model.destinations.contains(.otherFolder) {
                isPickingFolder = true
            } else {
                model.toggle(.otherFolder)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Other Folder…", comment: "Server export destination").foregroundStyle(.primary)
                    Text(model.otherFolder.map { "\($0.server.name) · \($0.path.isEmpty ? "/" : $0.path)" }
                         ?? String(localized: "A folder on any saved connection.", comment: "Server export: Other Folder row detail"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if model.destinations.contains(.otherFolder) {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.destinations.contains(.otherFolder) ? .isSelected : [])
    }

    private func openPicker(on server: FileServer) {
        let session = ServerBrowseSession(server: server, client: RemoteFileClientFactory.make(
            for: server, password: dependencies.fileServers.password(for: server.id) ?? ""
        ))
        let dependencies = dependencies
        let picker = ServerBrowserModel(session: session, start: server.folder, mode: .chooseFolder) { path in
            ServerFolderModel(
                session: session,
                folder: path,
                cache: dependencies.serverThumbnails,
                downloads: dependencies.serverDownloads,
                existingAssetIds: { PhotoKitAssetCreator.existingAssetIds($0) }
            )
        }
        folderPath = [FolderPickerRoute(model: picker)]
    }

    private func pick(_ route: FolderPickerRoute, _ path: String) {
        folderPath = []
        let chosen = ServerExportModel.OtherFolder(server: route.model.server, path: path)
        if picksAfterRefusal {
            model.chooseAnotherFolder(chosen)
        } else {
            model.otherFolder = chosen
            model.destinations.insert(.otherFolder)
        }
        Task { await route.model.session.close() }
    }

    // MARK: Progress

    private var progressForm: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(model.progressLine.isEmpty
                         ? String(localized: "Preparing…", comment: "Server export: before the first render")
                         : model.progressLine)
                        .monospacedDigit()
                }
            } footer: {
                Text("Keep ShotDex open until the export finishes.", comment: "Server export: progress footer")
            }
        }
    }

    // MARK: Result

    private var resultForm: some View {
        Form {
            Section {
                ForEach(Array(model.report.outcomes.keys).sorted { $0.order < $1.order }) { destination in
                    resultRow(destination)
                }
            } footer: {
                if model.stage == .finishedWithFailures {
                    Text("Your edits are still here. Try again, or choose another place.", comment: "Server export: some destinations failed")
                }
            }
            if model.stage == .finishedWithFailures {
                Section {
                    Button(String(localized: "Retry Failed", comment: "Server export: run the failed destinations again")) {
                        model.retryFailed()
                    }
                    if model.hasPermissionDenied {
                        Button(String(localized: "Choose Another Folder", comment: "Server export: the server refused the write")) {
                            picksAfterRefusal = true
                            isPickingFolder = true
                        }
                    }
                }
            }
        }
    }

    private func resultRow(_ destination: ServerExportDestination) -> some View {
        let outcomes = model.photos.compactMap { model.report.outcome(destination, $0.id) }
        let failure = outcomes.first { if case .done = $0 { false } else { true } }
        return HStack(alignment: .firstTextBaseline) {
            Image(systemName: failure == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(failure == nil ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title(of: destination))
                switch failure {
                case .permissionDenied?:
                    Text("You can't write to this folder.", comment: "Server export: the server refused the write")
                        .font(.footnote).foregroundStyle(.secondary)
                case .failed(let reason)?:
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
