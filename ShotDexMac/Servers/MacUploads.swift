import SwiftUI

/// A finished (or paused) upload as it is kept across launches: enough to
/// say what happened and to send the same photos again (FS-15.02 §9).
struct MacUploadRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let serverId: String?
    let serverName: String
    let startedAt: Date
    let endedAt: Date
    /// The row's result line, as it read when it ended.
    let line: String
    let isTrouble: Bool
    let wasPaused: Bool
    /// How many library photos it sent (none for files picked on the Mac).
    /// Their ids sit in a file of their own (`MacUploads.photoIds(of:)`):
    /// a 55k batch must not ride in the preferences read at launch.
    let photoCount: Int
    /// Where it went, so Upload Again… sends to the same place.
    var folder: String? = nil
    var usesDateFolders = false
}

/// Uploads under way and just finished (FS-15.02 §9, board `MAC_ServerUpload`):
/// owned by the app, not by a sheet, so the Library window stays usable and
/// closing a window does not stop one. The Activity popover lists them.
@MainActor
@Observable
final class MacUploads {
    struct Entry: Identifiable {
        let id = UUID()
        let model: ServerUploadModel
        let serverName: String
        let startedAt = Date()
    }

    /// Newest first.
    private(set) var entries: [Entry] = []
    /// Rows from earlier launches (and this one's, once ended), newest first, at most 20.
    private(set) var records: [MacUploadRecord] = []
    @ObservationIgnored private let defaults: UserDefaults
    /// One file of photo ids per kept row.
    @ObservationIgnored private let idsFolder: URL
    private static let recordsKey = "macUploadRecords"
    /// Batches the user stopped (Pause, Stop, Quit): kept as "Stopped", not as trouble.
    @ObservationIgnored private var userStoppedIds: Set<UUID> = []
    /// Upload Again… asked from Activity: the front Library window opens the sheet when it can.
    var againRequest: MacUploadRequest?

