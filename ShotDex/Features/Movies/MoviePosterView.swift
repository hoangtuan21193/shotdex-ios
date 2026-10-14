import SwiftUI

/// One movie in the grid (board `PH_Movies`): a 2:3 poster with what it is
/// — ✓ on the device, a progress bar while downloading — and the name and
/// year under it.
struct MovieGridCell: View {
    let movie: Movie
    /// Its source is out of reach (FS-23.01 §3).
    var isAway = false
    @Environment(AppDependencies.self) private var dependencies

    /// Board `PH_Movies`, `away` tweak.
    static let awayOpacity = 0.42

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MoviePoster(movie: movie)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .topTrailing) { if movie.isOnDevice { MovieOnDeviceBadge().padding(6) } }
                .overlay(alignment: .bottom) { MovieDownloadBar(movie: movie) }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            Text(movie.displayTitle)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                // A word smaller before half a word: "Blade Runner 2049".
                .minimumScaleFactor(0.85)
                .padding(.top, 6)
            Text(MovieRowText.caption(movie))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(movie.downloadError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                .lineLimit(1)
        }
        .opacity(isAway ? Self.awayOpacity : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MovieRowText.spoken(movie, isAway: isAway))
        .accessibilityAddTraits(.isButton)
    }
}

/// One movie in List (board `PH_Movies`, List tweak).
struct MovieListRow: View {
    let movie: Movie
    /// Its download needs the app open (SMB, SFTP, Files — FS-23.01 §6).
    var keepsAppOpen = false
    var isAway = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            MoviePoster(movie: movie, compact: true)
                .frame(width: 36, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(MovieRowText.titleWithYear(movie))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(MovieRowText.detail(movie, keepsAppOpen: keepsAppOpen))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(movie.downloadError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if movie.isOnDevice {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isAway ? MovieGridCell.awayOpacity : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MovieRowText.spoken(movie, isAway: isAway))
        .accessibilityAddTraits(.isButton)
    }
}

/// The poster image, or the title tile when there is none (FS-23.01 §4).
struct MoviePoster: View {
    let movie: Movie
    var compact = false
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    MovieTitleTile(movie: movie, compact: compact)
                }
            }
            .task(id: MoviePosterLoader.identity(movie)) {
                let pixels = Int(max(proxy.size.width, proxy.size.height) * displayScale)
                image = await dependencies.movieArt.poster(for: movie, maxPixelSize: max(pixels, 120))
            }
        }
    }
}

/// Title and year on a color picked from the title — the poster a movie
/// has before it has one.
struct MovieTitleTile: View {
    let movie: Movie
    var compact = false

    /// System colors, not app tokens: the tile only has to tell movies apart.
    static let palette: [Color] = [
        Color(.systemIndigo), Color(.systemTeal), Color(.systemOrange), Color(.systemPink),
        Color(.systemGreen), Color(.systemBlue), Color(.systemPurple), Color(.systemBrown),
    ]

    var body: some View {
        let color = Self.palette[MoviePosterResolver.colorIndex(for: movie.displayTitle, palette: Self.palette.count)]
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom)
            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.displayTitle)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)
                    if let caption = MovieRowText.yearOrEpisode(movie) {
                        Text(caption).font(.caption.weight(.medium)).opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
            }
        }
        .accessibilityHidden(true)
    }
}

/// ✓ on a dark disc: this one plays with no network.
struct MovieOnDeviceBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Color.black.opacity(0.72), in: Circle())
            .accessibilityHidden(true)
    }
}

/// The 4 pt bar under a poster while it downloads; red when paused.
struct MovieDownloadBar: View {
    let movie: Movie

    var body: some View {
        if let progress = MovieRowText.downloadProgress(movie) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.45))
                    Rectangle()
                        .fill(movie.downloadError == nil ? AnyShapeStyle(AppAccent.color) : AnyShapeStyle(Color.red))
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
    }
}

/// The words under a poster and in a list row (FS-23.01 §3–§4).
enum MovieRowText {
    static func yearOrEpisode(_ movie: Movie) -> String? {
        if let season = movie.season, let episode = movie.episode { return String(format: "S%02dE%02d", season, episode) }
        return movie.year.map(String.init)
    }

    static func titleWithYear(_ movie: Movie) -> String {
        yearOrEpisode(movie).map { "\(movie.displayTitle) (\($0))" } ?? movie.displayTitle
    }

    static func downloadProgress(_ movie: Movie) -> Double? {
        guard movie.state == .downloading || movie.state == .queued || movie.downloadError != nil,
              movie.byteCount > 0 else { return nil }
        return min(1, Double(movie.downloadedBytes) / Double(movie.byteCount))
    }

    /// Under the poster: the year, or what the download is doing.
    static func caption(_ movie: Movie) -> String {
        if movie.downloadError != nil { return String(localized: "Download paused", comment: "Movie grid: a download that stopped") }
        return yearOrEpisode(movie) ?? ""
    }

    /// List: where it plays from, how long, how big — or the download.
    static func detail(_ movie: Movie, keepsAppOpen: Bool = false) -> String {
        if let error = movie.downloadError { return error }
        let size = movie.byteCount.formatted(.byteCount(style: .file))
        switch movie.state {
        case .downloading, .queued:
            let percent = Int((downloadProgress(movie) ?? 0) * 100)
            let done = movie.downloadedBytes.formatted(.byteCount(style: .file))
            let line = String(localized: "Downloading \(percent)% · \(done) of \(size)", comment: "Movie list row: a download in progress")
            guard keepsAppOpen else { return line }
            return line + " · " + String(localized: "Keep ShotDex open to finish", comment: "Movie list row: this download stops when ShotDex is closed")
        case .onDevice:
            return [MoviesCountText.onDeviceShort(), duration(movie), size].compactMap { $0 }.joined(separator: " · ")
        case .missing:
            return String(localized: "File missing", comment: "Movie list row: the downloaded file is gone")
        case .stream, .unplayable:
            return [movie.sourceName, duration(movie), size].compactMap { $0 }.joined(separator: " · ")
        }
    }

    static func duration(_ movie: Movie) -> String? {
        guard let ms = movie.durationMs, ms > 0 else { return nil }
        return Duration.milliseconds(ms).formatted(.time(pattern: .hourMinuteSecond))
    }

    /// VoiceOver: `Dune: Part Two, 2024, Downloaded`.
    static func spoken(_ movie: Movie, isAway: Bool = false) -> String {
        var parts = [movie.displayTitle]
        if let caption = yearOrEpisode(movie) { parts.append(caption) }
        switch movie.state {
        case .onDevice: parts.append(String(localized: "Downloaded", comment: "Movie VoiceOver: on this device"))
        case .downloading, .queued:
            parts.append(String(localized: "Downloading \(Int((downloadProgress(movie) ?? 0) * 100))%", comment: "Movie VoiceOver: download progress"))
        case .missing: parts.append(String(localized: "File missing", comment: "Movie VoiceOver"))
        case .stream, .unplayable:
            if let name = movie.sourceName {
                parts.append(String(localized: "Streams from \(name)", comment: "Movie VoiceOver: plays over the network from this source"))
            }
        }
        if movie.downloadError != nil { parts.append(String(localized: "Download paused", comment: "Movie VoiceOver")) }
        if isAway { parts.append(String(localized: "Not available offline", comment: "Movie VoiceOver: its source is out of reach")) }
        return parts.joined(separator: ", ")
    }
}
