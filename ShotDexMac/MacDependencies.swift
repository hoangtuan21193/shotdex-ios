import Foundation
import Observation

/// The Mac's composition root (FS-18 T1): the shared data layer, built once
/// in `ShotDexMacApp`. It provides `LibraryServices`, so the Library grid
/// runs on the same `LibraryModel` as iOS. The iOS `AppDependencies` is not
/// reused whole — it builds ~30 iOS-only services (background tasks,
/// widgets, Spotlight) the Mac does not have.
@MainActor
@Observable
final class MacDependencies: LibraryServices {
    let database: AppDatabase
    let metadataStore: MetadataStore
    let libraryQueries: LibraryQueries
    let filterSuggestions: FilterSuggestionCache
    let indexPipeline: IndexPipeline
    let placeIndexPass: PlaceIndexPass
    let keywordMirror: ExtendedMetadataMirrorPass? = nil
    let unsupportedRAWIndex: UnsupportedRAWIndex
    let indexRunAssertion: any IndexRunAssertion = MacIndexActivity()
    let photoLibrary: PhotoLibraryService
    let networkStatus: NetworkMonitor
    let powerStatus: PowerMonitor
    let indexTraffic: IndexTrafficMonitor
    let sources: SourceStore

    init(database: AppDatabase, photoLibrary: PhotoLibraryService) {
        self.database = database
        self.photoLibrary = photoLibrary
        metadataStore = MetadataStore(database: database)
        let indexTraffic = IndexTrafficMonitor()
        self.indexTraffic = indexTraffic
        indexPipeline = IndexPipeline(
            metadataStore: MetadataStore(database: database),
            exifReader: ExifReader(trafficMonitor: indexTraffic),
            interactionGate: IndexInteractionGate()
        )
        let libraryQueries = LibraryQueries(database: database)
        self.libraryQueries = libraryQueries
        filterSuggestions = FilterSuggestionCache(libraryQueries: libraryQueries)
        let placeStore = PlaceStore(database: database)
        placeIndexPass = PlaceIndexPass(store: placeStore, geocoder: PlaceGeocodingService(store: placeStore))
        unsupportedRAWIndex = UnsupportedRAWIndex(store: RAWVerdictStore(database: database))
        networkStatus = NetworkMonitor()
        powerStatus = PowerMonitor()
        sources = SourceStore(database: database)
    }

    static func live() -> MacDependencies {
        let database: AppDatabase
        do {
            database = try AppDatabase.makeShared()
        } catch {
            assertionFailure("Failed to open database: \(error)")
            database = (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        }
        return MacDependencies(database: database, photoLibrary: PhotoLibraryService())
    }
}

/// An index run on the Mac: an activity that keeps App Nap from throttling
/// it while the window is in the background. Nothing expires it.
@MainActor
final class MacIndexActivity: IndexRunAssertion {
    private var activity: NSObjectProtocol?

    func beginRunAssertion(onExpiry: @escaping @MainActor () -> Void) {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Indexing the photo library")
    }

    func endRunAssertion() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