    init(defaults: UserDefaults = .standard, idsFolder: URL? = nil) {
        self.defaults = defaults
        self.idsFolder = idsFolder ?? URL.applicationSupportDirectory.appending(path: "ShotDex/UploadRecords", directoryHint: .isDirectory)
        // One by one: a row that no longer reads does not take the others with it.
        if let data = defaults.data(forKey: Self.recordsKey),
           let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            records = array.compactMap { element in
                guard let one = try? JSONSerialization.data(withJSONObject: element) else { return nil }
                return try? JSONDecoder().decode(MacUploadRecord.self, from: one)
            }
        }
    }

    /// The photo ids a kept row sent, read off the main actor.
    func photoIds(of record: MacUploadRecord) async -> [String] {
        let file = idsFolder.appending(path: "\(record.id.uuidString).json")
        return await Task.detached(priority: .userInitiated) {
            (try? JSONDecoder().decode([String].self, from: Data(contentsOf: file))) ?? []
        }.value
    }

    /// Stop from the row: the batch ends as the user's choice, not as trouble.
    func stop(_ id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        userStoppedIds.insert(id)
        entry.model.cancel()
    }

    /// The kept rows not shown live: those of earlier launches.
    var history: [MacUploadRecord] {
        let live = Set(entries.map(\.id))
        return records.filter { !live.contains($0.id) }
    }

    func forget(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
        let file = idsFolder.appending(path: "\(id.uuidString).json")
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.recordsKey) }
    }

    /// Writes the row down once its batch ends — again after each Resume.
    private func keep(_ entry: Entry) {
        Task { @MainActor [weak self] in
            while entry.model.stage != .finished { try? await Task.sleep(for: .seconds(1)) }
            self?.record(entry)
        }
    }

    /// The row as it stands, kept: at the start (so a quit or a crash still
    /// leaves it), at Stop and Quit, and when the batch ends.
    func record(_ entry: Entry) {
        guard entries.contains(where: { $0.id == entry.id }) else { return }
        let model = entry.model
        let summary = model.summary
        let isOver = model.stage == .finished
        let sent = (carried[entry.id]?.sent ?? 0) + model.fileOutcomes.values.filter(\.isOnServer).count
        // A batch the user stopped (Pause, Stop, Quit) or that is still going at a quit is not an error;
        // failed files and a server error are.
        let stopped = !isOver || isPaused(entry) || userStoppedIds.contains(entry.id)
        let trouble = !stopped && (!summary.failures.isEmpty || summary.stopMessage != nil)
        var parts: [String] = []
        if stopped {
            parts.append(isOver ? String(localized: "Stopped", comment: "Mac Activity kept upload: stopped by the user or a quit")
                                : String(localized: "Didn’t finish", comment: "Mac Activity kept upload: ShotDex quit while it ran"))
        }
        parts.append(String(AttributedString(localized: "^[\(sent) file](inflect: true) sent", comment: "Mac Activity kept upload: what went up").characters))
        if !summary.failures.isEmpty {
            parts.append(String(AttributedString(localized: "^[\(summary.failures.count) file](inflect: true) failed", comment: "Mac Activity kept upload: files that didn't go").characters))
        }
        if trouble, summary.failures.isEmpty, let reason = summary.stopMessage { parts.append(reason) }
        let photoIds = model.assetIds.filter { !$0.hasPrefix("file:") }
        if stopped || trouble, photoIds.isEmpty {
            parts.append(String(localized: "add the files again to send the rest", comment: "Mac Activity kept upload of Mac files: no Upload Again"))
        }
        let record = MacUploadRecord(id: entry.id, serverId: model.selectedServerId, serverName: entry.serverName,
                                     startedAt: entry.startedAt, endedAt: Date(), line: parts.joined(separator: " · "),
                                     isTrouble: trouble, wasPaused: stopped,
                                     photoCount: photoIds.count, folder: model.folder, usesDateFolders: model.usesDateFolders)
        // The ids once, off the main actor: they do not change for a batch.
        let folder = idsFolder
        let file = folder.appending(path: "\(entry.id.uuidString).json")
        Task.detached(priority: .utility) {
            guard !photoIds.isEmpty, !FileManager.default.fileExists(atPath: file.path) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? JSONEncoder().encode(photoIds).write(to: file, options: .atomic)
        }
        records.removeAll { $0.id == entry.id }
        records.insert(record, at: 0)
        if records.count > 20 { records.removeLast(records.count - 20) }
        save()
    }

    /// Batches the user paused: stopped between files, Resume sends the rest.
    private(set) var pausedIds: Set<UUID> = []
    /// What a batch had before Resume restarted it on the rest: files sent
    /// and its whole size, so counts read for the whole job.
    private(set) var carried: [UUID: (sent: Int, total: Int)] = [:]

    /// Pause: the batch stops now; the file in flight is cleaned off the
    /// server and starts over on Resume; what is up stays up. Not while an
    /// already-there question waits — stopping would answer it Skip.
    func pause(_ id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }), entry.model.stage == .uploading,
              entry.model.pendingConflict == nil else { return }
        pausedIds.insert(id)
        userStoppedIds.insert(id)
        entry.model.cancel()
    }

    /// Resume: the files not sent yet, on the same connection and folder.
    func resume(_ id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }), entry.model.stage == .finished else { return }
        let before = carried[id] ?? (0, entry.model.lastItems.count)
        carried[id] = (before.sent + entry.model.fileOutcomes.values.filter(\.isOnServer).count, before.total)
        pausedIds.remove(id)
        entry.model.uploadRemaining()
        keep(entry)
    }

    var isAnyRunning: Bool { entries.contains { $0.model.stage == .uploading } }
    /// A file already on the server waits for an answer: the batch is stopped
    /// until someone sees the row, so Activity opens on it.
    var needsAnswer: Bool { entries.contains { $0.model.pendingConflict != nil } }

    /// Stop and Quit: every batch stops and cleans its part file on the
    /// server; returns once all have finished, or after 10 s.
    func stopAll() async {
        let running = entries.filter { $0.model.stage == .uploading }
        for entry in running { userStoppedIds.insert(entry.id); entry.model.cancel() }
        let deadline = Date().addingTimeInterval(10)
        while running.contains(where: { $0.model.stage == .uploading }), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Written now: the once-a-second keeper may not run again before the app goes.
        for entry in running { record(entry) }
    }

    /// The sheet's Upload: the batch starts here and the sheet can close.
    /// False when it could not start (no connection, nothing to send).
    @discardableResult
    func start(_ model: ServerUploadModel) -> Bool {
        guard model.canStart else { return false }
        let name = model.selectedServer?.name ?? ""
        model.start()
        let entry = Entry(model: model, serverName: name)
        entries.insert(entry, at: 0)
        record(entry)
        keep(entry)
        // Finished rows beyond the last ten leave the list.
        // A paused batch is kept: it is waiting for Resume, not over.
        let finished = entries.indices.filter { entries[$0].model.stage == .finished && !pausedIds.contains(entries[$0].id) }
        if finished.count > 10 { entries.remove(at: finished.last!) }
        return true
    }

    /// Paused and still something to send: what the row and On Server show
    /// as "Paused". A pause that landed after the last file is just a finish.
    func isPaused(_ entry: Entry) -> Bool {
        pausedIds.contains(entry.id) && entry.model.stage == .finished && entry.model.hasRemaining
    }

    /// Remove from List: only a row that is over.
    func remove(_ id: UUID) {
        pausedIds.remove(id)
        carried[id] = nil
        entries.removeAll { $0.id == id && $0.model.stage == .finished }
    }

}

