import ImageIO
import GRDB
import SwiftUI

/// Find Common Photos (board `MAC_CommonPhotos`, FS-19.08 §4): the folders,
/// where the common photos go and Copy or Move; Scan, then Copy N / Move N
/// for the photos found Same. Starting a run closes the sheet — the run
/// goes on in `MacCommonPhotosRuns`.
struct MacCommonPhotosSheet: View {
    let request: MacCommonPhotosRequest
    let server: FileServer
    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var model: CommonPhotosScanModel?
    @State private var sources: [(source: SourceStore.Source, connection: FileServer)] = []

    var body: some View {
        Group {
            if let model {
                MacCommonPhotosSheetContent(model: model, server: server, sources: sources, close: close)
            } else {
                ProgressView().frame(width: MacCommonPhotosSheetContent.size.width, height: MacCommonPhotosSheetContent.size.height)
            }
        }
        .task {
            let all = (try? dependencies.sources.sources()) ?? []
            let connections = (try? dependencies.sources.serverConnections()) ?? [:]
            sources = all.compactMap { source in
                guard let id = connections[source.id], let connection = try? dependencies.fileServers.fetch(id: id),
                      CommonPhotosSources.sameFiles(connection, server) else { return nil }
                return (source, connection)
            }
            let model = CommonPhotosScanModel(connectionId: request.connectionId, sourceId: request.sourceId, folders: request.folders,
                                              client: dependencies.lockedClient(for: server), database: dependencies.database,
                                              sources: sources.map { CommonPhotosSources.Source(sourceId: $0.source.id, connection: $0.connection) })
            // Run Again: the set as it ran, checked for new photos at once.
            if let destination = request.destination { model.destination = destination }
            if let action = request.action { model.action = action }
            #if DEBUG
            MacDemoLibrary.prepareCommonPhotos(model)
            #endif
            self.model = model
            if request.scansAtOnce { model.scan() }
        }
        // However the sheet goes, the scan stops and the session ends.
        .onDisappear {
            let model = model
            // Compare showed this scan: it has nothing to show now.
            if let model, dependencies.commonPhotosCompare?.scan === model { dependencies.commonPhotosCompare = nil }
            Task { await model?.close() }
        }
    }

    private func close() {
        let model = model
        Task { await model?.close() }
        dismiss()
    }
}

