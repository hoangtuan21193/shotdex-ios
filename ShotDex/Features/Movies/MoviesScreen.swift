import SwiftUI

/// The Movies library (FS-23.01 §4): one library over every source — NAS
/// folders, Plex, files copied in.
struct MoviesScreen: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var model: MoviesModel?
    @State private var isAddingSource = false

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
            ToolbarItem(placement: .topBarTrailing) {
                addMenu
            }
        }
        .task {
            let model = model ?? MoviesModel(store: dependencies.movies)
            self.model = model
            model.load()
        }
        .sheet(isPresented: $isAddingSource, onDismiss: { model?.load() }) {
            AddMovieSourceSheet()
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

    /// Replaced by the poster grid (plan task 10).
    private func library(_ model: MoviesModel) -> some View {
        List(model.shown) { movie in
            VStack(alignment: .leading) {
                Text(movie.displayTitle)
                if let year = movie.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

private extension View {
    /// The `128 movies · 3 on this iPhone` line. A navigation bar has a
    /// subtitle only from iOS 26; earlier the screen goes without it.
    @ViewBuilder
    func moviesSubtitle(_ subtitle: String?) -> some View {
        if #available(iOS 26.0, *), let subtitle {
            navigationSubtitle(Text(subtitle))
        } else {
            self
        }
    }
}