/// One upload in the Activity popover: progress while it goes, the
/// already-there question answered right in the row (board), the result
/// with Upload Remaining after.
struct MacUploadRow: View {
    let entry: MacUploads.Entry
    /// Paused by the user (not stopped by trouble): Resume, not Try Again.
    var isPaused = false
    /// Sent before the last Resume, and the job's whole size.
    var carried: (sent: Int, total: Int)?
    var pause: () -> Void = {}
    var resume: () -> Void = {}
    var stop: () -> Void = {}
    let remove: () -> Void
    @State private var appliesToAll = false
    @State private var isConfirmingStop = false

    private var model: ServerUploadModel { entry.model }

    var body: some View {
        // Top while a question can open under the bar; centred once over (board).
        HStack(alignment: model.stage == .uploading || !model.lastItems.isEmpty ? .top : .center, spacing: 12) {
            // The same tile as the other Activity rows: soft amber while it goes, red after trouble.
            Image(systemName: isTrouble ? "exclamationmark.triangle.fill" : "arrow.up")
                .accessibilityHidden(true)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.stage == .uploading ? MacTheme.accent : isTrouble ? MacTheme.redText : Color.secondary)
                .frame(width: 28, height: 28)
                .background(model.stage == .uploading ? MacTheme.accentSoft : MacTheme.fill, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).fontWeight(.semibold).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(aside).font(.subheadline).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }
                if model.stage == .uploading { bar(model.progress.fraction) }
                Text(status)
                    .font(.subheadline).monospacedDigit().lineLimit(model.stage == .finished ? 2 : 1)
                    .foregroundStyle(isTrouble ? MacTheme.redText : .secondary)
                    .help(status)
                if let conflict = model.pendingConflict { conflictPanel(conflict) }
                if !model.lastItems.isEmpty { files }
                if isConfirmingStop, model.stage == .uploading { stopQuestion }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            buttons.fixedSize().frame(minWidth: 140, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onChange(of: model.stage) { isConfirmingStop = false }
    }

    private var title: String {
        String(localized: "Upload to \(entry.serverName)", comment: "Mac Activity: an upload to a server")
    }

    /// Right of the title: the percentage while it goes, when it ended after.
    private var aside: String {
        switch model.stage {
        case .uploading: model.progress.fraction.formatted(.percent.precision(.fractionLength(0)))
        case .finished where isPaused: String(localized: "Paused", comment: "Mac Activity upload: aside of a paused upload")
        default: String(localized: "Started \(entry.startedAt.formatted(date: .omitted, time: .shortened))",
                        comment: "Mac Activity upload: when a finished upload began")
        }
    }

    private var isTrouble: Bool {
        !isPaused && model.stage == .finished && (model.summary.stopMessage != nil || !model.summary.failures.isEmpty)
    }

    /// Board: each file with where it stands — the per-file list under the row.
    private var files: some View {
        DisclosureGroup {
            ScrollView {
                // Lazy: only the rows in view are made, on every progress tick too.
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<min(model.lastItems.count, 500), id: \.self) { index in
                        let item = model.lastItems[index]
                        HStack(spacing: 8) {
                            Text(item.file.filename).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(fileState(index)).foregroundStyle(fileIsTrouble(index) ? MacTheme.redText : .secondary)
                        }
                        .font(.subheadline.monospacedDigit())
                    }
                    if model.lastItems.count > 500 {
                        Text("+ \(model.lastItems.count - 500) more", comment: "Mac Activity upload: files past the list's first 500")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 140)
        } label: {
            Text("Files", comment: "Mac Activity upload: the list of each file").font(.subheadline)
        }
    }

