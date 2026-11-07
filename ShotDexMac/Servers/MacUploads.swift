import SwiftUI

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

    var isAnyRunning: Bool { entries.contains { $0.model.stage == .uploading } }
    /// A file already on the server waits for an answer: the batch is stopped
    /// until someone sees the row, so Activity opens on it.
    var needsAnswer: Bool { entries.contains { $0.model.pendingConflict != nil } }

    /// Stop and Quit: every batch stops and cleans its part file on the
    /// server; returns once all have finished, or after 10 s.
    func stopAll() async {
        let running = entries.filter { $0.model.stage == .uploading }
        for entry in running { entry.model.cancel() }
        let deadline = Date().addingTimeInterval(10)
        while running.contains(where: { $0.model.stage == .uploading }), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The sheet's Upload: the batch starts here and the sheet can close.
    /// False when it could not start (no connection, nothing to send).
    @discardableResult
    func start(_ model: ServerUploadModel) -> Bool {
        guard model.canStart else { return false }
        let name = model.selectedServer?.name ?? ""
        model.start()
        entries.insert(Entry(model: model, serverName: name), at: 0)
        // Finished rows beyond the last ten leave the list.
        let finished = entries.indices.filter { entries[$0].model.stage == .finished }
        if finished.count > 10 { entries.remove(at: finished.last!) }
        return true
    }

    /// Remove from List: only a row that is over.
    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id && $0.model.stage == .finished }
    }

}

/// One upload in the Activity popover: progress while it goes, the
/// already-there question answered right in the row (board), the result
/// with Upload Remaining after.
struct MacUploadRow: View {
    let entry: MacUploads.Entry
    let remove: () -> Void
    @State private var appliesToAll = false
    @State private var isConfirmingStop = false

    private var model: ServerUploadModel { entry.model }

    var body: some View {
        // Top while a question can open under the bar; centred once over (board).
        HStack(alignment: model.stage == .uploading ? .top : .center, spacing: 12) {
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
        default: String(localized: "Started \(entry.startedAt.formatted(date: .omitted, time: .shortened))",
                        comment: "Mac Activity upload: when a finished upload began")
        }
    }

    private var isTrouble: Bool {
        model.stage == .finished && (model.summary.stopMessage != nil || !model.summary.failures.isEmpty)
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
            var parts: [String] = []
            if summary.uploadedPhotoCount > 0 {
                let bytes = ByteCountFormatter.string(fromByteCount: summary.uploadedBytes, countStyle: .file)
                parts.append(String(localized: "Uploaded \(summary.uploadedPhotoCount) photos (\(bytes)), each file checked",
                                    comment: "Mac Activity upload result"))
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
                Button { isConfirmingStop = true } label: { Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help(String(localized: "Stop \(title)…", comment: "Mac Activity: stop an upload"))
                    .accessibilityLabel(String(localized: "Stop \(title)…", comment: "Mac Activity: stop an upload"))
            case .finished:
                if model.hasRemaining {
                    Button(model.summary.uploadedPhotoCount == 0
                           ? String(localized: "Try Again", comment: "Mac Activity upload: nothing went up, run it again")
                           : String(localized: "Upload Remaining", comment: "Mac Activity upload: send the files that didn't go")) {
                        model.uploadRemaining()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Button(String(localized: "Remove from List", comment: "Mac Activity upload: forget a finished row"), action: remove)
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    /// Stop asks right in the row: the popover cannot hold an alert.
    private var stopQuestion: some View {
        HStack(spacing: 8) {
            Text("Stop? Files already uploaded stay on the server.", comment: "Mac Activity upload: confirm Stop")
                .font(.subheadline)
            Spacer(minLength: 8)
            Button { model.cancel() } label: {
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
