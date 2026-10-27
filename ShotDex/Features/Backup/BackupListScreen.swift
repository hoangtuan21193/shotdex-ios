import SwiftUI

/// Navigation value for the Backup screen (Collections › Utilities).
struct BackupScreenDestination: Hashable {}

/// Backup (FS-22.01 §1, board `PH_Backup` 1/5): one card per job with its
/// status line. Compact width pushes a job's detail; regular width of 1000pt
/// and more shows the selected job beside the list (`IP_Backup`); the Duo's
/// inner screen lays the cards two to a row (`DI_Backup`).
struct BackupListScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL

    @State private var form: BackupFormModel?
    @State private var deleting: BackupJob?
    @State private var selectedJobId: String?
    @State private var editingServer: FileServer?

    private var coordinator: BackupCoordinator { dependencies.backupCoordinator }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Group {
                if coordinator.jobs.isEmpty {
                    emptyState
                } else if sizeClass == .regular, width >= 1000 {
                    split(width: width)
                } else {
                    cards(columns: sizeClass == .regular ? 2 : 1, selectable: false)
                }
            }
        }
        .navigationTitle(String(localized: "Backup", comment: "Backup screen title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openForm(editing: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "New Backup", comment: "Backup: add a job"))
                .disabled(dependencies.fileServerCatalog.servers.isEmpty && coordinator.jobs.isEmpty)
            }
        }
        .sheet(item: $form) { model in
            BackupFormSheet(model: model) { job in
                coordinator.jobsChanged(start: job.id)
                selectedJobId = job.id
            }
            .modifier(BackupSheetSizing())
        }
        .sheet(item: $editingServer) { server in
            NavigationStack { FileServerFormScreen(draft: FileServerDraft(server: server)) }
        }
        .confirmationDialog(
            String(localized: "Delete this backup?", comment: "Backup: confirm deleting a job"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
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
        .navigationDestination(for: BackupJobRoute.self) { route in
            BackupRunningScreen(jobId: route.jobId)
        }
        .onAppear {
            coordinator.reload()
            coordinator.sourcesTick()
            dependencies.fileServerCatalog.reload()
        }
    }

    // MARK: Layouts

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Backups", comment: "Backup: empty state title"), systemImage: "clock.arrow.circlepath")
        } description: {
            Text(String(localized: "Back up a whole library to your NAS.", comment: "Backup: empty state line"))
        } actions: {
            if dependencies.fileServerCatalog.servers.isEmpty {
                NavigationLink {
                    FileServerFormScreen(draft: FileServerDraft()) { _ in dependencies.fileServerCatalog.reload() }
                } label: {
                    Text(String(localized: "Add a Server", comment: "Backup: no connection yet"))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(String(localized: "New Backup", comment: "Backup: add a job")) { openForm(editing: nil) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private func cards(columns: Int, selectable: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.lg, alignment: .top), count: columns),
                          alignment: .leading, spacing: AppTheme.Spacing.md) {
                    ForEach(coordinator.jobs) { job in
                        card(job, selectable: selectable)
                    }
                }
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
            .padding(.horizontal, AppTheme.Size.screenMargin)
            .padding(.bottom, AppTheme.Spacing.xxl * 2)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func split(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            cards(columns: 1, selectable: true)
                .frame(width: 440 + AppTheme.Size.screenMargin * 2)
            Group {
                if let id = selectedJobId ?? coordinator.jobs.first?.id {
                    BackupRunningScreen(jobId: id, isEmbedded: true)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }

    @ViewBuilder
    private func card(_ job: BackupJob, selectable: Bool) -> some View {
        let content = BackupJobCard(job: job, isSelected: selectable && (selectedJobId ?? coordinator.jobs.first?.id) == job.id) { action in
            perform(action, job: job)
        }
        .contextMenu {
            Button { openForm(editing: job) } label: {
                Label(String(localized: "Edit", comment: "Backup: edit a job"), systemImage: "pencil")
            }
            Button { coordinator.backUpNow(job.id) } label: {
                Label(String(localized: "Back Up Now", comment: "Backup: compare the source now"), systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) { deleting = job } label: {
                Label(String(localized: "Delete Backup", comment: "Backup: delete the job"), systemImage: "trash")
            }
        }
        if selectable {
            Button { selectedJobId = job.id } label: { content }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: BackupJobRoute(jobId: job.id)) { content }
                .buttonStyle(.plain)
        }
    }

    /// Every layout says where Edit, Back Up Now and Delete are: the long
    /// press is their only way in, pushed on a phone or the Duo as much as
    /// selected in the iPad split.
    private var footnote: String {
        let base = String(localized: "Each backup watches its source and copies new photos and videos as they appear — full-size originals, downloaded from iCloud first when needed. Photos already in the destination folder — copied by another phone or by hand — are skipped, and a stopped backup picks up where it left off.", comment: "Backup screen footnote")
        return base + " " + String(localized: "Long-press a backup to edit, back up now or delete it.", comment: "Backup footnote: where the job actions are")
    }

    private func perform(_ action: BackupStatusText.Action, job: BackupJob) {
        switch action {
        case .pause: coordinator.pause(job.id)
        case .resume: coordinator.resume(job.id)
        case .retry: coordinator.retry(job.id)
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        case .editServer:
            editingServer = try? dependencies.fileServers.fetch(id: job.connectionId)
        }
    }

    private func openForm(editing job: BackupJob?) {
        form = BackupFormModel(database: dependencies.database, store: dependencies.backups, servers: dependencies.fileServers, editing: job)
    }
}

struct BackupJobRoute: Hashable {
    let jobId: String
}

extension BackupFormModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// One job: source → connection, folder and content, a bar while there is
/// one, the status lines and the one action that fits (board `PH_Backup`).
struct BackupJobCard: View {
    let job: BackupJob
    var isSelected = false
    var perform: (BackupStatusText.Action) -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appAccent) private var accent

    var body: some View {
        let info = BackupJobInfo(job: job, dependencies: dependencies)
        let status = info.status
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                // One line where it fits; on the Duo cover the destination
                // drops to its own line rather than cutting either name.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Label(info.sourceName, systemImage: info.sourceImage).fixedSize()
                        Image(systemName: "arrow.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        Label(info.connectionName, systemImage: "server.rack").fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label(info.sourceName, systemImage: info.sourceImage).lineLimit(1)
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Image(systemName: "arrow.turn.down.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            Label(info.connectionName, systemImage: "server.rack").lineLimit(1)
                        }
                    }
                }
                .labelStyle(BackupTitleLabelStyle())
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.headline)
            Text(info.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let fraction = status.fraction {
                ProgressView(value: fraction)
            }
            HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status.tone.color)
                    Text(status.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                if let action = status.action {
                    Button {
                        perform(action)
                    } label: {
                        Text(action.title).frame(minHeight: AppTheme.Size.minTouch - 14)
                    }
                    .buttonStyle(.bordered)
                    // Every card has one; none of them is the screen's main
                    // action, so none gets the accent (DESIGN.md §3.1).
                    .tint(.primary)
                    .buttonBorderShape(.capsule)
                    // 44pt to the finger everywhere; drawn that big where there is room.
                    .controlSize(sizeClass == .regular ? .large : .regular)
                    .contentShape(Capsule().inset(by: -6))
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
        .overlay {
            if isSelected {
                RoundedRectangle.app(AppTheme.Radius.lg).strokeBorder(accent, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle.app(AppTheme.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(info.sourceName) → \(info.connectionName), \(status.title), \(status.detail)")
    }
}

/// Names and the status text of a job, read from the coordinator and stores.
@MainActor
struct BackupJobInfo {
    let sourceName: String
    let sourceImage: String
    let connectionName: String
    let subtitle: String
    let status: BackupStatusText

    init(job: BackupJob, dependencies: AppDependencies) {
        let coordinator = dependencies.backupCoordinator
        if job.sourceId == PhotoLibrarySource.id {
            sourceName = String(localized: "Photos Library", comment: "Backup source: the Photos library")
            sourceImage = "photo.on.rectangle"
        } else {
            let source = (try? SourceStore(database: dependencies.database).sources())?.first { $0.id == job.sourceId }
            sourceName = source?.name ?? String(localized: "Source", comment: "Backup: a source whose name is unknown")
            sourceImage = switch source?.kind {
            case "drive": "externaldrive"
            case "server": "server.rack"
            default: "folder"
            }
        }
        connectionName = dependencies.fileServerCatalog.servers.first { $0.id == job.connectionId }?.name
            ?? String(localized: "Server", comment: "Backup: a connection whose name is unknown")
        let content = switch job.settings.content {
        case .photosAndVideos: String(localized: "Photos & videos, full size", comment: "Backup card: what the job copies")
        case .photosOnly: String(localized: "Photos only", comment: "Backup card: what the job copies")
        case .videosOnly: String(localized: "Videos only", comment: "Backup card: what the job copies")
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
    var color: Color {
        switch self {
        case .ok: .green
        case .active: .secondary
        case .waiting: .secondary
        case .attention: .orange
        }
    }
}

extension BackupStatusText.Action {
    var title: String {
        switch self {
        case .pause: String(localized: "Pause", comment: "Backup: pause the job")
        case .resume: String(localized: "Resume", comment: "Backup: resume the job")
        case .retry: String(localized: "Retry", comment: "Backup: try again")
        case .openSettings: String(localized: "Open Settings", comment: "Backup: open the Settings app")
        case .editServer: String(localized: "Edit Server", comment: "Backup: fix the connection")
        }
    }
}

/// Icon in secondary, name in primary — the card title's two names.
private struct BackupTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            configuration.icon.foregroundStyle(.secondary)
            configuration.title
        }
    }
}

/// On iPad the form gets a page-sized sheet so Organize shows without
/// scrolling; phones keep the full-height sheet.
private struct BackupSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.large])
        }
    }
}
