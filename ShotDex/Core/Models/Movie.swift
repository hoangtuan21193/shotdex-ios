import Foundation
import GRDB

/// Where Movies finds films (FS-23.01 §2): a folder on an FS-15 connection
/// or in Files, or a Plex server. Copied-in files have no source.
struct MovieSource: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case folder
        case plex
    }

    var id: String
    var kind: Kind
    var name: String
    /// Folder: the FS-15 connection (a Files folder is a connection too).
    var connectionId: String?
    /// Folder: the path inside the connection.
    var folder: String
    /// Plex: the server's machine identifier.
    var plexMachineId: String?
    /// Plex: the connection that answered last (FS-23.07 §2) — tried first
    /// next time.
    var plexAddress: String?
    /// Plex: JSON array of library section keys; empty = every Movies and
    /// TV Shows library.
    var plexLibraries: String
    var lastScannedAt: Int?
    var isReachable: Bool
    /// Plex: the token was refused — `Sign in to Plex again` (FS-23.07 §5).
    var needsSignIn: Bool
    var createdAt: Int

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        name: String,
        connectionId: String? = nil,
        folder: String = "",
        plexMachineId: String? = nil,
        plexAddress: String? = nil,
        plexLibraries: String = "[]",
        lastScannedAt: Int? = nil,
        isReachable: Bool = true,
        needsSignIn: Bool = false,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.connectionId = connectionId
        self.folder = folder
        self.plexMachineId = plexMachineId
        self.plexAddress = plexAddress
        self.plexLibraries = plexLibraries
        self.lastScannedAt = lastScannedAt
        self.isReachable = isReachable
        self.needsSignIn = needsSignIn
        self.createdAt = createdAt
    }
}

extension MovieSource: FetchableRecord, PersistableRecord {
    static let databaseTableName = "movie_sources"
}

