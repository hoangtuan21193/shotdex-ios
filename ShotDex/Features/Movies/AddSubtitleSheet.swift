import SwiftUI

/// A subtitle file shared or AirDropped in (FS-23.03 §5, AC-25, board
/// `PH_MovieSubtitleAdd`): pick the movie it belongs to. The one named like
/// the file comes first and says so, then the ones watched lately.
struct AddSubtitleSheet: View {
    let urls: [URL]
    let movies: [Movie]
    let onPick: (Movie) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent

    private var fileName: String { urls.first?.lastPathComponent ?? "" }

    private var match: Movie? { SubtitleFileName.matchingMovie(fileName, in: movies) }

    /// Matching first, then most recently watched, then by title.
    private var ordered: [Movie] {
        let match = match
        let rest = movies.filter { $0.id != match?.id }.sorted { lhs, rhs in
            switch (lhs.lastPlayedAt, rhs.lastPlayedAt) {
            case let (l?, r?): l > r
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
        }
        return (match.map { [$0] } ?? []) + rest
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ordered) { movie in
                        Button {
                            onPick(movie)
                            dismiss()
                        } label: {
                            row(movie)
                        }
                        .tint(.primary)
                        // Board PH_MovieSubtitleAdd: 64 pt rows.
                        .listRowInsets(EdgeInsets(top: AppTheme.Spacing.md, leading: AppTheme.Spacing.lg, bottom: AppTheme.Spacing.md, trailing: AppTheme.Spacing.lg))
                    }
                } footer: {
                    Text(String(localized: "The subtitle is copied to this device and stays with the movie for offline viewing.", comment: "Add Subtitle to… footer"))
                }
            }
            // Board: the list starts 16 pt under the title bar.
            .contentMargins(.top, AppTheme.Spacing.lg, for: .scrollContent)
            .overlay {
                if movies.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Movies Yet", comment: "Add Subtitle to… with an empty library"),
                        systemImage: "play.rectangle",
                        description: Text(String(localized: "Add a movie first, then share the subtitle again.", comment: "Add Subtitle to… with an empty library"))
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(String(localized: "Add Subtitle to…", comment: "Sheet title: pick the movie a shared subtitle belongs to"))
                            .font(.headline)
                        Text(subtitleLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Add Subtitle to…: keep the file out")) { dismiss() }
                }
            }
        }
    }

    /// `Dune.Part.Two.vi.srt · Tiếng Việt`; several files: `3 subtitle files`.
    private var subtitleLine: String {
        guard urls.count == 1 else {
            return String(localized: "\(urls.count) subtitle files", comment: "Add Subtitle to… subtitle: number of files shared")
        }
        guard let code = SubtitleFileName.language(fileName), let name = MovieLanguage.endonym(code) else { return fileName }
        return "\(fileName) · \(name)"
    }

    private func row(_ movie: Movie) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            MoviePoster(movie: movie, compact: true)
                .frame(width: 64, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(MovieRowText.titleWithYear(movie))
                    .lineLimit(1)
                if movie.id == match?.id {
                    Text(String(localized: "Matches file name", comment: "Add Subtitle to…: the movie named like the shared file"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accent)
                } else if let played = movie.lastPlayedAt {
                    Text(String(localized: "Watched \(Date(timeIntervalSince1970: TimeInterval(played)).formatted(.relative(presentation: .named)))", comment: "Add Subtitle to…: when the movie was last watched, e.g. Watched yesterday"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }
}
