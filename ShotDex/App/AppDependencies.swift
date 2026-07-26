import Foundation
import SwiftUI

/// Composition root. Built once at launch and injected through the environment.
@MainActor
@Observable
final class AppDependencies {
    let database: AppDatabase
    let metadataStore: MetadataStore
    let libraryQueries: LibraryQueries
    let filterSuggestions: FilterSuggestionCache
    let statisticsQueries: StatisticsQueries
    let smartAlbumStore: SmartAlbumStore
    let chartStore: ChartStore
    let photoLibrary: PhotoLibraryService
    let importService: ImportService
    let indexPipeline: IndexPipeline
    let backgroundIndex: BackgroundIndexService
    let networkStatus: NetworkMonitor
    let powerStatus: PowerMonitor
    let indexTraffic: IndexTrafficMonitor
    let indexInteractionGate: IndexInteractionGate

    init(database: AppDatabase, photoLibrary: PhotoLibraryService) {
        let metadataStore = MetadataStore(database: database)
        let indexTraffic = IndexTrafficMonitor()
        let indexInteractionGate = IndexInteractionGate()
        let indexPipeline = IndexPipeline(
            metadataStore: MetadataStore(database: database),
            exifReader: ExifReader(trafficMonitor: indexTraffic),
            interactionGate: indexInteractionGate
        )
        self.database = database
        self.metadataStore = metadataStore
        let libraryQueries = LibraryQueries(database: database)
        self.libraryQueries = libraryQueries
        self.filterSuggestions = FilterSuggestionCache(libraryQueries: libraryQueries)
        self.statisticsQueries = StatisticsQueries(database: database)
        self.smartAlbumStore = SmartAlbumStore(database: database)
        self.chartStore = ChartStore(database: database)
        self.photoLibrary = photoLibrary
        self.importService = ImportService(photoLibrary: photoLibrary, metadataStore: metadataStore)
        self.indexPipeline = indexPipeline
        self.backgroundIndex = BackgroundIndexService(pipeline: indexPipeline, metadataStore: metadataStore)
        self.networkStatus = NetworkMonitor()
        self.powerStatus = PowerMonitor()
        self.indexTraffic = indexTraffic
        self.indexInteractionGate = indexInteractionGate
    }

    /// Re-resolves cameras indexed as Unknown against the bundled sensor
    /// database — an app update that ships new records fixes already-indexed
    /// photos without a reindex. Cheap: touches only still-unknown models.
    func resolveNewlyKnownCameras() {
        let store = metadataStore
        Task.detached(priority: .utility) {
            guard let records = try? SensorDatabaseLoader().loadRecords() else { return }
            let mappings = (try? store.customMappings()) ?? []
            try? store.resolveUnknownCameras(using: SensorLookup(records: records, customMappings: mappings))
        }
    }

    static func live() -> AppDependencies {
        let database: AppDatabase
        do {
            database = try AppDatabase.makeShared()
        } catch {
            // A broken on-disk database would leave the app unusable;
            // fall back to an in-memory store so the UI can still surface the error.
            assertionFailure("Failed to open database: \(error)")
            database = (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        }
        return AppDependencies(database: database, photoLibrary: PhotoLibraryService())
    }

    static func preview() -> AppDependencies {
        let database = (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        return AppDependencies(database: database, photoLibrary: PhotoLibraryService())
    }
}
