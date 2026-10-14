import SwiftUI

/// The movie page (FS-23.08, boards `PH_MovieDetail`, `IP_MovieDetail`,
/// `DI_MovieDetail`, `DC_MovieDetail`): a tap on a movie lands here, not in
/// the player — backdrop and poster, Resume / From Beginning / Download,
/// and Audio · Subtitles · Version on the player's own panel.
struct MovieDetailScreen: View {
    let movieId: String
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: MovieDetailModel?
    @State private var playing: PlayingMovie?
    @State private var awayFrom: String?
    @State private var isRemovingDownload = false
    @State private var isRemovingCopy = false
    @State private var isRenaming = false
    @State private var typedTitle = ""
    @State private var showsWholeSummary = false
    @State private var choosingVersion = false
    @State private var backdrop: CGImage?
    /// The Duo's cover (§5): a short page — no Download, Remove, Rename, ⋯.
    @State private var isDuoCover = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let model {
                page(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let model, !isDuoCover {
                ToolbarItem(placement: .topBarTrailing) { moreMenu(model) }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            EditorLayoutMetrics.usesDuoCoverColumn(isWide: false, windowTrailingInset: proxy.safeAreaInsets.trailing)
        } action: { isDuoCover = $0 }
        .task {
            guard model == nil, let movie = try? dependencies.movies.movie(id: movieId) else { return }
            let model = MovieDetailModel(movie: movie, playback: MoviePlayback(dependencies: dependencies))
            self.model = model
            await model.load()
        }
        .onDisappear { model?.unload() }
        .onChange(of: dependencies.movieDownloads.revision) { model?.reload() }
        .fullScreenCover(item: $playing, onDismiss: { model?.reload() }) { playing in
            MoviePlayerScreen(model: playing.model, videoView: playing.view)
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
        .alert(String(localized: "Remove Download?", comment: "Remove Download alert title"), isPresented: $isRemovingDownload) {
            Button(String(localized: "Remove", comment: "Remove Download alert: confirm"), role: .destructive) {
                if let movie = model?.movie { dependencies.movieDownloads.removeDownload(movie) }
                model?.reload()
            }
            Button(String(localized: "Cancel", comment: "Remove Download alert: keep the download"), role: .cancel) {}
        } message: {
            Text(MoviesScreen.removeDownloadMessage(model.map { [$0.movie] } ?? []))
        }
        .alert(String(localized: "Remove from Movies?", comment: "Remove a copied-in movie: alert title"), isPresented: $isRemovingCopy) {
            Button(String(localized: "Remove", comment: "Remove from Movies: confirm"), role: .destructive) {
                guard let movie = model?.movie else { return }
                dependencies.movieDownloads.files.removeAll(for: movie.id)
                try? dependencies.movies.delete(id: movie.id)
                dismiss()
            }
            Button(String(localized: "Cancel", comment: "Remove from Movies: keep it"), role: .cancel) {}
        } message: {
            if let movie = model?.movie {
                Text(String(localized: "\(movie.displayTitle) will be deleted from this device. This frees \(movie.byteCount.formatted(.byteCount(style: .file))).", comment: "Remove from Movies alert message"))
            }
        }
        .alert(String(localized: "Rename", comment: "Movie menu: rename alert title"), isPresented: $isRenaming) {
            TextField(String(localized: "Name", comment: "Rename movie: field"), text: $typedTitle)
            Button(String(localized: "Cancel", comment: "Rename movie: cancel"), role: .cancel) {}
            Button(String(localized: "Save", comment: "Rename movie: save")) {
                guard let movie = model?.movie else { return }
                try? dependencies.movies.rename(id: movie.id, to: typedTitle)
                model?.reload()
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    // MARK: Page

    private var isWide: Bool { sizeClass == .regular && !isDuoCover }

    @ViewBuilder
    private func page(_ model: MovieDetailModel) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(model, width: proxy.size.width)
                    if isWide {
                        HStack(alignment: .top, spacing: 32) {
                            actions(model).frame(maxWidth: 488)
                            VStack(alignment: .leading, spacing: 24) {
                                summary(model)
                                trackCard(model)
                            }
                            .frame(maxWidth: 480)
                        }
                        .padding(.horizontal, 32)
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            actions(model)
                            if !isDuoCover { summary(model) }
                            trackCard(model)
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                    }
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)
        }
        .sheet(isPresented: Binding(get: { model.tracks?.isTracksPanelOpen == true }, set: { if !$0 { model.tracks?.closeTracksPanel() } })) {
            if let tracks = model.tracks {
                // The player's own panel, on its own dark ground.
                MovieTracksPanel(model: tracks)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(EditorTheme.panel)
            }
        }
    }

    private func header(_ model: MovieDetailModel, width: CGFloat) -> some View {
        let backdropHeight: CGFloat = isDuoCover ? 240 : (isWide ? 440 : 340)
        let posterSize = isDuoCover ? CGSize(width: 96, height: 144) : (isWide ? CGSize(width: 160, height: 240) : CGSize(width: 112, height: 168))
        return ZStack(alignment: .bottomLeading) {
            backdropView(model)
                .frame(width: width, height: backdropHeight)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color(.systemBackground)], startPoint: .top, endPoint: .bottom)
                        .frame(height: backdropHeight / 2)
                }
            HStack(alignment: .bottom, spacing: 16) {
                MoviePoster(movie: model.movie)
                    .frame(width: posterSize.width, height: posterSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.movie.displayTitle)
                        .font(isDuoCover ? .title3.weight(.bold) : .title2.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Group {
                        if !model.facts.isEmpty { Text(model.facts).monospacedDigit() }
                        if !isDuoCover {
                            if let genres = model.movie.genres { Text(genres) }
                            Text(model.whereFrom).monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .padding(.bottom, 2)
            }
            .padding(.horizontal, isWide ? 32 : AppTheme.Spacing.lg)
            .offset(y: posterSize.height * 0.17)
        }
        .padding(.bottom, posterSize.height * 0.17 + 20)
        .accessibilityElement(children: .combine)
    }

    /// Plex's background, else the poster blurred, else the title tile's
    /// color (§2).
    @ViewBuilder
    private func backdropView(_ model: MovieDetailModel) -> some View {
        if let backdrop {
            Image(decorative: backdrop, scale: 1).resizable().scaledToFill()
        } else {
            MoviePoster(movie: model.movie)
                .scaledToFill()
                .blur(radius: 40)
                .opacity(0.9)
                .task(id: model.movie.artPath) {
                    backdrop = await dependencies.movieArt.backdrop(for: model.movie, maxPixelSize: Int(1280 * min(displayScale, 2) / 2))
                }
        }
    }

    // MARK: Play and Download (§3)

    @ViewBuilder
    private func actions(_ model: MovieDetailModel) -> some View {
        let movie = model.movie
        VStack(alignment: .leading, spacing: 12) {
            if let resume = model.resumeMs {
                Button { play(model, fromStart: false) } label: {
                    Label(String(localized: "Resume · \(MoviePlayerText.clock(resume, longest: resume))", comment: "Movie page: play from where it stopped, e.g. Resume · 47:12"), systemImage: "play.fill")
                        .font(.headline)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(MovieDetailButtonStyle(isProminent: true))
                // Board PH_MovieDetail: the bar sits 4 pt under the button.
                watchedBar(model, resumeMs: resume)
                    .padding(.top, -8)
            } else {
                Button { play(model, fromStart: false) } label: {
                    Label(String(localized: "Play", comment: "Movie page: play the movie"), systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(MovieDetailButtonStyle(isProminent: true))
            }
            HStack(spacing: AppTheme.Spacing.lg) {
                if model.resumeMs != nil {
                    Button { play(model, fromStart: true) } label: {
                        Label(String(localized: "From Beginning", comment: "Movie page: play from 0:00"), systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(MovieDetailButtonStyle())
                }
                if !isDuoCover, movie.sourceId != nil { downloadButton(model) }
            }
            .font(.subheadline.weight(.semibold))
            if let error = movie.downloadError, !isDuoCover {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func watchedBar(_ model: MovieDetailModel, resumeMs: Int64) -> some View {
        let duration = max(model.movie.durationMs ?? 0, 1)
        return HStack(spacing: 8) {
            ProgressView(value: Double(resumeMs), total: Double(duration))
                .tint(AppAccent.color)
            Text(String(localized: "\(MoviePlayerText.clock(max(0, duration - resumeMs), longest: max(0, duration - resumeMs))) left", comment: "Movie page: time left to watch, e.g. 1:58:48 left"))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func downloadButton(_ model: MovieDetailModel) -> some View {
        let movie = model.movie
        let downloads = dependencies.movieDownloads
        if movie.isOnDevice {
            Button { isRemovingDownload = true } label: {
                Label(MoviesCountText.onDeviceShort(), systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(MovieDetailButtonStyle())
        } else if movie.isDownloading {
            let progress = movie.byteCount > 0 ? min(1, Double(downloads.bytes(for: movie)) / Double(movie.byteCount)) : 0
            Button { isRemovingDownload = true } label: {
                Text(movie.downloadedBytes == 0 && downloads.bytes(for: movie) == 0
                     ? String(localized: "Waiting…", comment: "Movie grid: a download queued or about to start")
                     : String(localized: "Downloading \(Int(progress * 100))%", comment: "Movie grid caption and VoiceOver: download progress"))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle().fill(Color(.tertiaryLabel).opacity(0.35)).frame(width: proxy.size.width * progress)
                        }
                    }
            }
            .buttonStyle(MovieDetailButtonStyle())
        } else if movie.downloadError != nil {
            Button { downloads.retry(movie.id) } label: {
                Label(String(localized: "Retry Download", comment: "Movie menu: try a stopped download again"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(MovieDetailButtonStyle())
        } else {
            Button { download(model) } label: {
                Label(String(localized: "Download", comment: "Movie page: keep this movie on the device"), systemImage: "arrow.down.to.line")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(MovieDetailButtonStyle())
            .accessibilityLabel("\(MoviesCountText.downloadTo()), \(movie.byteCount.formatted(.byteCount(style: .file)))")
        }
    }

    // MARK: Summary and tracks (§2, §4)

    @ViewBuilder
    private func summary(_ model: MovieDetailModel) -> some View {
        if let summary = model.movie.summary, !summary.isEmpty {
            Text(summary)
                .font(.subheadline)
                .lineLimit(showsWholeSummary ? nil : 3)
                .onTapGesture { showsWholeSummary.toggle() }
                .accessibilityAddTraits(.isButton)
        }
    }

    private func trackCard(_ model: MovieDetailModel) -> some View {
        VStack(spacing: 0) {
            trackRow(String(localized: "Audio", comment: "Movie page row: the audio track"), value: model.audioSummary) {
                model.tracks?.openTracksPanel()
            }
            Divider().padding(.leading, AppTheme.Spacing.lg)
            trackRow(String(localized: "Subtitles", comment: "Movie page row: the subtitles"), value: model.subtitleSummary) {
                model.tracks?.openTracksPanel()
            }
            if !isDuoCover, model.versions.count > 1, let version = model.chosenVersion {
                Divider().padding(.leading, AppTheme.Spacing.lg)
                trackRow(String(localized: "Version", comment: "Movie page row: which Plex version plays and downloads"), value: version.label) {
                    choosingVersion = true
                }
                .confirmationDialog(
                    String(localized: "Version", comment: "Movie page row: which Plex version plays and downloads"),
                    isPresented: $choosingVersion, titleVisibility: .visible
                ) {
                    ForEach(Array(model.versions.enumerated()), id: \.offset) { _, version in
                        Button(version.label) { model.choose(version) }
                    }
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .disabled(model.tracks == nil)
    }

    private func trackRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
    }

    // MARK: ⋯ (A2)

    private func moreMenu(_ model: MovieDetailModel) -> some View {
        let movie = model.movie
        return Menu {
            if movie.isWatched {
                Button { setWatched(false, model) } label: {
                    Label(String(localized: "Mark as Unwatched", comment: "Movie menu"), systemImage: "eye.slash")
                }
            } else {
                Button { setWatched(true, model) } label: {
                    Label(String(localized: "Mark as Watched", comment: "Movie menu"), systemImage: "eye")
                }
            }
            Button {
                typedTitle = movie.displayTitle
                isRenaming = true
            } label: {
                Label(String(localized: "Rename", comment: "Movie menu"), systemImage: "pencil")
            }
            if movie.sourceId != nil, movie.isOnDevice || movie.isDownloading {
                Button(role: .destructive) { isRemovingDownload = true } label: {
                    Label(String(localized: "Remove Download", comment: "Movie menu: delete the copy on this device"), systemImage: "arrow.uturn.backward.circle")
                }
            }
            if movie.sourceId == nil, movie.isOnDevice || movie.state == .missing {
                Button(role: .destructive) { isRemovingCopy = true } label: {
                    Label(String(localized: "Remove from Movies", comment: "Movie menu: delete a copied-in movie"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(.primary)
        .accessibilityLabel(String(localized: "More", comment: "Movie page: the ⋯ button"))
    }

    // MARK: Actions

    private func play(_ model: MovieDetailModel, fromStart: Bool) {
        let movie = model.movie
        if let sourceId = movie.sourceId, !movie.isOnDevice,
           (try? dependencies.movies.source(id: sourceId))?.isReachable == false {
            awayFrom = movie.sourceName ?? ""
            return
        }
        model.unload()
        Task {
            do {
                playing = try await MoviePlayback(dependencies: dependencies).open(movie, fromStart: fromStart)
            } catch {
                awayFrom = movie.sourceName ?? ""
            }
        }
    }

    /// The version shown is the one that downloads (§4); a Plex movie whose
    /// versions are not known yet asks its server first.
    private func download(_ model: MovieDetailModel) {
        let downloads = dependencies.movieDownloads
        if let version = model.chosenVersion {
            model.choose(version)
        } else if model.movie.plexRatingKey != nil {
            downloads.prepare(model.movie.id)
            Task {
                let preparer = PlexDownloadPreparer(store: dependencies.movies)
                if let best = try? await preparer.versions(of: model.movie).first { try? preparer.choose(best, for: model.movie) }
                downloads.download(model.movie.id)
            }
            return
        }
        downloads.download(model.movie.id)
    }

    private func setWatched(_ isWatched: Bool, _ model: MovieDetailModel) {
        try? dependencies.movies.setWatched(isWatched, ids: [model.movie.id])
        model.reload()
    }
}

/// The page's capsules: the accent Play/Resume, the filled others.
struct MovieDetailButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background(isProminent ? AnyShapeStyle(AppAccent.color) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