/// One film or episode in Movies (FS-23.01 §3, FS-23.05 §2). The file facts
/// come from the source and are rewritten by every scan; everything the
/// user did — where they stopped, watched, the name they typed, the track
/// they picked — is theirs and survives it.
struct Movie: Codable, Identifiable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        /// Plays over the home network; nothing on the device.
        case stream
        /// Waiting its turn in the download queue (one at a time).
        case queued
        case downloading
        case onDevice
        case unplayable
        /// On-device row whose file is gone (FS-23.05 §1) — shown, never
        /// deleted behind the user's back.
        case missing
    }

    var id: String
    /// nil = copied straight onto the device, or its source was removed
    /// after it was downloaded.
    var sourceId: String?
    /// The source's name when the movie came from it — the List row's
    /// "where", still there after the source is removed.
    var sourceName: String?
    /// Folder source: path inside the connection. Never set for Plex rows,
    /// which are keyed by `plexRatingKey`.
    var remotePath: String?
    /// Plex: the server, so a download outlives its source and rejoins it
    /// when the same server is added again.
    var plexMachineId: String?
    var plexRatingKey: String?
    /// The Plex version (part) being or already downloaded (AC-56).
    var plexPartKey: String?
    /// From Plex, else read from the file name (`Dune.Part.Two.2024…`).
    var title: String
    /// What the user typed in Rename; wins over `title`.
    var customTitle: String?
    var year: Int?
    var season: Int?
    var episode: Int?
    var originalFileName: String
    /// The file's name in `Movies/<id>/` once downloaded or copied in. Set
    /// once; a rename on the source does not move a file already here.
    var localFileName: String?
    var byteCount: Int64
    /// FS-23.05 §3, 16 hex characters; nil until read.
    var fileHash: String?
    var durationMs: Int64?
    var summary: String?
    /// JSON array of genre names (Plex).
    var genres: String?
    /// Folder: the poster image next to the movie (path on the
    /// connection); Plex: the thumb path. nil = the resolver's later steps.
    var posterPath: String?
    var state: State
    var downloadedBytes: Int64
    /// Why the last download stopped, as the row shows it.
    var downloadError: String?
    /// The source stopped listing it. A downloaded copy stays and shows
    /// `Removed from Plex` (FS-23.07 §4); a streamed row is hidden and kept
    /// 30 days with what the user did, in case the file comes back.
    var removedFromSourceAt: Int?
    var addedAt: Int
    var lastPlayedAt: Int?
    var positionMs: Int64
    var isWatched: Bool
    var playbackRate: Double
    var audioTrackId: String?
    var audioDelayMs: Int
    /// Position or watched changed while the Plex server was out of reach;
    /// sent when it answers again, latest view wins (FS-23.07 §4).
    var plexSyncPending: Bool

    init(
        id: String = UUID().uuidString,
        sourceId: String?,
        sourceName: String? = nil,
        remotePath: String? = nil,
        plexMachineId: String? = nil,
        plexRatingKey: String? = nil,
        plexPartKey: String? = nil,
        title: String,
        customTitle: String? = nil,
        year: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        originalFileName: String,
        localFileName: String? = nil,
        byteCount: Int64,
        fileHash: String? = nil,
        durationMs: Int64? = nil,
        summary: String? = nil,
        genres: String? = nil,
        posterPath: String? = nil,
        state: State,
        downloadedBytes: Int64 = 0,
        downloadError: String? = nil,
        removedFromSourceAt: Int? = nil,
        addedAt: Int = Int(Date().timeIntervalSince1970),
        lastPlayedAt: Int? = nil,
        positionMs: Int64 = 0,
        isWatched: Bool = false,
        playbackRate: Double = 1,
        audioTrackId: String? = nil,
        audioDelayMs: Int = 0,
        plexSyncPending: Bool = false
    ) {
        self.id = id
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.remotePath = remotePath
        self.plexMachineId = plexMachineId
        self.plexRatingKey = plexRatingKey
        self.plexPartKey = plexPartKey
        self.title = title
        self.customTitle = customTitle
        self.year = year
        self.season = season
        self.episode = episode
        self.originalFileName = originalFileName
        self.localFileName = localFileName
        self.byteCount = byteCount
        self.fileHash = fileHash
        self.durationMs = durationMs
        self.summary = summary
        self.genres = genres
        self.posterPath = posterPath
        self.state = state
        self.downloadedBytes = downloadedBytes
        self.downloadError = downloadError
        self.removedFromSourceAt = removedFromSourceAt
        self.addedAt = addedAt
        self.lastPlayedAt = lastPlayedAt
        self.positionMs = positionMs
        self.isWatched = isWatched
        self.playbackRate = playbackRate
        self.audioTrackId = audioTrackId
        self.audioDelayMs = audioDelayMs
        self.plexSyncPending = plexSyncPending
    }

    /// The name the grid shows.
    var displayTitle: String { customTitle ?? title }

    /// Playable with no network.
    var isOnDevice: Bool { state == .onDevice }

    /// The file is, or is becoming, the user's copy — a scan must not
    /// rewrite its name or size.
    var holdsLocalFile: Bool {
        switch state {
        case .onDevice, .missing, .queued, .downloading: true
        case .stream, .unplayable: false
        }
    }

    /// Gone from its source and nothing here to play: not on the grid.
    var isHidden: Bool { removedFromSourceAt != nil && !(state == .onDevice || state == .missing) }
}

extension Movie: FetchableRecord, PersistableRecord {
    static let databaseTableName = "movies"
}

/// One subtitle ShotDex holds for a movie, as a file in `Movies/<id>/`
/// (FS-23.03, FS-23.05 §2).
struct MovieSubtitle: Codable, Identifiable, Hashable, Sendable {
    enum Origin: String, Codable, Sendable {
        /// Pulled out of the movie file (FS-23.03 §3).
        case inFile
        /// Same name next to the movie on the source.
        case sidecar
        case imported
        case shared
        /// A Plex sidecar subtitle.
        case plex
        /// Made by Translate (FS-23.04).
        case translated
    }

    enum Format: String, Codable, Sendable {
        case srt
        case ass
        case vtt
    }

    var id: String
    var movieId: String
    /// BCP 47 (`en`, `vi`); nil when nothing says.
    var language: String?
    var origin: Origin
    /// In-file: the Matroska track number it came from.
    var inFileTrack: Int?
    /// Sidecar or Plex: the file on the source; `fileName` is empty until
    /// it has been fetched into `Movies/<movieId>/`.
    var remotePath: String?
    /// Translated: the subtitle it was made from, and by whom.
    var translatedFromId: String?
    var translationProviderId: String?
    var format: Format
    /// Detected or picked by the user (⋯ › Encoding).
    var encoding: String?
    /// Inside `Movies/<movieId>/`.
    var fileName: String
    var offsetMs: Int
    var addedAt: Int

