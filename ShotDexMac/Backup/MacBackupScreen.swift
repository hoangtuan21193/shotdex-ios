import SwiftUI

/// Backup on the Mac (board `MAC_Backup`, FS-22.06 §5.2): the jobs as rows,
/// the selected job's progress in the inspector. 1/5 and 5/5 of iOS in one
/// window.
struct MacBackupScreen: View {
    @Environment(MacDependencies.self) private var dependencies
    @Binding var showsInspector: Bool
    @Binding var opensNewBackup: Bool
    @State private var selection: String?
    @State private var form: BackupFormModel?
    @State private var deleting: BackupJob?
    /// Bumped when a connection is added, so the empty state and + redraw.
    @State private var serversVersion = 0

    private var coordinator: BackupCoordinator { dependencies.backupCoordinator }

    var body: some View {
        let _ = serversVersion
        Group {
            if coordinator.jobs.isEmpty {
                empty
            } else {
                list
            }
        }
        .navigationTitle(String(localized: "Backup", comment: "Mac Backup: window title"))
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .inspector(isPresented: $showsInspector) {
            Group {
                if let job = selectedJob {
                    MacBackupInspector(job: job, edit: { openForm(editing: job) })
                } else {
                    Text("No Backup Selected", comment: "Mac Backup inspector: nothing selected")
                        .foregroundStyle(.secondary)
                }
            }
            .inspectorColumnWidth(MacWindowMetrics.inspectorWidth)
        }
        .sheet(item: $form) { model in
            MacBackupFormSheet(model: model) { job in
                coordinator.jobsChanged(start: model.editing == nil ? job.id : nil)
                selection = job.id
            }
        }
        .confirmationDialog(
            String(localized: "Delete this backup?", comment: "Backup: confirm deleting a job"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { job in
            Button(String(localized: "Delete Backup", comment: "Backup: delete the job"), role: .destructive) {
                coordinator.pause(job.id)
                try? dependencies.backups.delete(id: job.id)
                coordinator.jobsChanged()
            }
        } message: { _ in
            Text(String(localized: "Files already on the server stay there.", comment: "Backup: deleting a job deletes nothing on the server"))
        }
        .onAppear {
            coordinator.reload()
            coordinator.sourcesTick()
            if selection == nil { selection = coordinator.jobs.first?.id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macServersChanged)) { _ in serversVersion += 1 }
        .onChange(of: opensNewBackup, initial: true) { _, opens in
            guard opens else { return }
            opensNewBackup = false
            if dependencies.fileServers.hasConnections { openForm(editing: nil) }
        }
    }

    private var selectedJob: BackupJob? {
        coordinator.jobs.first { $0.id == selection }
    }

    /// "3 backups · each one watches its source".
    private var subtitle: String {
        let count = coordinator.jobs.count
        guard count > 0 else { return "" }
        return count == 1
            ? String(localized: "1 backup · it watches its source", comment: "Mac Backup: toolbar subtitle, one job")
            : String(localized: "\(count) backups · each one watches its source", comment: "Mac Backup: toolbar subtitle")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(coordinator.jobs) { job in
                    MacBackupRow(job: job, perform: { perform($0, job: job) })
                        .tag(job.id)
                        .contextMenu { menu(for: job) }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            footer
        }
    }

    /// FS-22.06 §5.2: the line says what Quit does today. The helper that
    /// keeps going after Quit is not built yet, so Quit stops the jobs.
    private var footer: some View {
        Label(String(localized: "Backups stop when you quit ShotDex.", comment: "Mac Backup: the jobs run only while the app is open"),
              systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(String(localized: "No Backups", comment: "Mac Backup: empty state title"), systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Back up a whole library to your NAS.", comment: "Backup: empty state")
        } actions: {
            if dependencies.fileServers.hasConnections {
                Button(String(localized: "New Backup…", comment: "Mac Backup: create a job")) { openForm(editing: nil) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(String(localized: "Add a Server…", comment: "Mac Backup: no connection yet")) {
                    NotificationCenter.default.post(name: .macAddServer, object: nil)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private func menu(for job: BackupJob) -> some View {
        Button(String(localized: "Edit…", comment: "Mac Backup: edit a job")) { openForm(editing: job) }
        Button(String(localized: "Back Up Now", comment: "Backup: compare the whole source now")) { coordinator.backUpNow(job.id) }
        if coordinator.states[job.id]?.status == .pausedByUser {
            Button(BackupStatusText.Action.resume.title) { coordinator.resume(job.id) }
        } else {
            Button(BackupStatusText.Action.pause.title) { coordinator.pause(job.id) }
        }
        Divider()
        Button(String(localized: "Delete Backup…", comment: "Mac Backup: delete a job"), role: .destructive) { deleting = job }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if let id = selection { coordinator.backUpNow(id) }
            } label: {
                Label(String(localized: "Back Up Now", comment: "Backup: compare the whole source now"), systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(selection == nil)
            if let id = selection, coordinator.states[id]?.status == .pausedByUser {
                Button { coordinator.resume(id) } label: {
                    Label(BackupStatusText.Action.resume.title, systemImage: "play.fill")
                }
            } else {
                Button { if let id = selection { coordinator.pause(id) } } label: {
                    Label(BackupStatusText.Action.pause.title, systemImage: "pause.fill")
                }
                .disabled(selection == nil)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showsInspector.toggle() } label: {
                Label(String(localized: "Show Inspector", comment: "Mac toolbar"), systemImage: "sidebar.right")
            }
            Button { openForm(editing: nil) } label: {
                Label(String(localized: "New Backup…", comment: "Mac Backup: create a job"), systemImage: "plus")
            }
            .disabled(!dependencies.fileServers.hasConnections)
        }
    }

    private func perform(_ action: BackupStatusText.Action, job: BackupJob) {
        switch action {
        case .pause: coordinator.pause(job.id)
        case .resume: coordinator.resume(job.id)
        case .retry: coordinator.retry(job.id)
        case .openSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                NSWorkspace.shared.open(url)
            }
        case .editServer: NotificationCenter.default.post(name: .macAddServer, object: job.connectionId)
        }
    }

    private func openForm(editing job: BackupJob?) {
        form = BackupFormModel(database: dependencies.database, store: dependencies.backups,
                               servers: dependencies.fileServers, editing: job)
    }
}

extension BackupFormModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension FileServerStore {
    var hasConnections: Bool { ((try? count()) ?? 0) > 0 }
}

extension Notification.Name {
    /// File › New Backup… (FS-22.06 §5.1).
    static let macNewBackup = Notification.Name("ShotDexMacNewBackup")
    /// Add a Server… — object: a connection id to edit, or nil for a new one.
    static let macAddServer = Notification.Name("ShotDexMacAddServer")
    /// Go › Backup ⌥⌘B (FS-22.06 §5.1).
    static let macShowBackup = Notification.Name("ShotDexMacShowBackup")
    /// A connection was added or edited — screens that read the list redraw.
    static let macServersChanged = Notification.Name("ShotDexMacServersChanged")
}

/// One job (board `MAC_Backup`): the status glyph, `source → connection`,
/// folder and content, the status lines on the right, the one action that
/// fits.
struct MacBackupRow: View {
    let job: BackupJob
    var perform: (BackupStatusText.Action) -> Void
    @Environment(MacDependencies.self) private var dependencies

    var body: some View {
        let info = MacBackupJobInfo(job: job, dependencies: dependencies)
        let status = info.status
        HStack(spacing: 12) {
            MacBackupGlyph(status: status)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(info.sourceName) → \(info.connectionName)").font(.headline).lineLimit(1)
                Text(info.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(status.title).font(.subheadline.weight(.semibold)).foregroundStyle(status.tone.macColor)
                Text(status.detail).font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            if let action = status.action, action != .pause {
                Button(action.title) { perform(action) }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(info.sourceName) → \(info.connectionName), \(status.title), \(status.detail)")
    }
}

/// The ring, check or warning at the start of a row.
struct MacBackupGlyph: View {
    let status: BackupStatusText

    var body: some View {
        Group {
            if let fraction = status.fraction {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 3)
                    Circle().trim(from: 0, to: fraction).stroke(MacTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                Image(systemName: status.tone == .attention ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(status.tone == .attention ? Color.orange : MacTheme.accent)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// Names and the status text of a job, read from the coordinator and stores.
@MainActor
struct MacBackupJobInfo {
    let sourceName: String
    let connectionName: String
    let subtitle: String
    let status: BackupStatusText

    init(job: BackupJob, dependencies: MacDependencies) {
        let coordinator = dependencies.backupCoordinator
        if job.sourceId == PhotoLibrarySource.id {
            sourceName = String(localized: "Photos Library", comment: "Backup source: the Photos library")
        } else {
            sourceName = (try? dependencies.sources.sources())?.first { $0.id == job.sourceId }?.name
                ?? String(localized: "Source", comment: "Backup: a source whose name is unknown")
        }
        connectionName = (try? dependencies.fileServers.fetch(id: job.connectionId))?.name
            ?? String(localized: "Server", comment: "Backup: a connection whose name is unknown")
        let content = switch job.settings.content {
        case .photosAndVideos: String(localized: "Photos & Videos", comment: "Backup: what the job copies")
        case .photosOnly: String(localized: "Photos Only", comment: "Backup: what the job copies")
        case .videosOnly: String(localized: "Videos Only", comment: "Backup: what the job copies")
        }
        subtitle = "\(job.folder) · \(content)"
        status = BackupStatusText.make(BackupStatusText.Input(
            state: coordinator.states[job.id] ?? BackupJobState(jobId: job.id),
            progress: coordinator.runningJobId == job.id ? coordinator.progress[job.id] : nil,
            backedUpItems: coordinator.backedUpItems[job.id] ?? 0,
            connectionName: connectionName,
            sourceName: sourceName,
            bytesPerSecond: coordinator.bytesPerSecond[job.id]
        ))
    }
}

extension BackupStatusText.Tone {
    var macColor: Color {
        switch self {
        case .ok, .active, .waiting: .primary
        case .attention: .orange
        }
    }
}