    private func fileState(_ index: Int) -> String {
        if let outcome = model.fileOutcomes[index] {
            switch outcome {
            case .uploaded: return String(localized: "Verified", comment: "Mac Activity upload file: up and checked")
            case .alreadyThere: return String(localized: "Already there", comment: "Mac Activity upload file: same file on the server")
            case .skipped: return String(localized: "Skipped", comment: "Mac Activity upload file: left as it was on the server")
            case .failed(let reason): return reason
            case .notAttempted: return String(localized: "Not sent", comment: "Mac Activity upload file: stopped before it")
            }
        }
        guard model.stage == .uploading else { return String(localized: "Not sent", comment: "Mac Activity upload file: stopped before it") }
        if index == model.progress.fileIndex, !model.progress.filename.isEmpty {
            switch model.progress.phase {
            case .preparing: return String(localized: "Reading", comment: "Mac Activity upload file: being read out of Photos")
            case .uploading: return String(localized: "Uploading", comment: "Mac Activity upload file: going up")
            case .verifying: return String(localized: "Verifying", comment: "Mac Activity upload file: read back to compare")
            }
        }
        return String(localized: "Waiting", comment: "Mac Activity upload file: its turn has not come")
    }

    private func fileIsTrouble(_ index: Int) -> Bool {
        if case .failed = model.fileOutcomes[index] { return true }
        return false
    }

