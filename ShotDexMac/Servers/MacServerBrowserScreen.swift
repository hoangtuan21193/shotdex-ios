import AppKit
import SwiftUI

/// A server source in the Library window (board `MAC_ServerBrowser`,
/// FS-19.03 §4): the folder columns on the left, the open folder's folders
/// and photos on the right, the path bar along the bottom; Back/Forward,
/// Icons/List, New Folder, Rescan, Show Inspector, search and Upload… in the
/// toolbar.
struct MacServerBrowserScreen: View {
    let source: SourceStore.Source
    @Environment(MacDependencies.self) private var dependencies
    @State private var model: MacServerBrowserModel?
    @State private var isMissingConnection = false

    var body: some View {
        Group {
            if let model {
                MacServerBrowserContent(model: model)
            } else if isMissingConnection {
                ContentUnavailableView(String(localized: "Connection Not Found", comment: "Mac server browser: the source's connection was deleted"),
                                       systemImage: "server.rack",
                                       description: Text("Add the server again in Settings › Servers.",
                                                         comment: "Mac server browser: how to fix a missing connection"))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: source.id) {
            let previous = model
            model = nil
            await previous?.close()
            // Off the main actor: a read here waits for a free reader of the
            // pool, and a long background read once held them all for minutes
            // (hang report 2026-11-08).
            let sources = dependencies.sources
            let servers = dependencies.fileServers
            let sourceId = source.id
            let server = await Task.detached(priority: .userInitiated) {
                ((try? sources.serverConnections())?[sourceId]).flatMap { try? servers.fetch(id: $0) }
            }.value
            guard !Task.isCancelled else { return }
            guard let server else {
                isMissingConnection = true
                return
            }
            isMissingConnection = false
            var start = ""
            var layout = MacServerBrowserModel.Layout.icons
            #if DEBUG
            start = MacDemoLibrary.serverPath ?? ""
            layout = MacDemoLibrary.serverLayout.flatMap(MacServerBrowserModel.Layout.init(rawValue:)) ?? .icons
            #endif
            let model = MacServerBrowserModel(sourceId: source.id, sourceName: source.name, server: server,
                                              client: dependencies.lockedClient(for: server),
                                              refresh: dependencies.serverSources, database: dependencies.database, start: start)
            model.layout = layout
            self.model = model
        }
        // A renamed source keeps its browser; only the name changes.
        .onChange(of: source.name) { _, name in model?.rename(to: name) }
        .onDisappear {
            if let model { Task { await model.close() } }
        }
    }
}

/// The browser once its connection is known.
private struct MacServerBrowserContent: View {
    @Bindable var model: MacServerBrowserModel
    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.openSettings) private var openSettings
    @FocusState private var gridFocused: Bool
    @State private var hasPreselected = false
    @State private var isNamingFolder = false
    @State private var newFolderName = ""
    /// Why the last name was refused, shown in the name box asked again.
    @State private var nameProblem: String?
    @State private var rightClickMonitor: Any?
    /// Runs seen finished, so each ending refreshes the listing once.
    @State private var knownFinished: Set<String> = []