    init(
        id: String = UUID().uuidString,
        movieId: String,
        language: String?,
        origin: Origin,
        inFileTrack: Int? = nil,
        remotePath: String? = nil,
        translatedFromId: String? = nil,
        translationProviderId: String? = nil,
        format: Format,
        encoding: String? = nil,
        fileName: String,
        offsetMs: Int = 0,
        addedAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.movieId = movieId
        self.language = language
        self.origin = origin
        self.inFileTrack = inFileTrack
        self.remotePath = remotePath
        self.translatedFromId = translatedFromId
        self.translationProviderId = translationProviderId
        self.format = format
        self.encoding = encoding
        self.fileName = fileName
        self.offsetMs = offsetMs
        self.addedAt = addedAt
    }
}

extension MovieSubtitle: FetchableRecord, PersistableRecord {
    static let databaseTableName = "movie_subtitles"
}

/// What the Audio & Subtitles panel last chose for a movie. No row = the
/// defaults from Settings.
struct MovieSubtitleChoice: Codable, Hashable, Sendable {
    var movieId: String
    var primaryId: String?
    var secondaryId: String?
    /// JSON (placement, size and color per line), decoded leniently by the
    /// player.
    var style: String

    init(movieId: String, primaryId: String? = nil, secondaryId: String? = nil, style: String = "{}") {
        self.movieId = movieId
        self.primaryId = primaryId
        self.secondaryId = secondaryId
        self.style = style
    }
}

extension MovieSubtitleChoice: FetchableRecord, PersistableRecord {
    static let databaseTableName = "movie_subtitle_choices"
}

/// A translation that has not finished (FS-23.04): picks up at `cuesDone`.
struct MovieTranslationJob: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var movieId: String
    var fromSubtitleId: String
    var toLanguage: String
    var providerId: String
    var cuesDone: Int
    var cueCount: Int
    /// Inside `Movies/<movieId>/`.
    var partialFileName: String
    var startedAt: Int
    var updatedAt: Int

    init(
        id: String = UUID().uuidString,
        movieId: String,
        fromSubtitleId: String,
        toLanguage: String,
        providerId: String,
        cuesDone: Int = 0,
        cueCount: Int,
        partialFileName: String,
        startedAt: Int = Int(Date().timeIntervalSince1970),
        updatedAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.movieId = movieId
        self.fromSubtitleId = fromSubtitleId
        self.toLanguage = toLanguage
        self.providerId = providerId
        self.cuesDone = cuesDone
        self.cueCount = cueCount
        self.partialFileName = partialFileName
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

extension MovieTranslationJob: FetchableRecord, PersistableRecord {
    static let databaseTableName = "movie_translation_jobs"
}

/// What a scan of a source found for one file — the facts the source owns.
struct ScannedMovie: Hashable, Sendable {
    var remotePath: String?
    var plexRatingKey: String?
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?
    var originalFileName: String
    var byteCount: Int64
    var durationMs: Int64?
    var summary: String?
    var genres: String?
    var posterPath: String?
    /// Subtitle files next to the movie (`Dune.en.srt`).
    var subtitles: [ScannedSubtitle]

    init(
        remotePath: String? = nil,
        plexRatingKey: String? = nil,
        title: String,
        year: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        originalFileName: String,
        byteCount: Int64,
        durationMs: Int64? = nil,
        summary: String? = nil,
        genres: String? = nil,
        posterPath: String? = nil,
        subtitles: [ScannedSubtitle] = []
    ) {
        self.remotePath = remotePath
        self.plexRatingKey = plexRatingKey
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.originalFileName = originalFileName
        self.byteCount = byteCount
        self.durationMs = durationMs
        self.summary = summary
        self.genres = genres
        self.posterPath = posterPath
        self.subtitles = subtitles
    }

    /// The source's own key for the file.
    var key: String { plexRatingKey ?? remotePath ?? originalFileName }
}

/// A subtitle file a scan found beside a movie.
struct ScannedSubtitle: Hashable, Sendable {
    var remotePath: String
    var language: String?
    var format: MovieSubtitle.Format
    /// `.sidecar` for a folder source, `.plex` for a Plex sidecar.
    var origin: MovieSubtitle.Origin = .sidecar
}
