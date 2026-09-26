import SwiftUI

/// One folder on a server, drawn like the Library (FS-17.01 §2): subfolders
/// on top, then an edge-to-edge grid of square photo tiles with the same
/// columns and 2 pt gaps, Select to pick, Download to bring them into Photos.
/// Tier B.
struct ServerBrowserScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKeys.gridColumns) private var storedColumns = 3
    let model: ServerFolderModel
    @State private var downloadModel: ServerDownloadModel?
    @State private var viewing: ServerPhoto?

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if model.isSelecting { downloadBar }
            }
            .task { await model.load() }
            .refreshable { await model.load(force: true) }
            // The Download bar takes the tab bar's place while picking, as the
            // Library's selection does; before iOS 26 the tab bar is drawn over
            // the content and would hide the bar (seen on 18.6).
            .onChange(of: model.isSelecting) { _, selecting in navigation.hidesTabBar = selecting }
            .toolbar(model.isSelecting ? .hidden : .automatic, for: .tabBar)
            .onDisappear {
                if model.isSelecting { model.isSelecting = false }
                navigation.hidesTabBar = false
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
                ServerPhotoViewer(photo: photo, model: model) { presentDownload([photo]) }
            }
    }

    private var title: String {
        if model.isSelecting {
            return model.selected.isEmpty
                ? String(localized: "Select Photos", comment: "Server browser title while selecting, nothing picked")
                : String(localized: "\(model.selected.count) Selected", comment: "Server browser title: how many photos are picked")
        }
        if model.folder.isEmpty {
            let server = model.session.server
            return server.transferProtocol == .smb && !server.share.isEmpty
                ? server.share
                : String(localized: "Home", comment: "Server browser: the SFTP login's home folder")
        }
        return ServerUploadPath.lastComponent(of: model.folder)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.listing {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't Open Folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await model.load(force: true) } }
            }
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let columns = GridDensity.columns(forDensity: storedColumns, width: proxy.size.width, isRegularWidth: sizeClass == .regular)
            ScrollView {
                VStack(spacing: 0) {
                    if !model.contents.folders.isEmpty {
                        folderRows
                    }
                    if let progress = model.dateProgress {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reading dates… \(progress.done) of \(progress.total)", comment: "Server browser: reading capture dates for Date Taken sort")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    if model.photos.isEmpty {
                        Text("No photos in this folder.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: PhotoGridLayout.spacing), count: columns),
                            spacing: PhotoGridLayout.spacing
                        ) {
                            ForEach(model.photos) { photo in
                                ServerPhotoCell(
                                    photo: photo,
                                    image: model.thumbnails[photo.id],
                                    hasNoPreview: model.withoutPreview.contains(photo.id),
                                    isInLibrary: model.inLibrary.contains(photo.id),
                                    isSelecting: model.isSelecting,
                                    isSelected: model.selected.contains(photo.id)
                                )
                                .onAppear { model.requestThumbnail(for: photo) }
                                .onDisappear { model.cancelThumbnail(for: photo.id) }
                                .onTapGesture {
                                    if model.isSelecting { model.toggle(photo.id) } else { viewing = photo }
                                }
                            }
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

    private var folderRows: some View {
        VStack(spacing: 0) {
            ForEach(model.contents.folders, id: \.self) { name in
                NavigationLink(value: ServerFolderRoute(connectionId: model.session.server.id, path: ServerUploadPath.join(model.folder, name))) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .foregroundStyle(.tint)
                        Text(name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 48)
            }
        }
        .padding(.bottom, 8)
    }

    private var footer: some View {
        Group {
            if model.contents.hiddenFileCount > 0 {
                Text("\(model.photos.count) photos · \(model.contents.hiddenFileCount) other files hidden", comment: "Server browser footer: photos shown and files left out")
            } else {
                Text("\(model.photos.count) photos", comment: "Server browser footer: photos shown")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 16)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if model.isSelecting {
                Menu {
                    Button("Select All") { model.selectAll() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            } else {
                sortMenu
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(model.isSelecting ? "Cancel" : "Select") {
                model.isSelecting.toggle()
            }
            .disabled(model.photos.isEmpty && !model.isSelecting)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: Binding(get: { model.sort }, set: { model.setSort($0) })) {
                ForEach(ServerPhotoSort.allCases) { Text($0.title).tag($0) }
            }
            Picker("Order", selection: Binding(get: { model.ascending }, set: { model.setAscending($0) })) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
    }

    private var downloadBar: some View {
        Button {
            presentDownload(model.selectedPhotos)
        } label: {
            Label(
                model.selected.isEmpty
                    ? String(localized: "Download", comment: "Server browser: download the picked photos")
                    : String(localized: "Download \(model.selected.count)", comment: "Server browser: download the picked photos, with their count"),
                systemImage: "arrow.down.circle"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.selected.isEmpty)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func presentDownload(_ photos: [ServerPhoto]) {
        guard !photos.isEmpty else { return }
        let server = model.session.server
        let library = dependencies.photoLibrary
        let folderModel = model
        downloadModel = ServerDownloadModel(
            context: .init(server: server, folder: model.folder, photos: photos, inLibrary: model.inLibrary, known: model.known),
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
                    Label("Download", systemImage: "arrow.down.circle")
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