    /// Board `MAC_ServerBrowser`: two columns of 186 beside the files, 12
    /// apart; 8 in from the sidebar, 16 from the window's right edge.
    private static let columnWidth: CGFloat = 186
    private static let gap: CGFloat = 12
    /// Five tiles across the files at the board's 1440 width.
    private static let tileMinimum: CGFloat = 150
    /// The board's search field.
    private static let searchWidth: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            MacCommonPhotosResumeBanner(connectionId: model.server.id)
            HStack(alignment: .top, spacing: Self.gap) {
                columnBrowser
                    .padding(.bottom, Self.gap)
                files
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.top, 8)
            Divider()
            pathBar
        }
        .navigationTitle(model.title)
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .task(id: model.path) {
            await model.visit()
            #if DEBUG
            if !hasPreselected, let names = MacDemoLibrary.serverSelect, model.contents != nil {
                hasPreselected = true
                model.selectFolders(named: names)
                if ProcessInfo.processInfo.arguments.contains("-ShotDexServerFindCommon") { model.findCommonPhotosInSelection() }
            }
            #endif
        }
        .focusedSceneValue(\.macServerBrowser, model)
        .sheet(item: $model.commonPhotosRequest) { request in
            MacCommonPhotosSheet(request: request, server: model.server)
        }
        .sheet(item: $model.uploadRequest) { request in
            MacServerUploadSheet(request: request) { model.uploadRequest = nil }
        }
        // New Folder: a name, then the folder made where the browser stands (it stays there).
        .alert(String(localized: "New Folder", comment: "Mac server browser: name a new folder, title"), isPresented: $isNamingFolder) {
            TextField(String(localized: "Name", comment: "Mac server browser: new folder name field"), text: $newFolderName)
            Button(String(localized: "Create", comment: "Mac server browser: make the folder")) {
                let name = newFolderName
                Task {
                    // Refused or failed: asked again with the name kept and the reason under it.
                    if let problem = await model.createFolder(named: name) {
                        nameProblem = problem
                        newFolderName = name
                        isNamingFolder = true
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button(String(localized: "Cancel", comment: "Mac server browser: don't make a folder"), role: .cancel) {}
        } message: {
            Text(nameProblem ?? String(localized: "In “\(model.title(for: model.path))” on \(model.sourceName).",
                                       comment: "Mac server browser: where New Folder makes it"))
        }
        // An upload into this connection ended: Rescan, so the new files are indexed and get thumbnails.
        .onChange(of: dependencies.uploads.entries.filter { $0.model.stage == .finished && $0.model.selectedServerId == model.server.id }.count) {
            model.rescan()
        }
        // Show CSV in Browser: open the run's destination here.
        .onChange(of: dependencies.commonPhotos.browserRequest?.path, initial: true) {
            guard let request = dependencies.commonPhotos.browserRequest, request.connectionId == model.server.id else { return }
            dependencies.commonPhotos.browserRequest = nil
            let root = ServerUploadPath.normalizedFolder(model.server.folder)
            let destination = ServerUploadPath.normalizedFolder(request.path)
            if root.isEmpty {
                model.go(to: destination)
            } else if destination.hasPrefix(root + "/") {
                model.go(to: String(destination.dropFirst(root.count + 1)))
            }
        }
        // Run Again: the sheet on the run's set, scanning only new photos.
        .onChange(of: dependencies.commonPhotos.runAgainRequest?.id, initial: true) {
            guard let run = dependencies.commonPhotos.runAgainRequest, run.connectionId == model.server.id else { return }
            dependencies.commonPhotos.runAgainRequest = nil
            model.commonPhotosRequest = MacCommonPhotosRequest(connectionId: run.connectionId, sourceId: model.sourceId,
                                                               folders: run.folders, destination: run.destination,
                                                               action: run.action, scansAtOnce: true)
        }
        // A run on this connection ended: what the browser listed is stale.
        // Keyed on `generation` (runs starting and ending), not on progress.
        .onChange(of: dependencies.commonPhotos.generation) {
            let finished = Set(dependencies.commonPhotos.entries.values.filter(\.isFinished).map(\.id))
            let ended = finished.subtracting(knownFinished).compactMap { dependencies.commonPhotos.entries[$0]?.run }
            knownFinished = finished
            guard !ended.isEmpty else { return }
            #if DEBUG
            // `-ShotDexCommonPhotosRunAfterScan`: open the destination, to see what landed.
            if ProcessInfo.processInfo.arguments.contains("-ShotDexCommonPhotosRunAfterScan"), let run = ended.first {
                let root = ServerUploadPath.normalizedFolder(model.server.folder)
                let destination = ServerUploadPath.normalizedFolder(run.destination)
                model.go(to: root.isEmpty ? destination : String(destination.dropFirst(root.count + 1)))
            }
            #endif
            if ended.contains(where: { $0.connectionId == model.server.id }) { model.refreshListings() }
        }
        .onAppear {
            // A right-click retargets the selection before its menu opens;
            // the event goes on to the menu untouched.
            rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [model] event in
                model.secondaryClick()
                return event
            }
        }
        .onDisappear {
            if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
            rightClickMonitor = nil
        }
        .alert(rescanAlertTitle, isPresented: Binding(get: { model.rescanProblem != nil }, set: { if !$0 { model.rescanProblem = nil } })) {
            Button(String(localized: "OK", comment: "Mac server browser: dismiss the Rescan alert"), role: .cancel) {}
        } message: {
            Text(rescanAlertMessage)
        }
    }

    /// "NAS Home · SMB · indexed 5 min ago".
    private var subtitle: String {
        var parts = [model.sourceName, model.server.transferProtocol.title]
        if model.isRescanning {
            parts.append(String(localized: "Rescanning…", comment: "Mac server browser subtitle: Rescan is running"))
        } else if let lastIndexed = model.lastIndexed {
            let when = lastIndexed.formatted(.relative(presentation: .named))
            parts.append(String(localized: "indexed \(when)", comment: "Mac server browser subtitle: when the index last read the source"))
        }
        return parts.joined(separator: " · ")
    }

    private var rescanAlertTitle: String {
        String(localized: "Rescan Didn't Finish", comment: "Mac server browser: Rescan stopped or did not run")
    }

    private var rescanAlertMessage: String {
        switch model.rescanProblem {
        case .stopped(let error): error.errorDescription ?? ""
        case .disconnected:
            String(localized: "\(model.sourceName) went away during the Rescan. What was read is kept; the rest is read when it's back.",
                   comment: "Mac server browser: the server dropped mid-Rescan")
        case .notRun:
            String(localized: "The connection for \(model.sourceName) couldn't be found. Check it in Settings › Servers.",
                   comment: "Mac server browser: Rescan had no connection to use")
        case nil: ""
        }
    }

    // MARK: Columns

    private var columnBrowser: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.columns.enumerated()), id: \.element.id) { index, column in
                if index > 0 { Divider() }
                columnView(column)
            }
        }
        .frame(width: Self.columnWidth * 2, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Folders on \(model.sourceName)", comment: "Mac server browser: the folder columns"))
    }

    private func columnView(_ column: MacServerBrowserModel.Column) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(column.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.contents(of: column.path)?.folders ?? [], id: \.self) { name in
                        MacServerColumnRow(name: name, column: column, model: model)
                    }
                }
                .padding(4)
            }
            .overlay {
                if case .loading = model.listings[column.path] ?? .loading { ProgressView().controlSize(.small) }
            }
            Divider()
            Text(columnFoot(column.path))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
        .frame(width: Self.columnWidth)
    }

    /// "7 folders" · "9 folders · 1,102 photos".
    private func columnFoot(_ path: String) -> String {
        guard let contents = model.contents(of: path) else { return "" }
        var parts = [Self.folderCount(contents.folders.count)]
        if !contents.photos.isEmpty { parts.append(Self.photoCount(contents.photos.count)) }
        let picked = model.selectedFolderPaths.count
        if path == model.selectionFolder, picked > 0 {
            parts.append(String(localized: "\(picked.formatted()) selected", comment: "Mac server browser column foot: folders picked in it"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Files

    private var files: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            switch model.listing {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                failure(error)
            case .loaded:
                if model.items.isEmpty {
                    ContentUnavailableView(model.searchText.isEmpty
                                           ? String(localized: "No Photos", comment: "Mac server browser: the folder has no photos or folders")
                                           : String(localized: "No Results", comment: "Mac server browser: nothing matches the search"),
                                           systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.layout == .icons {
                    grid
                } else {
                    table
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Board: the folder's name, the counts line, Sort By on the right.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.title).font(.title3.weight(.semibold)).lineLimit(1)
            Text(countsLine).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            Spacer(minLength: 8)
            Button { model.toggleSortDirection() } label: {
                HStack(spacing: 4) {
                    Text("Name", comment: "Mac server browser: Sort By Name")
                    Image(systemName: model.isAscending ? "arrow.up" : "arrow.down").imageScale(.small).fontWeight(.bold)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Sort By Name", comment: "Mac server browser: sort control"))
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .frame(height: 36, alignment: .bottom)
    }

    /// "1 folder · 36 photos · 2 other files hidden".
    private var countsLine: String {
        guard let contents = model.contents else { return "" }
        var parts: [String] = []
        if !contents.folders.isEmpty { parts.append(Self.folderCount(contents.folders.count)) }
        if !contents.photos.isEmpty || contents.folders.isEmpty { parts.append(Self.photoCount(contents.photos.count)) }
        let hidden = contents.hiddenFileCount
        if hidden > 0 {
            parts.append(hidden == 1
                         ? String(localized: "1 other file hidden", comment: "Mac server browser: files that are not photos")
                         : String(localized: "\(hidden.formatted()) other files hidden", comment: "Mac server browser: files that are not photos"))
        }
        return parts.joined(separator: " · ")
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileMinimum), spacing: MacGridMetrics.spacing)],
                      spacing: MacGridMetrics.spacing) {
                ForEach(model.items) { item in
                    MacServerTile(item: item, copy: copy(item), folderMeta: folderMeta(item),
                                  isSelected: model.isSelected(item, in: model.path), model: model)
                        // The single click acts at once; the double click is
                        // seen alongside it, never waited for.
                        .onTapGesture {
                            let flags = NSEvent.modifierFlags
                            gridFocused = true
                            model.click(item, extendsSelection: flags.contains(.command), extendsRange: flags.contains(.shift))
                        }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            if case .folder(let name) = item { model.open(folder: name) }
                        })
                        .contextMenu {
                            MacServerFolderMenu(model: model, item: item, folder: model.path)
                        }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onKeyPress(.return) { model.openSelectedFolder() ? .handled : .ignored }
    }

    private var table: some View {
        Table(model.items, selection: Binding(get: { model.openFolderSelection }, set: { model.setSelection($0) })) {
            TableColumn(String(localized: "Name", comment: "Mac server browser list: column")) { item in
                HStack(spacing: 6) {
                    Image(systemName: itemSymbol(item))
                        .foregroundStyle(MacTheme.accent)
                        .frame(width: 20, height: 20)
                    Text(item.name).lineLimit(1)
                }
                .frame(height: 20)
            }
            TableColumn(String(localized: "Kind", comment: "Mac server browser list: column")) { item in
                Text(kind(item)).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
            TableColumn(String(localized: "Size", comment: "Mac server browser list: column")) { item in
                if case .photo(let photo) = item {
                    Text(photo.totalBytes.formatted(.byteCount(style: .file))).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .width(min: 60, ideal: 80)
            TableColumn(String(localized: "Date Modified", comment: "Mac server browser list: column")) { item in
                if let date = modified(item) {
                    Text(date.formatted(date: .abbreviated, time: .shortened)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 150)
        }
        .alternatingRowBackgrounds()
        // A right-click acts on the selection, or on the row under the
        // pointer when that is not picked; double-click and Return open.
        .contextMenu(forSelectionType: String.self) { ids in
            let folders = model.folderPaths(forIds: ids)
            if folders.count == 1 {
                Button(String(localized: "Open", comment: "Mac server browser context menu: open the folder")) { model.go(to: folders[0]) }
            } else if CommonPhotosEntry.canFind(folders) {
                MacFindCommonPhotosButton(model: model, folders: folders)
            }
        } primaryAction: { ids in
            guard ids.count == 1, let id = ids.first, let item = model.items.first(where: { $0.id == id }),
                  case .folder(let name) = item else { return }
            model.open(folder: name)
        }
    }

    private func itemSymbol(_ item: MacServerBrowserItem) -> String {
        if case .folder = item { "folder" } else { "photo" }
    }

    private func kind(_ item: MacServerBrowserItem) -> String {
        switch item {
        case .folder: String(localized: "Folder", comment: "Mac server browser list: kind of a folder")
        case .photo(let photo): photo.badge
        }
    }

    private func modified(_ item: MacServerBrowserItem) -> Date? {
        switch item {
        case .folder(let name): model.contents?.folderModified[name]
        case .photo(let photo): photo.modified
        }
    }

    private func copy(_ item: MacServerBrowserItem) -> MacServerCopy? {
        if case .photo(let photo) = item { model.copy(of: photo) } else { nil }
    }

    /// "12 photos" under a folder tile, once that folder has been listed.
    private func folderMeta(_ item: MacServerBrowserItem) -> String? {
        guard case .folder(let name) = item,
              let contents = model.contents(of: ServerUploadPath.join(model.path, name)) else { return nil }
        return Self.photoCount(contents.photos.count)
    }

    /// Off or away → Try Again; a password or folder the server refuses →
    /// the connection's settings, where it can be fixed (FS-19.03 §6).
    private func failure(_ error: RemoteFileError) -> some View {
        let unreachable: Bool
        let fixInSettings: Bool
        switch error {
        case .unreachable, .connectionLost: (unreachable, fixInSettings) = (true, false)
        case .authenticationFailed, .folderMissing, .permissionDenied, .hostKeyChanged, .hostKeyUntrusted, .localNetworkDenied:
            (unreachable, fixInSettings) = (false, true)
        default: (unreachable, fixInSettings) = (false, false)
        }
        return ContentUnavailableView {
            Label(unreachable
                  ? String(localized: "\(model.sourceName) Isn't Reachable", comment: "Mac server browser: the server is off or away")
                  : String(localized: "Couldn't Open Folder", comment: "Mac server browser: listing failed"),
                  systemImage: "exclamationmark.triangle")
        } description: {
            Text(unreachable
                 ? String(localized: "Its photos stay in your library with saved previews.", comment: "Mac server browser: offline explanation")
                 : (error.errorDescription ?? ""))
        } actions: {
            if fixInSettings {
                Button(String(localized: "Open Settings…", comment: "Mac server browser: fix the connection in Settings › Servers")) {
                    openSettings()
                }
            } else {
                Button(String(localized: "Try Again", comment: "Mac server browser: list the folder again")) { model.retry() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Path bar

    /// Board: the crumbs from the source down to the open folder, then
    /// "3 of 37 selected · 15.21 GB free of 152.09 GB".
    private var pathBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.crumbs.enumerated()), id: \.element) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right").imageScale(.small).fontWeight(.bold).foregroundStyle(.secondary)
                }
                Button { model.go(to: crumb) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: crumb.isEmpty ? "server.rack" : "folder").foregroundStyle(MacTheme.accent)
                        Text(model.title(for: crumb))
                            .fontWeight(crumb == model.path ? .semibold : .regular)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)
            Text(pathBarStatus)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .frame(height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Path", comment: "Mac server browser: the path bar"))
    }

    private var pathBarStatus: String {
        var parts: [String] = []
        // The open folder's picks only; a column's are counted at its foot.
        let picked = model.openFolderSelection.count
        if picked > 0 {
            let total = model.items.count
            parts.append(String(localized: "\(picked.formatted()) of \(total.formatted()) selected",
                                comment: "Mac server browser path bar: how many items are selected"))
        }
        if let storage = model.storage { parts.append(storage.footerText) }
        return parts.joined(separator: " · ")
    }

    // MARK: Toolbar

    /// Upload…: photos and videos picked on this Mac (an open panel, as
    /// Finder would) go to the upload sheet, locked to this server and folder.
    private func pickFilesToUpload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie, .rawImage]
        panel.prompt = String(localized: "Choose", comment: "Mac server browser: the open panel's button for Upload…")
        panel.message = String(localized: "Choose photos to upload into “\(model.title(for: model.path))” on \(model.sourceName).",
                               comment: "Mac server browser: Upload… open panel message")
        #if DEBUG
        // `-ShotDexUploadFiles a.jpg,b.jpg`: the panel's answer, for a test.
        if let files = MacDemoLibrary.uploadFiles {
            model.uploadRequest = MacUploadRequest(files: files, serverId: model.server.id, folder: model.openFolderOnServer)
            return
        }
        #endif
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        model.uploadRequest = MacUploadRequest(files: panel.urls, serverId: model.server.id, folder: model.openFolderOnServer)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.goBack() } label: { Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left") }
                .disabled(!model.canGoBack)
            Button { model.goForward() } label: { Label(String(localized: "Forward", comment: "Mac toolbar"), systemImage: "chevron.right") }
                .disabled(!model.canGoForward)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker(selection: $model.layout) {
                Label(String(localized: "Icons", comment: "Mac server browser view mode"), systemImage: "square.grid.2x2")
                    .tag(MacServerBrowserModel.Layout.icons)
                Label(String(localized: "List", comment: "Mac toolbar view mode"), systemImage: "list.bullet")
                    .tag(MacServerBrowserModel.Layout.list)
            } label: {
                Text("View", comment: "Mac toolbar view mode picker")
            }
            .pickerStyle(.segmented)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            // The inspector is drawn and not offered yet: it has nothing to show for a server file (FS-19.03 §4).
            Button { newFolderName = ""; nameProblem = nil; isNamingFolder = true } label: {
                Label(String(localized: "New Folder", comment: "Mac server browser toolbar"), systemImage: "folder.badge.plus")
            }
            // The top of an SMB connection lists shares, which ShotDex can't make (FS-17.01 §4).
            .disabled(model.server.transferProtocol == .smb && model.openFolderOnServer.isEmpty)
            .help(String(localized: "New folder in “\(model.title(for: model.path))”", comment: "Mac server browser: New Folder tooltip"))
            Button { model.rescan() } label: {
                Label(String(localized: "Rescan", comment: "Mac server browser toolbar: compare the server's listing again"),
                      systemImage: "arrow.clockwise")
            }
            .disabled(model.isRescanning)
            .help(String(localized: "Compare the server's files with the library again", comment: "Mac server browser: Rescan tooltip"))
            Button { } label: {
                Label(String(localized: "Show Inspector", comment: "Mac toolbar"), systemImage: "sidebar.right")
            }
            .disabled(true)
        }
        groupGap
        ToolbarItem(placement: .primaryAction) {
            MacToolbarSearchField(text: $model.searchText,
                                  prompt: String(localized: "Search \(model.sourceName)", comment: "Mac server browser: search field placeholder"))
                .frame(width: Self.searchWidth)
        }
        groupGap
        ToolbarItem(placement: .primaryAction) {
            // Upload…: files from this Mac into the open folder (FS-19.03 §4), through the upload sheet.
            Button { pickFilesToUpload() } label: {
                Label(String(localized: "Upload…", comment: "Mac server browser toolbar: upload to this folder"),
                      systemImage: "arrow.up.to.line")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .help(String(localized: "Upload files from this Mac into “\(model.title(for: model.path))”", comment: "Mac server browser: Upload… tooltip"))
            .accessibilityLabel(String(localized: "Upload to Server…", comment: "Mac server browser toolbar"))
        }
    }

    /// macOS 26 draws neighbouring items as one glass capsule; the board
    /// keeps the search field and Upload… in their own.
    @ToolbarContentBuilder
    private var groupGap: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
    }

    // MARK: Counts

    static func folderCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 folder", comment: "Mac server browser: number of folders")
                   : String(localized: "\(count.formatted()) folders", comment: "Mac server browser: number of folders")
    }

    static func photoCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 photo", comment: "Mac toolbar subtitle")
                   : String(localized: "\(count.formatted()) photos", comment: "Mac toolbar subtitle")
    }
}

/// One folder in a column: picked on the way down (`rowSel`), the open one
/// (`accentSoft`), hovered at half `rowSel`.
private struct MacServerColumnRow: View {
    let name: String
    let column: MacServerBrowserModel.Column
    let model: MacServerBrowserModel
    @State private var isHovered = false

    var body: some View {
        let isOnPath = column.selected == name
        let childPath = ServerUploadPath.join(column.path, name)
        // The open folder's row is amber unless folders are picked inside
        // it: then the picked column has the amber and this one goes grey,
        // as in Finder (board `MAC_CommonPhotos`).
        let picksInside = !model.selection.isEmpty && model.selectionFolder == childPath
        let isOpen = isOnPath && childPath == model.path && !picksInside
        let isPicked = model.isSelected(.folder(name), in: column.path)
        Button {
            // ⌘/⇧-click picks folders in this column (FS-19.08 §3); a plain
            // click opens, as in Finder's columns.
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) || flags.contains(.shift) {
                model.click(.folder(name), in: column.path,
                            extendsSelection: flags.contains(.command), extendsRange: flags.contains(.shift))
            } else {
                model.go(to: childPath)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .foregroundStyle(MacTheme.accent)
                    .frame(width: 15)
                Text(name)
                    .fontWeight(isOpen || isPicked ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let photos = model.contents(of: childPath)?.photos.count, photos > 0 {
                    Text(photos.formatted()).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 26)
            .background(background(isOnPath: isOnPath, isOpen: isOpen || isPicked), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isOver in
            isHovered = isOver
            model.pointer(isOver: isOver, item: .folder(name), in: column.path)
        }
        .accessibilityAddTraits(isOnPath || isPicked ? .isSelected : [])
        .contextMenu { MacServerFolderMenu(model: model, item: .folder(name), folder: column.path) }
    }

    private func background(isOnPath: Bool, isOpen: Bool) -> Color {
        if isOpen { return MacTheme.accentSoft }
        if isOnPath { return MacTheme.rowSelection }
        return isHovered ? MacTheme.rowSelection.opacity(0.5) : .clear
    }
}

/// One tile of the open folder (board `MAC_ServerBrowser`): a folder glyph
/// with its name; a photo filled square with its format top-left and its
/// marks and name over a shade; a photo the index has no preview for yet,
/// its glyph and name. Picked = 3pt amber ring, as in the Library grid;
/// hovered = half `rowSel` over it.
private struct MacServerTile: View {
    let item: MacServerBrowserItem
    let copy: MacServerCopy?
    let folderMeta: String?
    let isSelected: Bool
    let model: MacServerBrowserModel
    @State private var thumbnail: CGImage?
    @State private var isHovered = false

    var body: some View {
        MacTheme.fill2
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipped()
            .overlay { if let photo, thumbnail != nil { photoMarks(photo) } }
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(MacTheme.accent, lineWidth: 3)
                } else if isHovered {
                    MacTheme.rowSelection.opacity(0.5)
                }
            }
            .contentShape(Rectangle())
            .onHover { isOver in
                isHovered = isOver
                model.pointer(isOver: isOver, item: item, in: model.path)
            }
            .task(id: copy?.copyId) {
                guard let copyId = copy?.copyId else {
                    thumbnail = nil
                    return
                }
                thumbnail = await model.thumbnail(copyId: copyId)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var photo: ServerPhoto? {
        if case .photo(let photo) = item { photo } else { nil }
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .folder(let name):
            VStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(MacTheme.accent)
                VStack(spacing: 2) {
                    Text(name).font(.callout).lineLimit(1)
                    if let folderMeta { Text(folderMeta).font(.subheadline).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 8)
            }
        case .photo(let photo):
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.title2)
                    Text(photo.primary.name).font(.subheadline).monospacedDigit().lineLimit(1).padding(.horizontal, 6)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    /// The format top-left; the pick flag, the stars and the name over a
    /// 30pt shade at the bottom (FS-01.12 §7, as on board `Main`).
    private func photoMarks(_ photo: ServerPhoto) -> some View {
        ZStack {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 30)
                .frame(maxHeight: .infinity, alignment: .bottom)
            Text(photo.badge)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4))
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 5) {
                if copy?.flag == .pick {
                    Image(systemName: "flag.fill").imageScale(.small)
                        .accessibilityLabel(String(localized: "Picked", comment: "Mac server browser: pick flag on a tile"))
                }
                if let rating = copy?.rating, rating > 0 {
                    HStack(spacing: 1) {
                        Image(systemName: "star.fill").imageScale(.small)
                        Text(rating.formatted()).font(.caption2.weight(.semibold)).monospacedDigit()
                    }
                }
                Text(photo.primary.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private var accessibilityText: String {
        switch item {
        case .folder(let name):
            return [String(localized: "Folder, \(name)", comment: "Mac server browser: VoiceOver label of a folder tile"), folderMeta]
                .compactMap { $0 }.joined(separator: ", ")
        case .photo(let photo):
            var words = ["\(photo.primary.name), \(photo.badge)"]
            if let rating = copy?.rating, rating > 0 {
                words.append(rating == 1 ? String(localized: "1 star", comment: "Mac server browser: VoiceOver rating")
                                         : String(localized: "\(rating) stars", comment: "Mac server browser: VoiceOver rating"))
            }
            if copy?.flag == .pick { words.append(String(localized: "Picked", comment: "Mac server browser: pick flag on a tile")) }
            if thumbnail == nil {
                words.append(String(localized: "preview loading", comment: "Mac server browser: VoiceOver, a photo with no preview yet"))
            }
            return words.joined(separator: ", ")
        }
    }
}

/// The toolbar's search field at the board's width — `.searchable` takes
/// the toolbar's whole trailing room and always sits last, after Upload….
private struct MacToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// A folder's right-click menu (FS-19.08 §3): Open for one folder, then
/// Find Common Photos… — dimmed under two folders. It acts on the picked
/// folders when the one under the pointer is among them, else on that one.
private struct MacServerFolderMenu: View {
    let model: MacServerBrowserModel
    let item: MacServerBrowserItem
    let folder: String

    var body: some View {
        if case .folder(let name) = item {
            // Context menus leave out what cannot run (HIG): Open for one
            // folder, Find Common Photos… from two.
            let folders = model.commonPhotosFolders(for: item, in: folder)
            if CommonPhotosEntry.canFind(folders) {
                MacFindCommonPhotosButton(model: model, folders: folders)
            } else {
                Button(String(localized: "Open", comment: "Mac server browser context menu: open the folder")) {
                    model.go(to: ServerUploadPath.join(folder, name))
                }
            }
        }
    }
}

/// Find Common Photos… in a context menu, for `folders` (paths under the
/// source's root). ⇧⌘F lives on the File menu's item only.
private struct MacFindCommonPhotosButton: View {
    let model: MacServerBrowserModel
    let folders: [String]

    var body: some View {
        Button(String(localized: "Find Common Photos…", comment: "Mac: compare folders for the same photos (FS-19.08)")) {
            model.findCommonPhotos(folders: folders, connectionId: model.server.id, sourceId: model.sourceId)
        }
    }
}

/// The server browser of the key window, for File › Find Common Photos….
struct MacServerBrowserFocusKey: FocusedValueKey {
    typealias Value = MacServerBrowserModel
}

extension FocusedValues {
    var macServerBrowser: MacServerBrowserModel? {
        get { self[MacServerBrowserFocusKey.self] }
        set { self[MacServerBrowserFocusKey.self] = newValue }
    }
}
