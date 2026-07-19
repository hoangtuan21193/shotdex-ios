import Foundation
import SwiftUI

/// Composition root. Built once at launch and injected through the environment.
@MainActor
@Observable
final class AppDependencies {
    let database: AppDatabase
    let metadataDAO: MetadataDAO
    let libraryQueryDAO: LibraryQueryDAO
    let statsDAO: StatsDAO
    let photoLibrary: PhotoLibraryService
    let indexPipeline: IndexPipeline
    let backgroundIndex: BackgroundIndexService
    let networkStatus: NetworkStatusService
    let indexTraffic: IndexTrafficMonitor

    init(database: AppDatabase, photoLibrary: PhotoLibraryService) {
        let metadataDAO = MetadataDAO(database: database)
        let indexTraffic = IndexTrafficMonitor()
        let indexPipeline = IndexPipeline(
            metadataDAO: MetadataDAO(database: database),
            exifService: ExifService(trafficMonitor: indexTraffic)
        )
        self.database = database
        self.metadataDAO = metadataDAO
        self.libraryQueryDAO = LibraryQueryDAO(database: database)
        self.statsDAO = StatsDAO(database: database)
        self.photoLibrary = photoLibrary
        self.indexPipeline = indexPipeline
        self.backgroundIndex = BackgroundIndexService(pipeline: indexPipeline, metadataDAO: metadataDAO)
        self.networkStatus = NetworkStatusService()
        self.indexTraffic = indexTraffic
    }

    /// Re-resolves cameras indexed as Unknown against the bundled sensor
    /// database — an app update that ships new records fixes already-indexed
    /// photos without a reindex. Cheap: touches only still-unknown models.
    func resolveNewlyKnownCameras() {
        let dao = metadataDAO
        Task.detached(priority: .utility) {
            guard let records = try? SensorDatabaseService().loadRecords() else { return }
            let mappings = (try? dao.customMappings()) ?? []
            try? dao.resolveUnknownCameras(using: SensorLookup(records: records, customMappings: mappings))
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