private struct MacCommonPhotosSheetContent: View {
    @Bindable var model: CommonPhotosScanModel
    let server: FileServer
    let sources: [(source: SourceStore.Source, connection: FileServer)]
    var close: () -> Void
    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.openWindow) private var openWindow
    @State private var picker: FolderChoice?
    @State private var isNamingFolder = false
    @State private var newFolderName = ""
    @State private var newFolderError: String?
    @State private var confirmsMove = false
    /// §6d: the Left Out list, open or not.
    @State private var showsLeftOut = Self.showsLeftOutAtStart
    /// Rows picked in the list: Space compares one, or checks several (§6d).
    @State private var selectedRows = Set<String>()

    /// `-ShotDexCommonPhotosShowLeftOut` (DEBUG): the Left Out list open, for screenshots.
    private static let showsLeftOutAtStart: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosShowLeftOut")
        #else
        false
        #endif
    }()
    @State private var startError: String?
    /// The run is being written; a second click does nothing.
    @State private var isStarting = false
    /// Keep gathering (FS-19.08 §6c): saved when the run starts.
    @State private var keepsGathering = false

    /// Board `MAC_CommonPhotos`: the sheet at 640×560, labels in a 64pt column.
    static let size = CGSize(width: 640, height: 560)
    private static let labelWidth: CGFloat = 64
    private static let saveToWidth: CGFloat = 168
    private static let segmentWidth: CGFloat = 64
    private static let statusWidth: CGFloat = 86

    enum FolderChoice: Identifiable {
        case addFolder, destination
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Find Common Photos", comment: "Mac common photos sheet: title")
                .font(.title3.weight(.semibold))
            Spacer().frame(height: 14)
            foldersRow
            Divider().padding(.vertical, 12)
            saveToRow
            if model.action == .move {
                Text("Moved photos are removed from every folder above. The server has no Trash.",
                     comment: "Mac common photos sheet: what Move does")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.labelWidth + 8)
                    .padding(.top, 6)
            }
            if !model.isDestinationIndexed, let destination = model.destination {
                let name = ServerUploadPath.lastComponent(of: destination)
                Label(model.action == .move
                      ? String(localized: "These photos will leave ShotDex's library until you add “\(name)” as a source.",
                               comment: "Mac common photos sheet: Move into a folder no source holds")
                      : String(localized: "“\(name)” isn't in a source, so photos saved there won't show in ShotDex until you add it.",
                               comment: "Mac common photos sheet: the destination is in no source"),
                      systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.leading, Self.labelWidth + 8)
                    .padding(.top, 6)
            }
            Divider().padding(.vertical, 12)
            results
            Spacer().frame(height: 12)
            keepGatheringRow
            Spacer().frame(height: 8)
            footer
        }
        // The set's own choice, read again whenever the set changes.
        .task(id: "\(model.connectionId)|\(model.folders)|\(model.destination ?? "")") { readKeepGathering() }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: Self.size.width, height: Self.size.height)
        .sheet(item: $picker) { picker in
            MacServerFolderPicker(server: server, password: "", start: pickerStart(picker),
                                  client: dependencies.lockedClient(for: server)) { path in
                switch picker {
                case .addFolder: model.add(folder: path)
                case .destination: model.destination = ServerUploadPath.normalizedFolder(path)
                }
            }
        }
        .alert(String(localized: "New Folder", comment: "Mac common photos sheet: name a new destination folder"), isPresented: $isNamingFolder) {
            TextField(String(localized: "Name", comment: "Mac common photos sheet: new folder name field"), text: $newFolderName)
            Button(String(localized: "Create", comment: "Mac common photos sheet: create the folder")) { createFolder() }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
        } message: {
            Text("In \(display(newFolderParent)).", comment: "Mac common photos sheet: where the new folder goes")
        }
        .alert(moveTitle, isPresented: $confirmsMove) {
            Button(String(localized: "Move", comment: "Mac common photos: confirm the move"), role: .destructive) { start() }
            // Cancel is the default: Return removes nothing (FS-19.08 §4).
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(moveMessage)
        }
        .alert(String(localized: "Couldn't Start", comment: "Mac common photos: the run could not be written"),
               isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })) {
            Button(String(localized: "OK", comment: "Mac alert: dismiss"), role: .cancel) {}
        } message: {
            Text(startError ?? "")
        }
        .alert(String(localized: "Couldn't Create Folder", comment: "Mac common photos sheet: New Folder failed"),
               isPresented: Binding(get: { newFolderError != nil }, set: { if !$0 { newFolderError = nil } })) {
            Button(String(localized: "OK", comment: "Mac alert: dismiss"), role: .cancel) {}
        } message: {
            Text(newFolderError ?? "")
        }
        .onChange(of: model.phase) { _, phase in
            #if DEBUG
            if phase == .done, ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosConfirm"), model.canRun { confirmsMove = true }
            // The app end to end: the run starts with no click (and no Move question).
            if phase == .done, ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosRunAfterScan"), model.canRun { start() }
            #endif
        }
        #if DEBUG
        // `-ShotDexCommonPhotosRunAtOnce`: the run starts as the scan ends,
        // for screenshots of a set that gathered before.
        .onChange(of: model.phase) {
            // `-ShotDexCommonPhotosCompare IMG_0001.JPG`: Compare opened on that row (§6d), for screenshots.
            if model.phase == .done, let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-ShotDexCommonPhotosCompare"),
               index + 1 < ProcessInfo.processInfo.arguments.count,
               let row = model.rows.first(where: { $0.name == ProcessInfo.processInfo.arguments[index + 1] }) {
                compare(row.id)
            }
            // `-ShotDexCommonPhotosLeaveOut IMG_0003.JPG,IMG_0005.JPG`: those rows unchecked (§6d), for screenshots.
            if model.phase == .done, let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-ShotDexCommonPhotosLeaveOut"),
               index + 1 < ProcessInfo.processInfo.arguments.count {
                let names = Set(ProcessInfo.processInfo.arguments[index + 1].split(separator: ",").map(String.init))
                model.setIncluded(false, rows: Set(model.rows.filter { names.contains($0.name) }.map(\.id)))
            }
            // `-ShotDexCommonPhotosKeepGathering`: the box ticked, for an end-to-end run of Keep gathering.
            if model.phase == .done, ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosKeepGathering") { keepsGathering = true }
            if model.phase == .done, model.canRun, ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosRunAtOnce") { start() }
            // `-ShotDexCommonPhotosGatherReady` (with `-ShotDexCommonPhotosAction move`):
            // what Keep gathering's pass does with these photos — a run ready
            // to move, nothing moved — and its window, for screenshots (§6c).
            if model.phase == .done, ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosGatherReady"),
               let destination = model.destination, let made = model.makeRun(), !made.items.isEmpty,
               let watch = try? CommonPhotosWatchStore(database: dependencies.database).keepGathering(
                   connectionId: model.connectionId, folders: model.folders, destination: destination, action: model.action),
               let gathered = try? dependencies.commonPhotos.store.gatherIntoDay(
                   made.run, items: made.items, watchId: watch.id, day: CommonPhotosStore.day(of: Date()), ready: true) {
                close()
                if ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosAskMove") { dependencies.commonPhotos.moveAsked = gathered.runId }
                openWindow(id: MacCommonPhotosRunWindow.id, value: gathered.runId)
                if ProcessInfo.processInfo.arguments.contains("-ShotDexOpenActivity") { openWindow(id: MacActivityWindow.id) }
            }
        }
        #endif
    }

    // MARK: Folders

    private var foldersRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Folders:", comment: "Mac common photos sheet: label").frame(width: Self.labelWidth, height: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                if !model.folders.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(model.folders.enumerated()), id: \.element) { index, folder in
                            folderRow(folder, alternate: index % 2 == 1)
                        }
                    }
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(String(localized: "Folders", comment: "Mac common photos sheet: the folder list"))
                }
                Button(String(localized: "Add Folder…", comment: "Mac common photos sheet: add a folder of this connection")) {
                    picker = .addFolder
                }
    
            }
        }
    }

    private func folderRow(_ folder: String, alternate: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(MacTheme.accent)
            Text(display(folder)).lineLimit(1).truncationMode(.head).frame(maxWidth: .infinity, alignment: .leading)
            if let count = model.fileCounts[folder] {
                Text(count == 1 ? String(localized: "1 file", comment: "Mac common photos sheet: files in a folder")
                                : String(localized: "\(count.formatted()) files", comment: "Mac common photos sheet: files in a folder"))
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Button { model.remove(folder: folder) } label: {
                Image(systemName: "minus").fontWeight(.semibold).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "Remove \(ServerUploadPath.lastComponent(of: folder))", comment: "Mac common photos sheet: remove a folder"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(alternate ? MacTheme.rowAlternate : .clear)
    }

    /// "NAS Home › Family › Tuấn": the source holding it, then the folders
    /// below its root.
    private func display(_ path: String) -> String {
        let holder = sources.first { CommonPhotosSelection.contains($0.connection.folder, path) }
        let root = holder.map { ServerUploadPath.normalizedFolder($0.connection.folder) } ?? ""
        var rest = ServerUploadPath.normalizedFolder(path)
        if !root.isEmpty, rest.lowercased().hasPrefix(root.lowercased()) { rest = String(rest.dropFirst(root.count)) }
        let components = rest.split(separator: "/").map(String.init)
        return ([holder?.source.name ?? server.name] + components).joined(separator: " › ")
    }

    private func pickerStart(_ picker: FolderChoice) -> String {
        switch picker {
        case .addFolder: model.folders.last.map { ServerUploadPath.parent(of: $0) } ?? server.folder
        case .destination: model.destination ?? model.folders.first.map { ServerUploadPath.parent(of: $0) } ?? server.folder
        }
    }

    // MARK: Save to and action

    private var saveToRow: some View {
        HStack(spacing: 8) {
            Text("Save to:", comment: "Mac common photos sheet: label").frame(width: Self.labelWidth, alignment: .trailing)
            Button { picker = .destination } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(MacTheme.accent)
                    Text(model.destination.map { ServerUploadPath.lastComponent(of: $0) }
                         ?? String(localized: "Choose…", comment: "Mac common photos sheet: no destination yet"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(.secondary)
                }
                .frame(width: Self.saveToWidth - 24)
            }

            .accessibilityLabel(String(localized: "Save to", comment: "Mac common photos sheet: destination popup"))
            .accessibilityValue(model.destination.map(display) ?? "")
            Button(String(localized: "New Folder…", comment: "Mac common photos sheet: make a destination folder")) {
                newFolderName = ""
                isNamingFolder = true
            }

            Spacer(minLength: 8)
            Text("Action:", comment: "Mac common photos sheet: label")
            Picker(selection: $model.action) {
                Text("Copy", comment: "Mac common photos sheet: action").tag(CommonPhotosRun.Action.copy)
                Text("Move", comment: "Mac common photos sheet: action").tag(CommonPhotosRun.Action.move)
            } label: {
                Text("Action", comment: "Mac common photos sheet: label")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: Self.segmentWidth * 2 + 4)
        }
        .frame(height: 28)
    }

    /// New Folder… goes inside the destination, or beside the first folder.
    private var newFolderParent: String {
        model.destination ?? model.folders.first.map { ServerUploadPath.parent(of: $0) } ?? server.folder
    }

    private func createFolder() {
        guard let name = RemoteFolderListing.validatedName(newFolderName) else {
            newFolderError = String(localized: "Use a name that isn't empty, has no “/” and doesn't start with a dot.",
                                    comment: "Mac common photos sheet: a folder name that cannot be used")
            return
        }
        let path = ServerUploadPath.join(newFolderParent, name)
        let client = dependencies.lockedClient(for: server)
        Task {
            do {
                try await client.connect()
                if try await client.folderNames(in: newFolderParent).contains(where: { $0.lowercased() == name.lowercased() }) {
                    newFolderError = String(localized: "“\(name)” already exists.", comment: "Mac common photos sheet: New Folder with a name in use")
                } else {
                    try await client.createDirectory(path)
                    model.destination = path
                }
            } catch {
                newFolderError = (error as? RemoteFileError)?.errorDescription ?? error.localizedDescription
            }
            await client.disconnect()
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if model.preview == nil {
            VStack(spacing: 6) {
                if model.phase == .listing {
                    ProgressView().controlSize(.small)
                    Text(model.listedFiles == 0
                         ? String(localized: "Listing…", comment: "Mac common photos sheet: the scan lists the folders")
                         : String(localized: "Listing… \(model.listedFiles.formatted()) files", comment: "Mac common photos sheet: files listed so far"))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else if let failure = model.failure {
                    failureLine(failure)
                } else if let notice = model.notice {
                    Text(noticeText(notice))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Scan finds the photos every folder holds, byte for byte. Nothing is copied or moved until you choose.",
                         comment: "Mac common photos sheet: before the scan")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
        } else {
            VStack(spacing: 8) {
                if let failure = model.failure { failureLine(failure).frame(maxWidth: .infinity, alignment: .leading) }
                HStack(spacing: 16) {
                    Text(headline).fontWeight(.semibold).monospacedDigit().lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    count(String(localized: "Same", comment: "Mac common photos sheet: photos proven the same"), model.sameCount, done: true)
                    if model.checkingCount > 0 {
                        count(String(localized: "Checking", comment: "Mac common photos sheet: photos still being checked"),
                              model.checkingCount, done: false)
                    }
                    if model.notCheckedCount > 0 {
                        // A failed scan's leftovers: counted, never listed (§6d).
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                            Text("Not checked", comment: "Mac common photos sheet: photos a failed scan never reached")
                                .foregroundStyle(.secondary)
                            Text(model.notCheckedCount.formatted()).fontWeight(.semibold).monospacedDigit()
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(height: 28)
                let isNothingNew = model.phase == .done && !model.isCutting && model.sameCount == 0
                    && model.lastGathered != nil && !model.scansEverything
                if let gathered = model.lastGathered, !model.scansEverything, !isNothingNew {
                    againLine(gathered)
                }
                if isNothingNew, let gathered = model.lastGathered {
                    nothingNew(since: gathered)
                } else if model.phase == .done, model.sameCount == 0 {
                    Text(model.folders.count == 2
                         ? String(localized: "No photos are in both folders.", comment: "Mac common photos sheet: nothing in common, two folders")
                         : String(localized: "No photos are in all \(model.folders.count) folders.", comment: "Mac common photos sheet: nothing in common"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.rows, selection: $selectedRows) { row in
                        MacCommonPhotosRow(row: row, destination: model.destination.map(ServerUploadPath.lastComponent(of:)),
                                           action: model.action, database: dependencies.database, sources: sources,
                                           setIncluded: { model.setIncluded($0, rows: [row.id]) },
                                compare: { compare(row.id) })
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
                            .contextMenu {
                                Button(String(localized: "Compare", comment: "Mac common photos sheet: row menu")) { compare(row.id) }
                                // A Copy skips what is already there: nothing to leave out.
                                if row.landing.map({ if case .alreadyThere = $0 { model.action == .copy } else { false } }) == true {
                                    EmptyView()
                                } else if row.isIncluded {
                                    Button(String(localized: "Leave Out", comment: "Mac common photos sheet: row menu")) {
                                        model.setIncluded(false, rows: [row.id])
                                    }
                                } else {
                                    Button(String(localized: "Include", comment: "Mac common photos sheet: row menu")) {
                                        model.setIncluded(true, rows: [row.id])
                                    }
                                }
                            }
                    }
                    .listStyle(.bordered)
                    .alternatingRowBackgrounds()
                    // §6d: Space on one row compares it; on several, checks or unchecks them together.
                    .onKeyPress(.space) {
                        // Rows the list still has: a rescan may have taken some away.
                        let picked = model.rows.filter { selectedRows.contains($0.id) }
                        guard !picked.isEmpty else { return .ignored }
                        if picked.count == 1 {
                            compare(picked[0].id)
                        } else {
                            // Rows a Copy skips (already there) are no choice.
                            let choices = picked.filter { row in
                                if case .alreadyThere? = row.landing, model.action == .copy { false } else { true }
                            }
                            guard !choices.isEmpty else { return .handled }
                            model.setIncluded(!choices.allSatisfy(\.isIncluded), rows: Set(choices.map(\.id)))
                        }
                        return .handled
                    }
                    .contextMenu(forSelectionType: String.self, menu: { _ in EmptyView() }, primaryAction: { ids in
                        // A double-click on one row; several picked is no single photo to show.
                        if ids.count == 1, let id = ids.first { compare(id) }
                    })
                    .onChange(of: model.rows.map(\.id)) { _, ids in selectedRows.formIntersection(ids) }
                    .accessibilityLabel(model.folders.count == 2
                                        ? String(localized: "Same photos in both folders", comment: "Mac common photos sheet: results list")
                                        : String(localized: "Same photos in all folders", comment: "Mac common photos sheet: results list"))
                }
                // Also with no rows: what was left out stays reachable.
                if model.phase == .done, !model.leftOutEntries.isEmpty { leftOutSection }
            }
        }
    }

    /// §6d: opens Compare on this row (one window for the app).
    private func compare(_ rowId: String) {
        guard model.rows.contains(where: { $0.id == rowId }) else { return }
        if let open = dependencies.commonPhotosCompare, open.scan === model {
            open.show(rowId)
        } else {
            dependencies.commonPhotosCompare = MacCommonPhotosCompareModel(scan: model, database: dependencies.database,
                                                                           sources: sources, showing: rowId)
        }
        openWindow(id: MacCommonPhotosCompareWindow.id)
    }

    /// §6d: what the user left out of this set before — never run until
    /// Include.
    private var leftOutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $showsLeftOut) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.leftOutEntries) { entry in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name).lineLimit(1).foregroundStyle(.secondary)
                                    Text("Left out \(entry.leftOutAt.formatted(.dateTime.month(.abbreviated).day()))",
                                         comment: "Mac common photos sheet: Left Out row, when")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(entry.size.formatted(.byteCount(style: .file)))
                                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                                Button(String(localized: "Include", comment: "Mac common photos sheet: Left Out row")) {
                                    model.include([entry.sha256])
                                }
                                .controlSize(.small)
                                .accessibilityLabel(String(localized: "Include \(entry.name)", comment: "Mac common photos sheet: Left Out row, VoiceOver"))
                            }
                            .frame(height: 36)
                            .padding(.leading, 20)
                        }
                    }
                }
                .frame(maxHeight: 112)
            } label: {
                HStack(spacing: 6) {
                    Text("Left Out (\(model.leftOutEntries.count))", comment: "Mac common photos sheet: photos left out of this set")
                        .fontWeight(.semibold)
                    Text("Skipped by every scan and gather of this set", comment: "Mac common photos sheet: Left Out subtitle")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    /// §6c: the set gathered before — when, how many are left out, and the
    /// way to check them all again.
    private func againLine(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock").foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Last gathered \(Self.gatheredDate(date)) · \(model.alreadyGathered.formatted()) already gathered",
                 comment: "Mac common photos sheet: the set gathered before; only new photos are listed")
                .font(.callout).monospacedDigit().foregroundStyle(.secondary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            scanEverythingButton
        }
        .frame(minHeight: 24)
    }

    private var scanEverythingButton: some View {
        Button(String(localized: "Scan Everything", comment: "Mac common photos sheet: check every common photo again, gathered or not")) {
            model.scanEverything()
        }
        .controlSize(.small)
        .disabled(model.isScanning)
        .accessibilityHint(Text("Checks the photos already gathered too.", comment: "Mac common photos sheet: what Scan Everything does"))
    }

    /// §6c: the set has nothing new since it last gathered.
    private func nothingNew(since date: Date) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nothing new since \(Self.gatheredDate(date))",
                 comment: "Mac common photos sheet: the set gathered everything before")
                .fontWeight(.semibold)
            Text(model.alreadyGathered == 1
                 ? String(localized: "The photo these folders share is already in “\(destinationName)”.",
                          comment: "Mac common photos sheet: one photo already gathered")
                 : String(localized: "The \(model.alreadyGathered.formatted()) photos these folders share are already in “\(destinationName)”.",
                          comment: "Mac common photos sheet: photos already gathered"))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            scanEverythingButton
                .padding(.top, 6)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
        // The button stays its own control for VoiceOver and Voice Control.
        .accessibilityElement(children: .contain)
    }

    /// "Nov 3, 2:30 PM" this year; with the year before that.
    private static func gatheredDate(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                        : date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }

    private var destinationName: String {
        model.destination.map { ServerUploadPath.lastComponent(of: $0) } ?? ""
    }

    /// Why results the user saw went (FS-19.08 §6c).
    private func noticeText(_ notice: CommonPhotosScanModel.Notice) -> String {
        switch notice {
        case .moveChecksAgain:
            String(localized: "Moving checks each copy before removing it. Scan again to list the photos.",
                   comment: "Mac common photos sheet: results dropped after switching to Move")
        case .otherDestination:
            String(localized: "This folder has photos of its own already gathered. Scan again to list what's new.",
                   comment: "Mac common photos sheet: results dropped after changing the destination")
        }
    }

    /// The scan stopped on an error: say so above what it found.
    private func failureLine(_ message: String) -> some View {
        Label {
            Text("Couldn't finish checking. Scan to try again. \(message)", comment: "Mac common photos sheet: the scan failed")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(Color(nsColor: .systemRed))
        .lineLimit(2)
    }

    /// Done: "312 photos in all 3 folders · 4.2 GB" — "in both folders" for
    /// two. Before that a count found Same is not a result yet: "Checking ·
    /// 2 of 8 confirmed so far" with "6 of 8 · 1.2 GB left".
    private var headline: String {
        let folders = model.folders.count
        guard model.phase == .done else {
            let confirmed = String(localized: "Checking · \(model.confirmedCount.formatted()) of \(model.candidateCount.formatted()) confirmed so far",
                                   comment: "Mac common photos sheet: headline while checking")
            guard model.isScanning else { return confirmed }
            let left = model.bytesLeft.formatted(.byteCount(style: .file))
            return confirmed + " · " + String(localized: "\(model.checkedFiles.formatted()) of \(model.candidateCount.formatted()), \(left) left",
                                              comment: "Mac common photos sheet: how far the check is")
        }
        let count = model.sameCount
        let bytes = model.sameBytes.formatted(.byteCount(style: .file))
        // §6d: some rows unchecked — the headline counts what the run takes,
        // the number the button shows.
        if model.runCount < model.selectableCount {
            let selected = String(localized: "\(model.runCount.formatted()) of \(count.formatted()) selected",
                                  comment: "Mac common photos sheet: headline, rows the run takes out of all Same rows")
            return selected + " · " + model.runBytes.formatted(.byteCount(style: .file)) + alreadyThereSuffix
        }
        // §6c: a set that gathered before lists only what is new.
        if model.lastGathered != nil, !model.scansEverything {
            let new = count == 1 ? String(localized: "1 new photo", comment: "Mac common photos sheet: headline count, only new photos")
                                 : String(localized: "\(count.formatted()) new photos", comment: "Mac common photos sheet: headline count, only new photos")
            let place = folders == 2 ? String(localized: "in both folders", comment: "Mac common photos sheet: headline, two folders")
                                     : String(localized: "in all \(folders) folders", comment: "Mac common photos sheet: headline, three or more")
            return count == 0 ? String(localized: "No new photos \(place)", comment: "Mac common photos sheet: headline, nothing new")
                              : "\(new) \(place) · \(bytes)" + alreadyThereSuffix
        }
        let photos = count == 1 ? String(localized: "1 photo", comment: "Mac common photos sheet: headline count")
                                : String(localized: "\(count.formatted()) photos", comment: "Mac common photos sheet: headline count")
        let place = folders == 2 ? String(localized: "in both folders", comment: "Mac common photos sheet: headline, two folders")
                                 : String(localized: "in all \(folders) folders", comment: "Mac common photos sheet: headline, three or more")
        return "\(photos) \(place) · \(bytes)" + alreadyThereSuffix
    }

    /// §6d: how many Same photos the destination already holds.
    private var alreadyThereSuffix: String {
        let there = model.alreadyThereCount
        guard there > 0, let destination = model.destination else { return "" }
        let name = ServerUploadPath.lastComponent(of: destination)
        return " · " + String(localized: "\(there.formatted()) already in \(name)",
                              comment: "Mac common photos sheet: headline, Same photos the destination already holds")
    }

    private func count(_ label: String, _ value: Int, done: Bool) -> some View {
        HStack(spacing: 5) {
            if done {
                Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.green)
            } else {
                ProgressView().controlSize(.mini)
            }
            Text(label).foregroundStyle(.secondary)
            Text(value.formatted()).fontWeight(.semibold).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: Keep gathering (FS-19.08 §6c)

    private var keepGatheringRow: some View {
        HStack(spacing: 8) {
            Toggle(String(localized: "Keep gathering new photos", comment: "Mac common photos sheet: the helper runs this set again on its own"),
                   isOn: $keepsGathering)
                .toggleStyle(.checkbox)
                .fixedSize()
            Text(MacAgentLink.keepsWorkingAfterQuit
                 ? String(localized: "Every 15 minutes while this Mac is plugged in.", comment: "Mac common photos sheet: when Keep gathering runs")
                 : String(localized: "Every 15 minutes while this Mac is plugged in and ShotDex is open.",
                          comment: "Mac common photos sheet: when Keep gathering runs, Keep Working After Quit being off"))
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
        .disabled(model.destination == nil)
    }

    private func readKeepGathering() {
        guard let destination = model.destination else { return keepsGathering = false }
        let watch = try? CommonPhotosWatchStore(database: dependencies.database)
            .watch(connectionId: model.connectionId, folders: model.folders, destination: destination)
        keepsGathering = (watch ?? nil)?.isOn ?? false
    }

    /// The choice, saved as the run starts: on, the helper runs the set
    /// from now on with this run's action; off, a set that was gathered
    /// stops.
    @discardableResult
    private func saveKeepGathering() -> Bool {
        guard let destination = model.destination else { return true }
        let store = CommonPhotosWatchStore(database: dependencies.database)
        do {
            if keepsGathering {
                try store.keepGathering(connectionId: model.connectionId, folders: model.folders, destination: destination,
                                        action: model.action)
                // A Move set tells the user when photos are ready (§6c):
                // asked now, while the user is here.
                if model.action == .move { MacCommonPhotosNotices.requestAuthorization() }
                dependencies.watchesChanged()
            } else if let watch = try store.watch(connectionId: model.connectionId, folders: model.folders, destination: destination),
                      watch.isOn {
                try store.stopGathering(id: watch.id)
                dependencies.watchesChanged()
            }
        } catch {
            startError = String(localized: "The run started, but Keep gathering couldn't be saved: \(error.localizedDescription)",
                                comment: "Mac common photos sheet: saving Keep gathering failed")
            return false
        }
        return true
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                footerNote
                Spacer(minLength: 0)
            }
            Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel, action: close)
                .keyboardShortcut(.cancelAction)
    
            if model.phase == .done {
                Button(runTitle) { model.action == .move ? (confirmsMove = true) : start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canRun || isStarting)
            } else if model.isScanning {
                Button(String(localized: "Stop", comment: "Mac common photos sheet: stop the scan")) { model.cancelScan() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(String(localized: "Scan", comment: "Mac common photos sheet: start the scan")) { model.scan() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canScan)
            }
        }
        .frame(height: 28)
    }

    /// The first thing in the way, else what the run button does.
    @ViewBuilder
    private var footerNote: some View {
        if case .selection(let problem)? = model.problem {
            Label(problemText(problem), systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color(nsColor: .systemRed))
                .lineLimit(2)
        } else if model.problem == .noDestination, model.phase == .done {
            Text("Choose where to save the common photos.", comment: "Mac common photos sheet: no destination yet")
                .font(.callout).foregroundStyle(.secondary)
        } else if model.isScanning || (model.phase == .done && model.sameCount > 0) {
            Text(footerText).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// §6d: what happens to the checked rows, and to the others.
    private var footerText: String {
        guard model.phase == .done else {
            return String(localized: "Only Same photos are listed.", comment: "Mac common photos sheet: footer while scanning")
        }
        if model.runCount == 0, model.selectableCount > 0 {
            return String(localized: "Nothing selected. Check a photo to include it.", comment: "Mac common photos sheet: footer, every row unchecked")
        }
        guard model.action == .move else {
            return String(localized: "Unchecked photos stay out of this set.", comment: "Mac common photos sheet: footer, Copy")
        }
        let names = model.folders.map(ServerUploadPath.lastComponent(of:))
        let destination = model.destination.map(ServerUploadPath.lastComponent(of:)) ?? ""
        return names.count == 2
            ? String(localized: "Verified in \(destination), then removed from \(names[0]) and \(names[1]).", comment: "Mac common photos sheet: footer, Move, two folders")
            : String(localized: "Verified in \(destination), then removed from every folder above.", comment: "Mac common photos sheet: footer, Move, three or more folders")
    }

    private func problemText(_ problem: CommonPhotosSelection.Problem) -> String {
        switch problem {
        case .tooFewFolders:
            String(localized: "Choose at least two folders to compare.", comment: "Mac common photos sheet: fewer than two folders")
        case .nested(let outer, let inner):
            String(localized: "“\(ServerUploadPath.lastComponent(of: inner))” is inside “\(ServerUploadPath.lastComponent(of: outer))”. Choose folders that don't overlap.",
                   comment: "Mac common photos sheet: one folder inside another")
        case .destinationInsideSource(let source):
            String(localized: "“\(model.destination.map { ServerUploadPath.lastComponent(of: $0) } ?? "")” is inside “\(ServerUploadPath.lastComponent(of: source))”, one of the folders above. Save somewhere else.",
                   comment: "Mac common photos sheet: the destination is inside a folder being compared")
        }
    }

    private var runTitle: String {
        // Nothing to run: the verb alone, dimmed.
        guard model.runCount > 0 else {
            return model.action == .move ? String(localized: "Move", comment: "Mac common photos sheet: run button, nothing to move")
                                         : String(localized: "Copy", comment: "Mac common photos sheet: run button, nothing to copy")
        }
        let count = model.runCount.formatted()
        return model.action == .move
            ? String(localized: "Move \(count)…", comment: "Mac common photos sheet: run button, a confirmation follows")
            : String(localized: "Copy \(count)", comment: "Mac common photos sheet: run button")
    }

    // MARK: Move

    /// "Move 280 photos to “Shared”?" (FS-19.08 §4).
    private var moveTitle: String {
        let destination = model.destination.map { ServerUploadPath.lastComponent(of: $0) } ?? ""
        return model.runCount == 1
            ? String(localized: "Move 1 photo to “\(destination)”?", comment: "Mac common photos: Move confirmation title")
            : String(localized: "Move \(model.runCount.formatted()) photos to “\(destination)”?", comment: "Mac common photos: Move confirmation title")
    }

    /// "Each photo is copied to “Shared” and verified, then removed from
    /// Tuấn and Vợ. The server has no Trash; you can undo the run from Activity." (§4, §6b)
    private var moveMessage: String {
        MacCommonPhotosWords.moveMessage(folders: model.folders,
                                         destination: model.destination.map { ServerUploadPath.lastComponent(of: $0) } ?? "")
    }

    private func start() {
        guard !isStarting, let made = model.makeRun() else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            try dependencies.commonPhotos.start(made.run, items: made.items)
            if let problem = dependencies.commonPhotos.entries[made.run.id]?.problem {
                startError = problem
                return
            }
            // Saved once the run is under way; a failure keeps the sheet
            // open to say so.
            guard saveKeepGathering() else { return }
            close()
            // The run's window opens as it starts (FS-19.08 §7).
            openWindow(id: MacCommonPhotosRunWindow.id, value: made.run.id)
        } catch {
            startError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// One Same photo: its thumbnail from the index when a source holds it, its
/// name and where it is in each folder, and its size (§6d: only Same rows).
private struct MacCommonPhotosRow: View {
    let row: CommonPhotosScanModel.Row
    /// The destination folder's name, for the plan line (§6d).
    let destination: String?
    let action: CommonPhotosRun.Action
    let database: AppDatabase
    let sources: [(source: SourceStore.Source, connection: FileServer)]
    /// Checks or unchecks the row (§6d).
    let setIncluded: (Bool) -> Void
    /// Opens Compare on it.
    let compare: () -> Void
    @State private var thumbnail: CGImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // A Copy skips what is already there: nothing to choose on that row.
            if isAlreadyThere, action == .copy {
                Color.clear.frame(width: 14, height: 14)
            } else {
                Toggle(isOn: Binding(get: { row.isIncluded }, set: setIncluded)) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel(row.name)
                    .accessibilityValue(row.isIncluded
                        ? String(localized: "Included", comment: "Mac common photos sheet: row checkbox, VoiceOver value")
                        : String(localized: "Left out", comment: "Mac common photos sheet: row checkbox, VoiceOver value"))
            }
            MacTheme.fill2
                .frame(width: 28, height: 28)
                .overlay {
                    if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().scaledToFill() }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .opacity(isAlreadyThere ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).lineLimit(1).foregroundStyle(isAlreadyThere ? .secondary : .primary)
                // Where it comes from, then where it goes: the destination name never truncates.
                HStack(spacing: 0) {
                    Text(row.paths).lineLimit(1).truncationMode(.middle)
                    if let landing = landingText { Text(landing).lineLimit(1).fixedSize() }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .help(row.fullPaths + (landingText.map { "\n" + $0 } ?? ""))
            if isHovered {
                Button(action: compare) { Image(systemName: "rectangle.split.2x1") }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Compare (Space)", comment: "Mac common photos sheet: row button"))
                    .accessibilityLabel(String(localized: "Compare", comment: "Mac common photos sheet: row button"))
            }
            Text(row.size.formatted(.byteCount(style: .file)))
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(note ?? "").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                .frame(width: 124, alignment: .leading)
        }
        .frame(height: 40)
        .onHover { isHovered = $0 }
        .accessibilityAction(named: String(localized: "Compare", comment: "Mac common photos sheet: row action, VoiceOver"), compare)
        .task(id: row.serverPath) {
            thumbnail = await MacCommonPhotosPreview.load(serverPath: row.serverPath, sources: sources, database: database,
                                                         maxPixelSize: 96)?.image
        }
    }

    private var isAlreadyThere: Bool {
        if case .alreadyThere = row.landing { true } else { false }
    }

    /// " → Shared/IMG_0001 (2).JPG" once planned; on a Move, " → already in
    /// Shared" (the note column says what it removes).
    private var landingText: String? {
        guard let destination, let landing = row.landing else { return nil }
        switch landing {
        case .name(let name): return "\u{00A0}→ " + ServerUploadPath.join(destination, name)
        case .alreadyThere:
            guard action == .move else { return nil }
            return "\u{00A0}→ " + String(localized: "already in \(destination)", comment: "Mac common photos sheet: row plan, a Move whose bytes the destination holds")
        }
    }

    /// Already there (Copy skips it), or on a Move the copies it takes out of
    /// the folders — already there or not; unchecked, that it stays out.
    private var note: String? {
        if !row.isIncluded, !(isAlreadyThere && action == .copy) {
            return String(localized: "Left out from now on", comment: "Mac common photos sheet: row, unchecked")
        }
        if isAlreadyThere, action == .copy {
            return String(localized: "Already in \(destination ?? "")", comment: "Mac common photos sheet: row, the destination holds these bytes")
        }
        guard action == .move, row.landing != nil else { return nil }
        return row.copies == 1
            ? String(localized: "Removes 1 copy", comment: "Mac common photos sheet: row, a Move removes this copy")
            : String(localized: "Removes \(row.copies) copies", comment: "Mac common photos sheet: row, a Move removes these copies")
    }

}