    private var status: String {
        switch model.stage {
        case .preparing:
            return ""
        case .uploading:
            let progress = model.progress
            guard !progress.filename.isEmpty else {
                return String(localized: "Connecting to \(entry.serverName)…", comment: "Mac Activity upload: before the first file")
            }
            let done = ByteCountFormatter.string(fromByteCount: progress.bytesDone / 2, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.bytesTotal / 2, countStyle: .file)
            var line = String(localized: "\(min(progress.fileIndex + 1, progress.fileCount)) of \(progress.fileCount) files · \(done) of \(total)",
                              comment: "Mac Activity upload progress: files and bytes")
            if let seconds = progress.secondsLeft, seconds.isFinite {
                let left = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1))
                line += " · " + String(localized: "about \(left) left", comment: "Mac Activity upload: time left")
            }
            return line
        case .finished:
            let summary = model.summary
            if isPaused {
                let sent = (carried?.sent ?? 0) + model.fileOutcomes.values.filter(\.isOnServer).count
                let total = carried?.total ?? model.lastItems.count
                return String(AttributedString(localized: "Paused · \(sent) of ^[\(total) file](inflect: true) sent · the file that was going starts over on Resume",
                                               comment: "Mac Activity upload: paused by the user").characters)
            }
            var parts: [String] = []
            if summary.uploadedPhotoCount > 0 {
                let bytes = ByteCountFormatter.string(fromByteCount: summary.uploadedBytes, countStyle: .file)
                parts.append(String(AttributedString(localized: "Uploaded ^[\(summary.uploadedPhotoCount) photo](inflect: true) (\(bytes)), each file checked",
                                                     comment: "Mac Activity upload result").characters))
                if let carried, carried.sent > 0 {
                    parts.append(String(localized: "\(carried.sent) more before the pause", comment: "Mac Activity upload result: sent before a Resume"))
                }
            } else {
                parts.append(String(localized: "No photos uploaded", comment: "Mac Activity upload result: nothing went up"))
            }
            if summary.skippedFileCount > 0 {
                parts.append(String(localized: "\(summary.skippedFileCount) skipped", comment: "Mac Activity upload result: already there"))
            }
            if let first = summary.failures.first {
                parts.append(String(localized: "\(summary.failures.count) failed (\(first.filename): \(first.reason))",
                                    comment: "Mac Activity upload result: files that didn't go, the first one's reason"))
            }
            if summary.notAttemptedCount > 0 {
                parts.append(String(localized: "\(summary.notAttemptedCount) not sent", comment: "Mac Activity upload result: stopped before them"))
            }
            if let stop = summary.stopMessage { parts.append(stop) }
            return parts.joined(separator: " · ")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 6) {
            switch model.stage {
            case .preparing:
                EmptyView()
            case .uploading:
                Button(action: pause) { Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.bordered).controlSize(.small)
                    // A waiting question first: pausing would answer it Skip.
                    .disabled(model.pendingConflict != nil)
                    .help(String(localized: "Pause \(title)", comment: "Mac Activity: pause an upload"))
                    .accessibilityLabel(String(localized: "Pause \(title)", comment: "Mac Activity: pause an upload"))
                Button { isConfirmingStop = true } label: { Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help(String(localized: "Stop \(title)…", comment: "Mac Activity: stop an upload"))
                    .accessibilityLabel(String(localized: "Stop \(title)…", comment: "Mac Activity: stop an upload"))
            case .finished:
                if isPaused, model.hasRemaining {
                    Button(String(localized: "Resume", comment: "Mac Activity upload: send the rest of a paused upload"), action: resume)
                        .buttonStyle(.bordered).controlSize(.small)
                    Button(String(localized: "Discard Remaining", comment: "Mac Activity upload: forget a paused upload's unsent files"), action: remove)
                        .buttonStyle(.bordered).controlSize(.small)
                        .help(String(localized: "The files not sent stay on this Mac only; files already uploaded stay on the server.",
                                     comment: "Mac Activity upload: Discard Remaining tooltip"))
                } else if model.hasRemaining {
                    Button(model.summary.uploadedPhotoCount == 0
                           ? String(localized: "Try Again", comment: "Mac Activity upload: nothing went up, run it again")
                           : String(localized: "Upload Remaining", comment: "Mac Activity upload: send the files that didn't go")) {
                        model.uploadRemaining()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                if !(isPaused && model.hasRemaining) {
                    Button(String(localized: "Remove from List", comment: "Mac Activity upload: forget a finished row"), action: remove)
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    /// Stop asks right in the row: the popover cannot hold an alert.
    private var stopQuestion: some View {
        HStack(spacing: 8) {
            Text("Stop? Files already uploaded stay on the server.", comment: "Mac Activity upload: confirm Stop")
                .font(.subheadline)
            Spacer(minLength: 8)
            Button { stop() } label: {
                Text("Stop", comment: "Mac Activity upload: stop").foregroundStyle(MacTheme.redText)
            }
            .buttonStyle(MacPushButtonStyle(isDefault: false))
            // The safe answer is the prominent one: going on.
            Button(String(localized: "Keep Uploading", comment: "Mac Activity upload: don't stop")) { isConfirmingStop = false }
                .buttonStyle(MacPushButtonStyle(isDefault: true, defaultWeight: .medium))
        }
        .padding(10)
        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Already on the server (FS-15.02 §5): decided in the row, for this file
    /// or every one left.
    private func conflictPanel(_ conflict: ServerUploadConflict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“\(conflict.item.file.filename)” is already on \(entry.serverName)",
                 comment: "Mac Activity upload: a file of that name is on the server")
                .font(.body.weight(.semibold))
            Text("\(ByteCountFormatter.string(fromByteCount: conflict.localBytes, countStyle: .file)) here · \(ByteCountFormatter.string(fromByteCount: conflict.remoteBytes, countStyle: .file)) on the server",
                 comment: "Mac Activity upload: the two sizes")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            Toggle(String(localized: "Apply to Remaining Conflicts", comment: "Mac Activity upload: apply the choice to the rest (FS-15.02 §5)"),
                   isOn: $appliesToAll)
                .toggleStyle(.checkbox)
            HStack {
                Button(role: .destructive) { answer(.replace) } label: {
                    Text("Replace", comment: "Mac Activity upload conflict: overwrite the server's file").foregroundStyle(MacTheme.redText)
                }
                .buttonStyle(MacPushButtonStyle(isDefault: false))
                Spacer()
                Button(String(localized: "Skip", comment: "Mac Activity upload conflict: leave the server's file")) { answer(.skip) }
                    .buttonStyle(MacPushButtonStyle(isDefault: false))
                Button(String(localized: "Keep Both", comment: "Mac Activity upload conflict: upload under a new name")) { answer(.keepBoth) }
                    .buttonStyle(MacPushButtonStyle(isDefault: true, defaultWeight: .medium))
            }
        }
        .padding(10)
        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 8))
    }

    private func answer(_ choice: ServerUploadConflictDecision.Choice) {
        model.answerConflict(.init(choice: choice, appliesToRemaining: appliesToAll))
        appliesToAll = false
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(MacTheme.fill)
                Capsule().fill(MacTheme.accent).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The sidebar's foot while uploads run (board `MAC_ServerUpload`):
/// where they go, how far, and a click away from Activity.
struct MacUploadFoot: View {
    /// The uploads going now, newest first.
    let entries: [MacUploads.Entry]
    /// The index's own line, kept under the upload while both run.
    var indexLine: String?

    private var models: [ServerUploadModel] { entries.map(\.model) }
    private var bytesTotal: Int64 { models.reduce(0) { $0 + $1.progress.bytesTotal } }
    private var fraction: Double {
        bytesTotal > 0 ? min(1, Double(models.reduce(0) { $0 + $1.progress.bytesDone }) / Double(bytesTotal)) : 0
    }
    private var needsAnswer: Bool { models.contains { $0.pendingConflict != nil } }

    private var title: String {
        entries.count == 1
            ? String(localized: "Uploading to \(entries[0].serverName)", comment: "Mac sidebar foot: an upload is running")
            : String(localized: "Uploading \(entries.count) batches", comment: "Mac sidebar foot: several uploads are running")
    }

    var body: some View {
        Button {
            MacWindowRequest.showsActivity = true
            NotificationCenter.default.post(name: .macShowActivity, object: nil)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).lineLimit(1)
                    Spacer(minLength: 8)
                    if needsAnswer {
                        Text("Needs answer", comment: "Mac sidebar foot: an upload waits on an already-there question")
                            .foregroundStyle(MacTheme.accent).fontWeight(.semibold)
                    } else if bytesTotal == 0 {
                        // Files still being read out of Photos: no number yet, rather than a stuck 0%.
                        Text("Preparing…", comment: "Mac sidebar foot: an upload before its first bytes go")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                    }
                }
                .font(.caption)
                if bytesTotal == 0 {
                    ProgressView().progressViewStyle(.linear).tint(MacTheme.accent).controlSize(.mini)
                } else {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(MacTheme.fill)
                            Capsule().fill(MacTheme.accent).frame(width: geometry.size.width * fraction)
                        }
                    }
                    .frame(height: 4)
                }
                if let indexLine {
                    Text(indexLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .help(String(localized: "Show the upload in Activity", comment: "Mac sidebar foot: upload tooltip"))
        .accessibilityLabel(title)
        .accessibilityValue(needsAnswer ? String(localized: "Needs answer", comment: "Mac sidebar foot: an upload waits on an already-there question")
                                        : fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// An upload from an earlier launch (FS-15.02 §9): what happened, and
/// Upload Again… for the same photos — the ones already there are skipped.
struct MacUploadRecordRow: View {
    let record: MacUploadRecord
    let uploadAgain: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: record.isTrouble ? "exclamationmark.triangle.fill" : "arrow.up")
                .accessibilityHidden(true)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(record.isTrouble ? MacTheme.redText : Color.secondary)
                .frame(width: 28, height: 28)
                .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Upload to \(record.serverName)", comment: "Mac Activity: an upload to a server").fontWeight(.semibold).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(record.endedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }
                Text(record.line).font(.subheadline).monospacedDigit().lineLimit(2)
                    .foregroundStyle(record.isTrouble ? MacTheme.redText : .secondary)
                    .help(record.line)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if record.photoCount > 0, record.isTrouble || record.wasPaused {
                    Button(String(localized: "Upload Again…", comment: "Mac Activity kept upload: the same photos to the same server, what is there already skipped"),
                           action: uploadAgain)
                        .buttonStyle(.bordered).controlSize(.small)
                        .help(String(localized: "Sends the same photos to the same folder. Files already there are recognised and skipped, so only the rest goes.",
                                     comment: "Mac Activity kept upload: Upload Again… tooltip"))
                }
                Button(String(localized: "Remove from List", comment: "Mac Activity upload: forget a finished row"), action: remove)
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .fixedSize()
            .frame(minWidth: 140, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .accessibilityElement(children: .contain)
    }
}
