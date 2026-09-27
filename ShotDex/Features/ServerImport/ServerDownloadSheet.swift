import SwiftUI

/// Server browser → Download (FS-17.02): where to, progress, result. Tier A —
/// a form and a report, the same shape as the upload sheet.
struct ServerDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var model: ServerDownloadModel
    @State private var isConfirmingCancel = false
    @State private var isNamingAlbum = false
    @State private var newAlbumName = ""
    /// Show in Library / the album after the download.
    var onShow: ((ServerDownloadModel.Destination) -> Void)?

    init(model: ServerDownloadModel, onShow: ((ServerDownloadModel.Destination) -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onShow = onShow
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.stage == .downloading)
        // Leaving the app stops the batch, as uploads do.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, model.stage == .downloading { model.cancel() }
        }
        .onDisappear { model.tearDown() }
        .alert("Stop Importing?", isPresented: $isConfirmingCancel) {
            Button("Stop", role: .destructive) { model.cancel() }
            Button("Keep Importing", role: .cancel) {}
        } message: {
            Text("Photos already imported stay in your library.")
        }
        .alert("New Album", isPresented: $isNamingAlbum) {
            TextField("Name", text: $newAlbumName)
            Button("Create") {
                let name = newAlbumName
                Task { await model.createAlbum(named: name) }
            }
            .disabled(newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Couldn't Create Album",
            isPresented: Binding(get: { model.albumError != nil }, set: { if !$0 { model.albumError = nil } }),
            presenting: model.albumError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private var title: String {
        switch model.stage {
        case .preparing: String(localized: "Import to Library", comment: "Import from server sheet title")
        case .downloading: String(localized: "Importing", comment: "Import from server sheet title while running")
        case .finished: String(localized: "Import Finished", comment: "Import from server sheet title when done")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch model.stage {
        case .preparing:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") { model.start() }
                    .disabled(!model.canStart)
            }
        case .downloading:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isConfirmingCancel = true }
            }
        case .finished:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .preparing: prepareForm
        case .downloading: progressForm
        case .finished: resultForm
        }
    }

    // MARK: Prepare

    private var prepareForm: some View {
        Form {
            Section {
                if model.isLimitedAccess {
                    destinationRow("Library Only", isChosen: true) {}
                } else {
                    // Three plain choices (FS-17.02 §1): library only, an
                    // album that exists, or one made here.
                    destinationRow("Library Only", isChosen: model.choice == .libraryOnly) {
                        model.destination = .library
                    }
                    NavigationLink {
                        AlbumChoiceList(model: model)
                    } label: {
                        HStack {
                            chosenMark(model.choice == .existingAlbum)
                            Text("Existing Album")
                            Spacer()
                            if model.choice == .existingAlbum {
                                Text(model.destinationTitle)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .disabled(model.albums.isEmpty)
                    Button {
                        newAlbumName = ""
                        isNamingAlbum = true
                    } label: {
                        HStack {
                            chosenMark(model.choice == .newAlbum)
                            Text("New Album…")
                                .foregroundStyle(.primary)
                            Spacer()
                            if model.choice == .newAlbum {
                                Text(model.destinationTitle)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Import To")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.destinationSentence)
                    if model.isLimitedAccess {
                        Text("Allow full access to Photos to add them to an album too.")
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.footnote)
                    }
                }
            }
            Section {
                if model.inLibraryCount > 0 {
                    Toggle(isOn: $model.skipsInLibrary) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Skip Photos Already in Library")
                            Text("\(model.inLibraryCount) of the selected photos", comment: "Download from server: how many picked photos are already in the library")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Label("Keep ShotDex open until the import finishes. The screen stays on.", systemImage: "iphone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.photosToDownload.count) photos · \(model.photosToDownload.reduce(0) { $0 + $1.files.count }) files · ~\(ByteCountFormatter.string(fromByteCount: model.estimatedBytes, countStyle: .file))",
                         comment: "Download from server summary: photos, files and estimated size")
                    if let short = model.spaceShortfall {
                        Text("Not enough space on this device — about \(ByteCountFormatter.string(fromByteCount: short, countStyle: .file)) more needed.",
                             comment: "Download from server: free space too low")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: Progress

    private var progressForm: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Importing \(model.progress.index + 1) of \(model.progress.count)", comment: "Download from server progress headline")
                        .font(.headline)
                    ProgressView(value: model.progress.fraction)
                        .accessibilityLabel("Import progress")
                        .accessibilityValue(Text(model.progress.fraction, format: .percent.precision(.fractionLength(0))))
                    Text(byteLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
                LabeledContent(model.progress.filename, value: phaseTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } footer: {
                Text("Keep ShotDex open until the download finishes. The screen stays on.")
            }
        }
    }

    private var byteLine: String {
        let done = ByteCountFormatter.string(fromByteCount: model.progress.bytesDone, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: model.progress.bytesTotal, countStyle: .file)
        guard let seconds = model.progress.secondsLeft else {
            return String(localized: "\(done) of \(total)", comment: "Download from server: bytes received of total")
        }
        let left = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
        return String(localized: "\(done) of \(total) · about \(left) left", comment: "Download from server: bytes received of total, and time left")
    }

    private var phaseTitle: String {
        switch model.progress.phase {
        case .downloading: String(localized: "Downloading", comment: "Download from server: receiving the file")
        case .checking: String(localized: "Checking", comment: "Download from server: checking the received file")
        case .saving: String(localized: "Saving", comment: "Download from server: writing into Photos")
        }
    }

    // MARK: Result

    private var resultForm: some View {
        let summary = model.summary
        return Form {
            Section {
                if summary.savedCount > 0 {
                    Text(model.destination == .library
                         ? String(localized: "Imported \(summary.savedCount) photos into your library.", comment: "Import from server result headline, library only")
                         : String(localized: "Imported \(summary.savedCount) photos into your library and “\(model.destinationTitle)”.", comment: "Import from server result headline, with an album"))
                        .font(.headline)
                    // Library only: opening an album from here would mean
                    // rebuilding the Collections album entry (FS-17.02 §4).
                    if let onShow, model.destination == .library {
                        Button("Show") {
                            onShow(model.destination)
                            dismiss()
                        }
                    }
                } else {
                    Text("Nothing was imported.")
                        .font(.headline)
                }
                if let stop = summary.stopMessage {
                    Text(stop).foregroundStyle(.secondary)
                }
                if summary.skippedCount > 0 {
                    Text("\(summary.skippedCount) photos skipped — already in your library.", comment: "Download from server result: photos skipped because they were already in the library")
                        .foregroundStyle(.secondary)
                }
            }
            if !summary.failures.isEmpty || summary.notAttemptedCount > 0 {
                Section {
                    ForEach(summary.failures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.filename)
                            Text(failure.reason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if summary.notAttemptedCount > 0 {
                        Text("\(summary.notAttemptedCount) photos not imported yet.", comment: "Download from server result: photos the stopped batch never reached")
                            .foregroundStyle(.secondary)
                    }
                    if model.hasRemaining {
                        Button("Try Again") { model.tryAgain() }
                    }
                } header: {
                    Text("Not Imported")
                }
            }
        }
    }

    private func destinationRow(_ title: LocalizedStringKey, isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                chosenMark(isChosen)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// The check in front of the chosen way in, blank space otherwise so
    /// the three titles line up.
    private func chosenMark(_ isChosen: Bool) -> some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
            .opacity(isChosen ? 1 : 0)
            .frame(width: 22)
            .accessibilityHidden(true)
    }
}

/// Existing Album: the user's albums, the chosen one checked (FS-17.02 §1).
private struct AlbumChoiceList: View {
    @Environment(\.dismiss) private var dismiss
    let model: ServerDownloadModel

    var body: some View {
        List(model.albums) { album in
            Button {
                model.destination = .album(id: album.id)
                dismiss()
            } label: {
                HStack {
                    Text(album.title)
                        .foregroundStyle(.primary)
                    Spacer()
                    if model.destination == .album(id: album.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Choose Album")
        .navigationBarTitleDisplayMode(.inline)
    }
}
