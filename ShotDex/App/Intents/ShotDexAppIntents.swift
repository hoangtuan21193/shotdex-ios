import AppIntents
import Foundation
import SwiftUI

/// What a Shortcut or a Siri phrase asked the app to open, handed to the
/// running scene rather than performed inside the intent.
///
/// The intents cannot do the work themselves: the library, the index and the
/// navigation state all live on the running app's dependency graph, and an
/// intent process has none of it. So each one records a request and opens the
/// app, and `RootTabView` drains it.
@MainActor
@Observable
final class IntentRouter {
    enum Request: Equatable {
        case library
        case search(String)
        case favorites
        case camera(String)
        case statistics
        case places
        case trips
        /// A photo handed over from another device, already translated into
        /// this device's own identifier.
        case photo(assetId: String)
    }

    static let shared = IntentRouter()

    /// Set by an intent, consumed once by the root view.
    var pending: Request?

    private init() {}

    func request(_ request: Request) {
        pending = request
    }
}

// MARK: - Intents

struct OpenLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Library"
    static let description = IntentDescription("Opens your photo library in ShotDex.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.library)
        return .result()
    }
}

struct SearchPhotosIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Photos"
    static let description = IntentDescription(
        "Searches your library by camera, lens, exposure settings, place or date."
    )
    static let openAppWhenRun = true

    @Parameter(
        title: "Search",
        requestValueDialog: "What should I look for?"
    )
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search ShotDex for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.search(query))
        return .result()
    }
}

struct ShowFavoritesIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Favorites"
    static let description = IntentDescription("Opens your favorite photos.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.favorites)
        return .result()
    }
}

struct ShowCameraPhotosIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Photos from a Camera"
    static let description = IntentDescription(
        "Opens the photos taken with one camera body."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Camera", requestValueDialog: "Which camera?")
    var camera: String

    static var parameterSummary: some ParameterSummary {
        Summary("Show photos from \(\.$camera)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.camera(camera))
        return .result()
    }
}

struct ShowStatisticsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Gear Statistics"
    static let description = IntentDescription(
        "Opens the statistics for your cameras, lenses and focal lengths."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.statistics)
        return .result()
    }
}

struct ShowPlacesIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Places"
    static let description = IntentDescription("Opens the map of where you have shot.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.places)
        return .result()
    }
}

struct ShowTripsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Trips"
    static let description = IntentDescription("Opens the trips found in your library.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.trips)
        return .result()
    }
}

// MARK: - Spoken phrases

/// The phrases Siri and Spotlight offer without the user building a shortcut
/// first. Every phrase has to name the app, which is why they read a little
/// stiffly — that is the system's requirement, not a style choice.
struct ShotDexShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchPhotosIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Find photos in \(.applicationName)",
            ],
            shortTitle: "Search Photos",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: ShowFavoritesIntent(),
            phrases: [
                "Show my favorites in \(.applicationName)",
                "Open favorites in \(.applicationName)",
            ],
            shortTitle: "Favorites",
            systemImageName: "heart"
        )
        AppShortcut(
            intent: ShowStatisticsIntent(),
            phrases: [
                "Show my gear statistics in \(.applicationName)",
                "Open statistics in \(.applicationName)",
            ],
            shortTitle: "Statistics",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: ShowPlacesIntent(),
            phrases: [
                "Show my places in \(.applicationName)",
                "Open the map in \(.applicationName)",
            ],
            shortTitle: "Places",
            systemImageName: "map"
        )
        AppShortcut(
            intent: ShowTripsIntent(),
            phrases: [
                "Show my trips in \(.applicationName)",
                "Open trips in \(.applicationName)",
            ],
            shortTitle: "Trips",
            systemImageName: "airplane"
        )
        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Library",
            systemImageName: "photo.on.rectangle"
        )
    }
}
