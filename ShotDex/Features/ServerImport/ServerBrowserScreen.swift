import SwiftUI

/// The Files-style browser of one connection (FS-17.01 §2): ‹ › through the
/// visit, the title menu up the tree, ⋯ with Select, New Folder, Icons/List,
/// Sort By and View Options; folders and photos drawn the same way. In
/// choose-folder mode (FS-17.01 §5) it is the folder picker of the upload
/// sheet and the connection form. Tier B.
struct ServerBrowserScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3
    let model: ServerBrowserModel
    /// Choose-folder mode: the folder picked.
    var onChoose: ((String) -> Void)?
    @State private var downloadModel: ServerDownloadModel?
    @State private var viewing: ServerPhoto?
    @State private var isNamingFolder = false
    @State private var renaming: ServerBrowserItem?
    @State private var typedName = ""
    @State private var deleting: [ServerBrowserItem]?

    private var folder: ServerFolderModel { model.current }

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .modifier(TitleMenu(ancestors: folder.isSelecting ? [] : model.ancestors, model: model, rootSymbol: rootSymbol))
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task(id: model.path) { await folder.load() }
            .refreshable { await folder.load(force: true) }
            // The bottom bar takes the tab bar's place while picking, as the
            // Library's selection does; before iOS 26 the tab bar is drawn over
            // the content and would hide the bar (seen on 18.6).
            .onChange(of: folder.isSelecting) { _, selecting in
                if model.mode == .browse { navigation.hidesTabBar = selecting }
            }
            .toolbar(folder.isSelecting ? .hidden : .automatic, for: .tabBar)
            .onDisappear {
                if folder.isSelecting { folder.isSelecting = false }
                if model.mode == .browse { navigation.hidesTabBar = false }
            }
            .sheet(item: Binding(get: { downloadModel.map(DownloadSheetItem.init) }, set: { if $0 == nil { downloadModel = nil } })) { item in
                ServerDownloadSheet(model: item.model, onShow: { destination in
                    if destination == .library {
                        navigation.selectedTab = .library
                        navigation.resetLibraryToRoot()
                    }
                })
            }
            .sheet(item: $viewing) { photo in
                ServerPhotoViewer(photo: photo, model: folder) { presentDownload([photo]) }
            }
            .alert("New Folder", isPresented: $isNamingFolder) {
                TextField("Name", text: $typedName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Create") {
                    let name = typedName
                    Task { await model.createFolder(named: name) }
                }
                .disabled(RemoteFolderListing.validatedName(typedName) == nil)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The folder is created on the server inside \(model.title).", comment: "Server browser: New Folder alert message")
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { item in
                TextField("Name", text: $typedName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Rename") {
                    let name = typedName
                    Task { await model.rename(item, to: name) }
                }
                .disabled(RemoteFolderListing.validatedName(typedName) == nil)
                Button("Cancel", role: .cancel) {}
            } message: { item in
                if case .photo(let photo) = item, photo.isPair {
                    Text("Both files of this RAW+JPEG pair are renamed. Extensions stay as they are.", comment: "Server browser: Rename alert for a RAW+JPEG pair")
                } else if case .folder = item {
                    EmptyView()
                } else {
                    Text("The extension stays as it is.", comment: "Server browser: Rename alert for a file")
                }
            }
            .alert(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { items in
                Button("Delete", role: .destructive) {
                    Task { await model.delete(items) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("It's deleted from the server, not moved to a trash, and can't be undone.", comment: "Server browser: delete confirmation")
            }
            .alert(
                "Couldn't Finish",
                isPresented: Binding(get: { model.editError != nil }, set: { if !$0 { model.editError = nil } }),
                presenting: model.editError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
    }

    private var title: String {
        if folder.isSelecting {
            return folder.selected.isEmpty
                ? String(localized: "Select Photos", comment: "Server browser title while selecting, nothing picked")
                : String(localized: "\(folder.selected.count) Selected", comment: "Server browser title: how many photos are picked")
        }
        return model.title
    }

    private var rootSymbol: String {
        model.server.transferProtocol == .sftp ? "house" : "externaldrive.connected.to.line.below"
    }

    private var deleteTitle: String {
        guard let items = deleting else { return "" }
        if items.count == 1, let item = items.first {
            if case .folder(let name) = item {
                return String(localized: "Delete the folder “\(name)” and everything in it?", comment: "Server browser: delete a folder")
            }
            let name: String = switch item {
            case .photo(let photo): photo.isPair ? item.baseName : photo.primary.name
            case .file(let entry): entry.name
            case .folder(let name): name
            }
            return String(localized: "Delete “\(name)” from \(model.server.name)?", comment: "Server browser: delete one photo or file")
        }
        return String(localized: "Delete \(items.count) photos from \(model.server.name)?", comment: "Server browser: delete the picked photos")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch folder.listing {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't Open Folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await folder.load(force: true) } }
            }
        case .loaded:
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if let progress = folder.dateProgress {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Reading dates… \(progress.done) of \(progress.total)", comment: "Server browser: reading capture dates for Date Taken sort")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        let items = model.items
                        if items.isEmpty {
                            Text(model.isAtSMBRoot ? "This computer doesn't share any folders with this account." : "No photos in this folder.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 40)
                                .padding(.horizontal, 16)
                        } else {
                            switch model.layout {
                            case .icons: grid(items, width: proxy.size.width)
                            case .list: list(items)
                            }
                            footer
                        }
                        // Before iOS 26 the floating tab bar sits over the scroll view.
                        if #unavailable(iOS 26.0) {
                            Color.clear.frame(height: 90)
                        }
                    }
                }
            }
        }
    }

    private func grid(_ items: [ServerBrowserItem], width: CGFloat) -> some View {
        let columns = GridDensity.columns(forDensity: storedColumns, width: width, isRegularWidth: sizeClass == .regular)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: PhotoGridLayout.spacing), count: columns),
            spacing: PhotoGridLayout.spacing
        ) {
            ForEach(items) { item in
                itemView(item) {
                    switch item {
                    case .folder(let name):
                        ServerGlyphTile(name: name, symbol: "folder.fill", isFolder: true)
                    case .file(let entry):
                        ServerGlyphTile(name: entry.name, symbol: "doc", isFolder: false)
                    case .photo(let photo):
                        ServerPhotoCell(
                            photo: photo,
                            image: folder.thumbnails[photo.id],
                            hasNoPreview: folder.withoutPreview.contains(photo.id),
                            isInLibrary: folder.inLibrary.contains(photo.id),
                            isSelecting: folder.isSelecting,
                            isSelected: folder.selected.contains(photo.id)
                        )
                    }
                }
            }
        }
    }

    private func list(_ items: [ServerBrowserItem]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                itemView(item) {
                    ServerListRow(
                        item: item,
                        image: item.photo.flatMap { folder.thumbnails[$0.id] },
                        modified: item.folderName.flatMap { folder.contents.folderModified[$0] },
                        isInLibrary: item.photo.map { folder.inLibrary.contains($0.id) } ?? false,
                        isSelecting: folder.isSelecting,
                        isSelected: item.photo.map { folder.selected.contains($0.id) } ?? false
                    )
                }
                Divider().padding(.leading, 72)
            }
        }
    }

    /// One item with what it does on a tap and a long press — shared by
    /// both layouts, so Icons and List never disagree.
    private func itemView(_ item: ServerBrowserItem, @ViewBuilder label: () -> some View) -> some View {
        label()
            .opacity(isDimmed(item) ? 0.45 : 1)
            .onAppear { if let photo = item.photo { folder.requestThumbnail(for: photo) } }
            .onDisappear { if let photo = item.photo { folder.cancelThumbnail(for: photo.id) } }
            .onTapGesture { tap(item) }
            .contextMenu { contextMenu(for: item) }
    }

    /// Files are never opened; in choose-folder mode photos are only
    /// context (FS-17.01 §5).
    private func isDimmed(_ item: ServerBrowserItem) -> Bool {
        switch item {
        case .folder: folder.isSelecting
        case .file: true
        case .photo: model.mode == .chooseFolder
        }
    }

    private func tap(_ item: ServerBrowserItem) {
        switch item {
        case .folder(let name):
            guard !folder.isSelecting else { return }
            model.open(folder: name)
        case .photo(let photo):
            guard model.canSelect else { return }
            if folder.isSelecting { folder.toggle(photo.id) } else { viewing = photo }
        case .file:
            break
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ServerBrowserItem) -> some View {
        if !folder.isSelecting {
            switch item {
            case .folder(let name):
                Button { model.open(folder: name) } label: { Label("Open", systemImage: "folder") }
            case .photo(let photo):
                if model.canSelect {
                    Button { presentDownload([photo]) } label: { Label("Import to Library", systemImage: "square.and.arrow.down") }
                }
            case .file:
                EmptyView()
            }
            if model.canEdit {
                Button {
                    typedName = item.baseName
                    renaming = item
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleting = [item]
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    /// "3 folders · 12 photos · 2 other files hidden", leaving out what is
    /// not there; counts agree with their nouns ("1 folder").
    private var footer: some View {
        let contents = folder.contents
        var parts: [Text] = []
        if !contents.folders.isEmpty {
            parts.append(Text("^[\(contents.folders.count) folder](inflect: true)", comment: "Server browser footer: folders in this folder"))
        }
        if !folder.photos.isEmpty || contents.folders.isEmpty {
            parts.append(Text("^[\(folder.photos.count) photo](inflect: true)", comment: "Server browser footer: photos shown"))
        }
        if contents.hiddenFileCount > 0 {
            parts.append(model.showsAllFiles
                ? Text("^[\(contents.hiddenFileCount) other file](inflect: true)", comment: "Server browser footer: non-photo files shown by Show All Files")
                : Text("^[\(contents.hiddenFileCount) other file](inflect: true) hidden", comment: "Server browser footer: files left out"))
        }
        let line = parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) { $0 + Text(verbatim: " · ") + $1 }
        return line
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 16)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if folder.isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                if folder.selected.count == folder.photos.count, !folder.photos.isEmpty {
                    Button("Deselect All") { folder.deselectAll() }
                } else {
                    Button("Select All") { folder.selectAll() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { folder.isSelecting = false }
                    .fontWeight(.semibold)
            }
        } else {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    if !model.goBack() { dismiss() }
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("Back")
                Button {
                    model.goForward()
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .accessibilityLabel("Forward")
                .disabled(!model.history.canGoForward)
            }
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
            }
        }
    }

    /// ⋯, in the order of Files' own (FS-17.01 §2c).
    private var moreMenu: some View {
        Menu {
            Section {
                if model.canSelect {
                    Button {
                        folder.isSelecting = true
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    .disabled(folder.photos.isEmpty)
                }
                Button {
                    typedName = ""
                    isNamingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .disabled(!model.canCreateFolder || model.isWorking)
            }
            Section {
                Picker("View", selection: Binding(get: { model.layout }, set: { model.setLayout($0) })) {
                    Label("Icons", systemImage: "square.grid.2x2").tag(ServerBrowserModel.Layout.icons)
                    Label("List", systemImage: "list.bullet").tag(ServerBrowserModel.Layout.list)
                }
                .pickerStyle(.inline)
            }
            Section {
                Menu {
                    ForEach(ServerPhotoSort.allCases) { sort in
                        Button {
                            model.chooseSort(sort)
                        } label: {
                            if model.sort == sort {
                                Label(sort.title, systemImage: model.ascending ? "chevron.up" : "chevron.down")
                            } else {
                                Text(sort.title)
                            }
                        }
                    }
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                    Text(model.sort.title)
                }
                Menu {
                    Toggle("Show All Files", isOn: Binding(get: { model.showsAllFiles }, set: { model.setShowsAllFiles($0) }))
                } label: {
                    Label("View Options", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    // MARK: Bottom bars

    @ViewBuilder
    private var bottomBar: some View {
        if folder.isSelecting {
            HStack(spacing: 12) {
                Button {
                    presentDownload(folder.selectedPhotos)
                } label: {
                    Label(
                        folder.selected.isEmpty
                            ? String(localized: "Import to Library", comment: "Server browser: copy the picked photos into the library")
                            : String(localized: "Import \(folder.selected.count) to Library", comment: "Server browser: copy the picked photos into the library, with their count"),
                        systemImage: "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) {
                    deleting = folder.selectedPhotos.map(ServerBrowserItem.photo)
                } label: {
                    Image(systemName: "trash")
                        .frame(minWidth: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Delete")
            }
            .controlSize(.large)
            .disabled(folder.selected.isEmpty || model.isWorking)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        } else if model.mode == .chooseFolder {
            VStack(spacing: 6) {
                if model.isAtSMBRoot {
                    Text("Open one of the shared folders first.", comment: "Server folder picker: nothing can be chosen at an SMB root")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    onChoose?(model.path)
                } label: {
                    Text(chooseTitle)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canChoose)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var chooseTitle: String {
        if model.path.isEmpty, model.server.transferProtocol == .sftp {
            return String(localized: "Choose Home", comment: "Server folder picker: pick the SFTP home folder")
        }
        return String(localized: "Choose “\(model.title)”", comment: "Server folder picker: pick the folder on screen")
    }

    private func presentDownload(_ photos: [ServerPhoto]) {
        guard !photos.isEmpty else { return }
        let server = model.server
        let library = dependencies.photoLibrary
        let folderModel = folder
        downloadModel = ServerDownloadModel(
            context: .init(server: server, folder: folderModel.folder, photos: photos, inLibrary: folderModel.inLibrary, known: folderModel.known),
            password: dependencies.fileServers.password(for: server.id) ?? "",
            isLimitedAccess: PhotoKitAssetCreator.isLimitedAccess,
            makeClient: RemoteFileClientFactory.make(for:password:),
            creator: PhotoKitAssetCreator(),
            downloads: dependencies.serverDownloads,
            screenHold: ScreenAwakeCoordinator.shared,
            listAlbums: {
                PhotoLibraryService.fetchUserAlbums().map { .init(id: $0.localIdentifier, title: $0.localizedTitle ?? "") }
            },
            createAlbumNamed: { name in try await library.createAlbum(named: name).localIdentifier },
            freeSpace: {
                let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                return values?.volumeAvailableCapacityForImportantUsage
            },
            onSaved: { ids in
                folderModel.markInLibrary(ids)
                folderModel.isSelecting = false
            }
        )
    }
}

/// The title's menu of folders above (FS-17.01 §2a) — only when there are
/// any: an empty menu still draws its chevron.
private struct TitleMenu: ViewModifier {
    let ancestors: [String]
    let model: ServerBrowserModel
    let rootSymbol: String

    func body(content: Content) -> some View {
        if ancestors.isEmpty {
            content
        } else {
            content.toolbarTitleMenu {
                ForEach(ancestors, id: \.self) { path in
                    Button {
                        model.go(to: path)
                    } label: {
                        Label(model.title(for: path), systemImage: path.isEmpty ? rootSymbol : "folder")
                    }
                }
            }
        }
    }
}

private extension ServerBrowserItem {
    var photo: ServerPhoto? {
        if case .photo(let photo) = self { photo } else { nil }
    }

    var folderName: String? {
        if case .folder(let name) = self { name } else { nil }
    }

    var isPhoto: Bool { photo != nil }
}

/// A folder or a non-photo file in the Icons grid: the same square as a
/// photo tile without a preview, glyph over name (FS-17.01 §2b).
struct ServerGlyphTile: View {
    let name: String
    let symbol: String
    let isFolder: Bool

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 34))
                        .foregroundStyle(isFolder ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isFolder
                ? String(localized: "\(name), Folder", comment: "Server browser: a folder tile")
                : name)
            .accessibilityAddTraits(.isButton)
    }
}

/// One item in the List view (FS-17.01 §2b): 44pt square, name, a second
/// line, and In Library or a chevron.
struct ServerListRow: View {
    let item: ServerBrowserItem
    let image: CGImage?
    let modified: Date?
    let isInLibrary: Bool
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .opacity(item.isPhoto ? 1 : 0)
            }
            thumbnail
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            switch item {
            case .folder:
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            case .photo:
                if isInLibrary {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("In Library")
                }
            case .file:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Color(.secondarySystemBackground)
            switch item {
            case .folder:
                Image(systemName: "folder.fill").foregroundStyle(.tint)
            case .file:
                Image(systemName: "doc").foregroundStyle(.secondary)
            case .photo:
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var name: String {
        switch item {
        case .folder(let name): name
        case .photo(let photo): photo.isPair ? item.baseName : photo.primary.name
        case .file(let entry): entry.name
        }
    }

    private var detail: String? {
        switch item {
        case .folder:
            return modified?.formatted(date: .abbreviated, time: .shortened)
        case .photo(let photo):
            let size = ByteCountFormatter.string(fromByteCount: photo.totalBytes, countStyle: .file)
            let parts = [photo.modified?.formatted(date: .abbreviated, time: .shortened), size, photo.isPair ? photo.badge : nil]
            return parts.compactMap { $0 }.joined(separator: " · ")
        case .file(let entry):
            let size = ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
            return [entry.modified?.formatted(date: .abbreviated, time: .shortened), size].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// `sheet(item:)` needs Identifiable; the model is a class.
private struct DownloadSheetItem: Identifiable {
    let model: ServerDownloadModel
    var id: ObjectIdentifier { ObjectIdentifier(model) }
}

/// One square tile (FS-17.01 §2): thumbnail or format icon, format badge
/// top-left, In Library bottom-left, selection bottom-right — where the
/// Library tile keeps them.
struct ServerPhotoCell: View {
    let photo: ServerPhoto
    let image: CGImage?
    let hasNoPreview: Bool
    let isInLibrary: Bool
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else if hasNoPreview {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.title2)
                        Text(photo.primary.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 4)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(photo.badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }
            .overlay(alignment: .bottomLeading) {
                if isInLibrary {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : .clear)
                        .shadow(radius: 1)
                        .padding(5)
                }
            }
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityText: String {
        var parts = [photo.primary.name, photo.badge]
        if isInLibrary { parts.append(String(localized: "In Library", comment: "Server browser tile: the photo is already in the library")) }
        return parts.joined(separator: ", ")
    }
}

/// Tapping a tile outside Select (FS-17.01 §4): a larger preview, what the
/// file is, and Download for just this photo.
struct ServerPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photo: ServerPhoto
    let model: ServerFolderModel
    let onDownload: () -> Void
    @State private var image: CGImage?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    Color(.secondarySystemBackground)
                    if let image = image ?? model.thumbnails[photo.id] {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                    } else if !isLoading {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    if isLoading {
                        ProgressView()
                    }
                }
                .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(photo.files, id: \.name) { file in
                        LabeledContent(file.name, value: ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    }
                    if let modified = photo.modified {
                        LabeledContent("Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                Button {
                    dismiss()
                    onDownload()
                } label: {
                    Label("Import to Library", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle(photo.primary.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            let folder = model.folder
            let photo = photo
            let result = try? await model.session.perform { client in
                var reader = RemoteThumbnailer(client: client)
                reader.maxPixelSize = 2048
                reader.sharpEnough = 1200
                return try await reader.thumbnail(for: photo, in: folder)
            }
            image = result?.thumbnail?.image
            isLoading = false
        }
    }
}
