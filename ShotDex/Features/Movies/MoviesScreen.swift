import SwiftUI
import UniformTypeIdentifiers

/// The Movies library (FS-23.01 §4, board `PH_Movies`): one library over
/// every source — NAS folders, Plex, files copied in.
struct MoviesScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @AppStorage("movies.layout") private var layout = MoviesLayout.grid
    @AppStorage("movies.sort") private var sort = MovieLibraryQuery.Sort.recentlyAdded

    @State private var model: MoviesModel?
    @State private var isAddingSource = false
    @State private var renaming: Movie?
    @State private var typedTitle = ""
    @State private var removingDownloads: [Movie] = []
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    /// The source a dimmed movie needs (FS-23.01 §3).
    @State private var awayFrom: String?
    @State private var isImporting = false
    @State private var removingCopied: Movie?
    @State private var importFailure: String?
    @State private var playing: PlayingMovie?
    /// The movie page a tap opened (FS-23.08 §1).
    @State private var detail: MovieDetailDestination?
    /// Subtitle files shared in, waiting for their movie (FS-23.03 §5).
    @State private var sharedSubtitles: [URL] = []
    @State private var subtitleFailure: String?
    /// A Plex movie with several versions: which one to download (AC-56).
    @State private var choosingVersion: (movie: Movie, versions: [PlexClient.Version])?
    /// The Duo's cover screen (FS-23.02 §4): play only — no +, Delete or
    /// Rename. Told apart from a phone by the 84 pt rail in its trailing
    /// safe area, as the editor does.
    @State private var isDuoCover = false

    var body: some View {
        Group {
            if let model, model.isLoaded {
                if model.isEmpty {
                    emptyState
                } else {
                    library(model)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(String(localized: "Movies", comment: "Movies screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .moviesSubtitle(model.flatMap { MoviesCountText.subtitle($0.counts) })
        .toolbar {
            if model?.isEmpty == false, !isDuoCover {
                ToolbarItem(placement: .topBarTrailing) { viewMenu }
                // Two round buttons as on `PH_Movies`, not one shared capsule.
                if #available(iOS 26.0, *) { ToolbarSpacer(.fixed, placement: .topBarTrailing) }
            }
            if !isDuoCover {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            EditorLayoutMetrics.usesDuoCoverColumn(isWide: false, windowTrailingInset: proxy.safeAreaInsets.trailing)
        } action: { isDuoCover = $0 }
        .task {
            let model = model ?? MoviesModel(store: dependencies.movies)
            model.query.sort = sort
            self.model = model
            model.load()
            // FS-23.01 §2: sources are listed again each time Movies opens.
            await dependencies.movieSync.refreshAll()
            model.load()
        }
        .onChange(of: sort) { _, sort in model?.query.sort = sort }
        .onChange(of: dependencies.movieDownloads.revision) { model?.load() }
        .sheet(isPresented: $isAddingSource, onDismiss: { model?.load() }) {
            AddMovieSourceSheet()
        }
        .navigationDestination(item: $detail) { destination in
            MovieDetailScreen(movieId: destination.movieId)
        }
        .onChange(of: detail) { _, shown in if shown == nil { model?.load() } }
        .fullScreenCover(item: $playing, onDismiss: { model?.load() }) { playing in
            MoviePlayerScreen(model: playing.model, videoView: playing.view)
        }
        .confirmationDialog(
            String(localized: "Download Which Version?", comment: "Plex movie with several versions: pick one to download"),
            isPresented: Binding(get: { choosingVersion != nil }, set: {
                guard !$0, let choice = choosingVersion else { return }
                choosingVersion = nil
                dependencies.movieDownloads.cancelPreparing(choice.movie.id)
            }),
            titleVisibility: .visible,
            presenting: choosingVersion
        ) { choice in
            ForEach(Array(choice.versions.enumerated()), id: \.offset) { _, version in
                Button(version.label) {
                    try? PlexDownloadPreparer(store: dependencies.movies).choose(version, for: choice.movie)
                    dependencies.movieDownloads.download(choice.movie.id)
                }
            }
            Button(String(localized: "Cancel", comment: "Plex versions: download nothing"), role: .cancel) {}
        }
        .onChange(of: IntentRouter.shared.pendingMovieSubtitles, initial: true) { _, urls in
            guard !urls.isEmpty else { return }
            sharedSubtitles = urls
            IntentRouter.shared.pendingMovieSubtitles = []
        }
        .sheet(isPresented: Binding(get: { !sharedSubtitles.isEmpty }, set: { if !$0 { finishSharedSubtitles() } })) {
            AddSubtitleSheet(urls: sharedSubtitles, movies: (try? dependencies.movies.movies()) ?? []) { movie in
                do {
                    _ = try SubtitleImporter(store: dependencies.movies, files: dependencies.movieDownloads.files)
                        .importFiles(sharedSubtitles, into: movie.id, origin: .shared)
                } catch {
                    subtitleFailure = error.localizedDescription
                }
            }
        }
        .alert(
            String(localized: "Couldn't Add the Subtitle", comment: "A shared subtitle could not be added"),
            isPresented: Binding(get: { subtitleFailure != nil }, set: { if !$0 { subtitleFailure = nil } }),
            presenting: subtitleFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            do {
                _ = try MovieImporter(store: dependencies.movies, files: dependencies.movieDownloads.files).importFiles(urls)
            } catch {
                importFailure = error.localizedDescription
            }
            model?.load()
        }
        .alert(
            String(localized: "Couldn't Add the Movie", comment: "Add Movie Files failed"),
            isPresented: Binding(get: { importFailure != nil }, set: { if !$0 { importFailure = nil } }),
            presenting: importFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .alert(
            String(localized: "Remove from Movies?", comment: "Remove a copied-in movie: alert title"),
            isPresented: Binding(get: { removingCopied != nil }, set: { if !$0 { removingCopied = nil } }),
            presenting: removingCopied
        ) { movie in
            Button(String(localized: "Remove", comment: "Remove from Movies: confirm"), role: .destructive) {
                dependencies.movieDownloads.files.removeAll(for: movie.id)
                try? dependencies.movies.delete(id: movie.id)
                model?.load()
            }
            Button(String(localized: "Cancel", comment: "Remove from Movies: keep it"), role: .cancel) {}
        } message: { movie in
            Text(String(localized: "\(movie.displayTitle) will be deleted from this device. This frees \(movie.byteCount.formatted(.byteCount(style: .file))).", comment: "Remove from Movies alert message"))
        }
        .alert(
            String(localized: "Not available offline.", comment: "Tapped a movie whose source is out of reach"),
            isPresented: Binding(get: { awayFrom != nil }, set: { if !$0 { awayFrom = nil } }),
            presenting: awayFrom
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { name in
            Text(String(localized: "Connect to \(name) to play.", comment: "Tapped a movie whose source is out of reach: what to do"))
        }
        .alert(
            String(localized: "Remove Download?", comment: "Remove Download alert title"),
            isPresented: Binding(get: { !removingDownloads.isEmpty }, set: { if !$0 { removingDownloads = [] } })
        ) {
            Button(String(localized: "Remove", comment: "Remove Download alert: confirm"), role: .destructive) {
                for movie in removingDownloads { dependencies.movieDownloads.removeDownload(movie) }
                removingDownloads = []
                isSelecting = false
                selection = []
            }
            Button(String(localized: "Cancel", comment: "Remove Download alert: keep the download"), role: .cancel) {}
        } message: {
            Text(removeDownloadMessage)
        }
        .alert(String(localized: "Rename", comment: "Movie menu: rename alert title"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(String(localized: "Name", comment: "Rename movie: field"), text: $typedTitle)
            Button(String(localized: "Cancel", comment: "Rename movie: cancel"), role: .cancel) {}
            Button(String(localized: "Save", comment: "Rename movie: save")) {
                if let movie = renaming { model?.rename(movie, to: typedTitle) }
            }
        }
    }

    // MARK: Library

    @ViewBuilder
    private func library(_ model: MoviesModel) -> some View {
        @Bindable var model = model
        let downloads = dependencies.movieDownloads
        let shown = model.shown.map { movie in
            var live = movie
            live.downloadedBytes = downloads.bytes(for: movie)
            return live
        }
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if #unavailable(iOS 26.0), let subtitle = MoviesCountText.subtitle(model.counts) {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                filterChips(model)
                if shown.isEmpty {
                    ContentUnavailableView.search(text: model.query.text)
                        .padding(.top, 40)
                } else if layout == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105, maximum: 160), spacing: 12, alignment: .top)], spacing: 16) {
                        ForEach(shown) { movie in
                            MovieGridCell(movie: movie, isAway: model.isAway(movie))
                                .overlay(alignment: .topLeading) { selectionMark(movie) }
                                .contentShape(Rectangle())
                                .onTapGesture { tapped(movie) }
                                .accessibilityAddTraits(isSelecting && selection.contains(movie.id) ? .isSelected : [])
                                .contextMenu { if !isSelecting { movieMenu(movie, model: model) } }
                        }
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(shown) { movie in
                            MovieListRow(movie: movie, keepsAppOpen: model.sources[movie.sourceId ?? ""].map { !downloads.downloadsInBackground($0, movie) } ?? false, isAway: model.isAway(movie))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 64)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                .overlay(alignment: .trailing) { selectionMark(movie).padding(.trailing, 12) }
                                .contentShape(Rectangle())
                                .onTapGesture { tapped(movie) }
                                .accessibilityAddTraits(isSelecting && selection.contains(movie.id) ? .isSelected : [])
                                .contextMenu { if !isSelecting { movieMenu(movie, model: model) } }
                        }
                    }
                }
                if let total = storageLine(model) {
                    Text(total)
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .searchable(text: $model.query.text, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "Search Movies", comment: "Movies search field"))
    }

    /// All · On This iPhone · Unwatched (FS-23.01 §4).
    private func filterChips(_ model: MoviesModel) -> some View {
        HStack(spacing: 8) {
            ForEach(MovieLibraryQuery.Filter.allCases, id: \.self) { filter in
                let isOn = model.query.filter == filter
                Button { model.query.filter = filter } label: {
                    Text(Self.title(filter))
                        .font(.subheadline.weight(isOn ? .semibold : .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .foregroundStyle(isOn ? Color(.systemBackground) : Color(.label))
                        .background(isOn ? Color(.label) : Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    static func title(_ filter: MovieLibraryQuery.Filter) -> String {
        switch filter {
        case .all: String(localized: "All", comment: "Movies filter: every movie")
        case .onDevice: MoviesCountText.onThisDevice()
        case .unwatched: String(localized: "Unwatched", comment: "Movies filter: not watched to the end")
        }
    }

    /// `21.4 GB · 48 GB free` at the end of the list.
    private func storageLine(_ model: MoviesModel) -> String? {
        let used = model.movies.filter(\.isOnDevice).reduce(Int64(0)) { $0 + $1.byteCount }
        guard used > 0 else { return nil }
        let free = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return String(localized: "\(used.formatted(.byteCount(style: .file))) · \(free.formatted(.byteCount(style: .file))) free", comment: "Movies: space the downloads take, and what is left")
    }

    // MARK: Menus

    /// "The movie stays on NAS Home. This frees 6.1 GB."
    private var removeDownloadMessage: String { Self.removeDownloadMessage(removingDownloads) }

    static func removeDownloadMessage(_ movies: [Movie]) -> String {
        let freed = movies.reduce(Int64(0)) { $0 + max($1.byteCount, $1.downloadedBytes) }.formatted(.byteCount(style: .file))
        let sources = Set(movies.compactMap(\.sourceName))
        if sources.count == 1, let name = sources.first {
            return String(localized: "The movie stays on \(name). This frees \(freed).", comment: "Remove Download alert message")
        }
        return String(localized: "The movies stay on their sources. This frees \(freed).", comment: "Remove Download alert message, several sources")
    }

    /// Movie files (and subtitles to go with them) for Add Movie Files….
    /// Download to iPhone. A Plex movie first learns its versions; with more
    /// than one the user picks (FS-23.07 §3, AC-56).
    private func startDownload(_ movie: Movie) {
        guard movie.plexRatingKey != nil else {
            dependencies.movieDownloads.download(movie.id)
            return
        }
        let preparer = PlexDownloadPreparer(store: dependencies.movies)
        dependencies.movieDownloads.prepare(movie.id)
        Task {
            let versions = (try? await preparer.versions(of: movie)) ?? []
            if versions.count > 1 {
                choosingVersion = (movie, versions)
            } else {
                if let only = versions.first { try? preparer.choose(only, for: movie) }
                dependencies.movieDownloads.download(movie.id)
            }
        }
    }

    /// The Inbox copies the system made of shared files go once handled.
    private func finishSharedSubtitles() {
        for url in sharedSubtitles where url.path.contains("/Inbox/") {
            try? FileManager.default.removeItem(at: url)
        }
        sharedSubtitles = []
    }

    static let importTypes: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2TransportStream]
        + ["mkv", "webm", "flv", "wmv", "m2ts", "ts", "srt", "ass", "ssa", "vtt"].compactMap { UTType(filenameExtension: $0) }

    // MARK: Select

    @ViewBuilder
    private func selectionMark(_ movie: Movie) -> some View {
        if isSelecting {
            Image(systemName: selection.contains(movie.id) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, selection.contains(movie.id) ? AppAccent.color : Color.black.opacity(0.35))
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    private func tapped(_ movie: Movie) {
        if isSelecting {
            if selection.contains(movie.id) { selection.remove(movie.id) } else { selection.insert(movie.id) }
            return
        }
        // The page, not the player (FS-23.08 §1) — a movie out of reach
        // too: its page still shows what it is.
        detail = MovieDetailDestination(movieId: movie.id)
    }

    /// Play (FS-23.02 §1): from the file when the movie is on the device,
    /// else streamed from its source over the saved connection (AC-3).
    private func play(_ movie: Movie, fromStart: Bool = false) {
        Task {
            do {
                playing = try await MoviePlayback(dependencies: dependencies).open(movie, fromStart: fromStart)
            } catch {
                awayFrom = movie.sourceName ?? ""
            }
        }
    }

    private func selected(_ model: MoviesModel) -> [Movie] {
        model.movies.filter { selection.contains($0.id) }
    }

    /// ⋯ while selecting: what can be done to the chosen movies (FS-23.01 §5).
    @ViewBuilder
    private func selectionActions(_ model: MoviesModel) -> some View {
        let chosen = selected(model)
        let downloadable = chosen.filter { $0.state == .stream && $0.sourceId != nil }
        let downloaded = chosen.filter { ($0.isOnDevice || $0.state == .downloading || $0.state == .queued) && $0.sourceId != nil }
        Button {
            for movie in downloadable { dependencies.movieDownloads.download(movie.id) }
            isSelecting = false
            selection = []
        } label: {
            Label(MoviesCountText.downloadTo(), systemImage: "arrow.down.circle")
        }
        .disabled(downloadable.isEmpty)
        Button(role: .destructive) {
            removingDownloads = downloaded
        } label: {
            Label(String(localized: "Remove Download", comment: "Movie menu: delete the copy on this device"), systemImage: "arrow.uturn.backward.circle")
        }
        .disabled(downloaded.isEmpty)
        Button {
            for movie in chosen { model.setWatched(true, movie) }
            isSelecting = false
            selection = []
        } label: {
            Label(String(localized: "Mark as Watched", comment: "Movie menu"), systemImage: "eye")
        }
        .disabled(chosen.isEmpty)
    }

    /// ⋯: Grid/List and Sort (FS-23.01 §4).
    private var viewMenu: some View {
        Menu {
            if isSelecting, let model {
                selectionActions(model)
                Divider()
                Button(String(localized: "Done", comment: "Movies: leave Select")) {
                    isSelecting = false
                    selection = []
                }
            } else {
                viewMenuItems
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: "View, Sort and Select", comment: "Movies: the ⋯ button"))
    }

    @ViewBuilder
    private var viewMenuItems: some View {
        Group {
            Picker(selection: $layout) {
                Label(String(localized: "Grid", comment: "Movies view: posters"), systemImage: "square.grid.3x2").tag(MoviesLayout.grid)
                Label(String(localized: "List", comment: "Movies view: rows"), systemImage: "list.bullet").tag(MoviesLayout.list)
            } label: { EmptyView() }
            .pickerStyle(.inline)
            Picker(selection: $sort) {
                Text(String(localized: "Recently Added", comment: "Movies sort")).tag(MovieLibraryQuery.Sort.recentlyAdded)
                Text(String(localized: "Title", comment: "Movies sort")).tag(MovieLibraryQuery.Sort.title)
                Text(String(localized: "Year", comment: "Movies sort")).tag(MovieLibraryQuery.Sort.year)
                Text(String(localized: "Recently Watched", comment: "Movies sort")).tag(MovieLibraryQuery.Sort.recentlyWatched)
            } label: {
                Label(String(localized: "Sort", comment: "Movies ⋯ menu: sort submenu"), systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)
            Button {
                isSelecting = true
            } label: {
                Label(String(localized: "Select", comment: "Movies ⋯ menu: choose several movies"), systemImage: "checkmark.circle")
            }
        }
    }

    /// FS-23.01 §5. Play, Download, Audio & Subtitles join with their tasks.
    @ViewBuilder
    private func movieMenu(_ movie: Movie, model: MoviesModel) -> some View {
        // D4: the quick menu keeps everything, with Play first.
        Button {
            if model.isAway(movie) { awayFrom = movie.sourceName ?? "" } else { play(movie) }
        } label: {
            Label(String(localized: "Play", comment: "Movie menu: play the movie"), systemImage: "play.fill")
        }
        // What the movie is, from its source — still there offline (AC-49).
        if movie.genres != nil || movie.summary != nil {
            Section {
                if let genres = movie.genres { Text(genres) }
                if let summary = movie.summary, !summary.isEmpty { Text(summary) }
            }
        }
        if movie.downloadError != nil, movie.sourceId != nil {
            Button { dependencies.movieDownloads.retry(movie.id) } label: {
                Label(String(localized: "Retry Download", comment: "Movie menu: try a stopped download again"), systemImage: "arrow.clockwise")
            }
        } else if movie.state == .stream, movie.sourceId != nil {
            Button { startDownload(movie) } label: {
                Label("\(MoviesCountText.downloadTo()) · \(movie.byteCount.formatted(.byteCount(style: .file)))", systemImage: "arrow.down.circle")
            }
        }
        if !isDuoCover, movie.sourceId != nil, movie.isOnDevice || movie.state == .downloading || movie.state == .queued {
            Button(role: .destructive) { removingDownloads = [movie] } label: {
                Label(String(localized: "Remove Download", comment: "Movie menu: delete the copy on this device"), systemImage: "arrow.uturn.backward.circle")
            }
        }
        if !isDuoCover, movie.sourceId == nil, movie.isOnDevice || movie.state == .missing {
            Button(role: .destructive) { removingCopied = movie } label: {
                Label(String(localized: "Remove from Movies", comment: "Movie menu: delete a copied-in movie"), systemImage: "trash")
            }
        }
        if movie.isWatched {
            Button { model.setWatched(false, movie) } label: {
                Label(String(localized: "Mark as Unwatched", comment: "Movie menu"), systemImage: "eye.slash")
            }
        } else {
            Button { model.setWatched(true, movie) } label: {
                Label(String(localized: "Mark as Watched", comment: "Movie menu"), systemImage: "eye")
            }
        }
        if !isDuoCover {
            Button {
                typedTitle = movie.displayTitle
                renaming = movie
            } label: {
                Label(String(localized: "Rename", comment: "Movie menu"), systemImage: "pencil")
            }
        }
    }

    /// FS-23.01 §5: the two ways a movie gets in, and nothing else.
    private var addMenu: some View {
        Menu {
            Button {
                isAddingSource = true
            } label: {
                Label(String(localized: "Add a Source…", comment: "Movies + menu: add a NAS folder or a Plex server"), systemImage: "externaldrive.connected.to.line.below")
            }
            Button { isImporting = true } label: {
                Label(String(localized: "Add Movie Files…", comment: "Movies + menu: copy movie files onto this device"), systemImage: "doc.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: "Add a Source or Movie Files", comment: "Movies: the + button"))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "No Movies", comment: "Movies empty state title"), systemImage: "play.rectangle")
        } description: {
            Text(MoviesCountText.emptyDescription())
        } actions: {
            Button(String(localized: "Add a Source", comment: "Movies empty state button")) {
                isAddingSource = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private extension View {
    /// The `128 movies · 3 on this iPhone` line. A navigation bar has a
    /// subtitle only from iOS 26; earlier the screen draws it at the top.
    @ViewBuilder
    func moviesSubtitle(_ subtitle: String?) -> some View {
        if #available(iOS 26.0, *), let subtitle {
            navigationSubtitle(Text(subtitle))
        } else {
            self
        }
    }
}
