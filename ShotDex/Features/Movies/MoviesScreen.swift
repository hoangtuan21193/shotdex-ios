import SwiftUI

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
            if model?.isEmpty == false {
                ToolbarItem(placement: .topBarTrailing) { viewMenu }
                // Two round buttons as on `PH_Movies`, not one shared capsule.
                if #available(iOS 26.0, *) { ToolbarSpacer(.fixed, placement: .topBarTrailing) }
            }
            ToolbarItem(placement: .topBarTrailing) { addMenu }
        }
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
                            MovieGridCell(movie: movie).contextMenu { movieMenu(movie, model: model) }
                        }
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(shown) { movie in
                            MovieListRow(movie: movie, keepsAppOpen: model.sources[movie.sourceId ?? ""].map { !downloads.downloadsInBackground($0, movie) } ?? false)
                                .padding(.horizontal, 12)
                                .frame(height: 64)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                .contextMenu { movieMenu(movie, model: model) }
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

    /// ⋯: Grid/List and Sort (FS-23.01 §4).
    private var viewMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: "View, Sort and Select", comment: "Movies: the ⋯ button"))
    }

    /// FS-23.01 §5. Play, Download, Audio & Subtitles join with their tasks.
    @ViewBuilder
    private func movieMenu(_ movie: Movie, model: MoviesModel) -> some View {
        if movie.downloadError != nil, movie.sourceId != nil {
            Button { dependencies.movieDownloads.retry(movie.id) } label: {
                Label(String(localized: "Retry Download", comment: "Movie menu: try a stopped download again"), systemImage: "arrow.clockwise")
            }
        } else if movie.state == .stream, movie.sourceId != nil {
            Button { dependencies.movieDownloads.download(movie.id) } label: {
                Label("\(MoviesCountText.downloadTo()) · \(movie.byteCount.formatted(.byteCount(style: .file)))", systemImage: "arrow.down.circle")
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
        Button {
            typedTitle = movie.displayTitle
            renaming = movie
        } label: {
            Label(String(localized: "Rename", comment: "Movie menu"), systemImage: "pencil")
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
            Button {} label: {
                Label(String(localized: "Add Movie Files…", comment: "Movies + menu: copy movie files onto this device"), systemImage: "doc.badge.plus")
            }
            .disabled(true)
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
