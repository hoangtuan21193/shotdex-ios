import Foundation
import Observation
import UIKit

/// Navigation value for the Movies screen (Collections › Utilities, FS-23.01).
struct MoviesDestination: Hashable {}

/// What the Movies screen shows: the library, the search, the filter and
/// the sort (FS-23.01 §4). Rows come from `MovieStore`; filtering runs here
/// over what is loaded, so it works with no network.
@MainActor
@Observable
final class MoviesModel {
    private let store: MovieStore

    private(set) var movies: [Movie] = []
    private(set) var isLoaded = false
    var query = MovieLibraryQuery()

    init(store: MovieStore) {
        self.store = store
    }

    var shown: [Movie] { query.apply(movies) }
    var counts: (total: Int, onDevice: Int) { MovieLibraryQuery.counts(movies) }
    var isEmpty: Bool { isLoaded && counts.total == 0 }

    func load() {
        movies = (try? store.movies()) ?? []
        isLoaded = true
    }

    func rename(_ movie: Movie, to title: String) {
        try? store.rename(id: movie.id, to: title)
        load()
    }

    func setWatched(_ isWatched: Bool, _ movie: Movie) {
        try? store.setWatched(isWatched, ids: [movie.id])
        load()
    }
}

/// Grid or List, remembered (FS-23.01 §4).
enum MoviesLayout: String, CaseIterable, Sendable {
    case grid
    case list
}

/// The words that name this device (`On This iPhone`, `3 on this iPad`) —
/// FS-23.01 §4: every "iPhone" in the spec is the device in hand.
enum MoviesCountText {
    enum Device {
        case iPhone, iPad, mac

        static var current: Device {
            #if targetEnvironment(macCatalyst)
            return .mac
            #else
            if ProcessInfo.processInfo.isiOSAppOnMac { return .mac }
            return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
            #endif
        }
    }

    /// `128 movies · 3 on this iPhone`; nil for an empty library.
    static func subtitle(_ counts: (total: Int, onDevice: Int), device: Device = .current) -> String? {
        guard counts.total > 0 else { return nil }
        let total = String(AttributedString(localized: "^[\(counts.total) movie](inflect: true)").characters)
        return "\(total) · \(onDevice(counts.onDevice, device: device))"
    }

    /// What VoiceOver says on the Movies row: `128 movies, 3 on this iPhone`.
    static func spoken(_ counts: (total: Int, onDevice: Int), device: Device = .current) -> String {
        let total = String(AttributedString(localized: "^[\(counts.total) movie](inflect: true)").characters)
        return "\(total), \(onDevice(counts.onDevice, device: device))"
    }

    static func onDevice(_ count: Int, device: Device) -> String {
        switch device {
        case .iPhone: String(localized: "\(count) on this iPhone", comment: "Movies: how many movies play with no network on this iPhone")
        case .iPad: String(localized: "\(count) on this iPad", comment: "Movies: how many movies play with no network on this iPad")
        case .mac: String(localized: "\(count) on this Mac", comment: "Movies: how many movies play with no network on this Mac")
        }
    }

    /// The filter chip (FS-23.01 §4).
    static func onThisDevice(_ device: Device = .current) -> String {
        switch device {
        case .iPhone: String(localized: "On This iPhone", comment: "Movies filter: movies stored on this iPhone")
        case .iPad: String(localized: "On This iPad", comment: "Movies filter: movies stored on this iPad")
        case .mac: String(localized: "On This Mac", comment: "Movies filter: movies stored on this Mac")
        }
    }

    /// Movie menu: `Download to iPhone` (FS-23.01 §5).
    static func downloadTo(_ device: Device = .current) -> String {
        switch device {
        case .iPhone: String(localized: "Download to iPhone", comment: "Movie menu: keep this movie on the iPhone")
        case .iPad: String(localized: "Download to iPad", comment: "Movie menu: keep this movie on the iPad")
        case .mac: String(localized: "Download to Mac", comment: "Movie menu: keep this movie on the Mac")
        }
    }

    /// The List row's "where": `On iPhone`.
    static func onDeviceShort(_ device: Device = .current) -> String {
        switch device {
        case .iPhone: String(localized: "On iPhone", comment: "Movie list row: stored on this iPhone")
        case .iPad: String(localized: "On iPad", comment: "Movie list row: stored on this iPad")
        case .mac: String(localized: "On Mac", comment: "Movie list row: stored on this Mac")
        }
    }

    /// Add a Source's last line.
    static func addFilesInstead(_ device: Device = .current) -> String {
        switch device {
        case .iPhone: String(localized: "To copy one file straight to this iPhone, use Add Movie Files… instead.", comment: "Add a Source footer")
        case .iPad: String(localized: "To copy one file straight to this iPad, use Add Movie Files… instead.", comment: "Add a Source footer")
        case .mac: String(localized: "To copy one file straight to this Mac, use Add Movie Files… instead.", comment: "Add a Source footer")
        }
    }

    /// The empty screen's line.
    static func emptyDescription(_ device: Device = .current) -> String {
        switch device {
        case .iPhone: String(localized: "Add a folder on your NAS or a Plex server, or copy movie files to this iPhone.", comment: "Movies empty state")
        case .iPad: String(localized: "Add a folder on your NAS or a Plex server, or copy movie files to this iPad.", comment: "Movies empty state")
        case .mac: String(localized: "Add a folder on your NAS or a Plex server, or copy movie files to this Mac.", comment: "Movies empty state")
        }
    }
}
