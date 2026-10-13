import Foundation
import Photos

extension BackupEnvironment {
    /// The real world: the job's FS-15 connection, Photos or the FS-19 source,
    /// and the device's network, power and free space (FS-22.02).
    static func live(
        database: AppDatabase,
        store: BackupStore,
        servers: FileServerStore,
        roots: FolderSourceRoots
    ) -> BackupEnvironment {
        // Monitors of its own: the shared ones have a single handler slot.
        let network = NetworkMonitor()
        let power = PowerMonitor()
        let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Backup", isDirectory: true)
        return BackupEnvironment(
            makeRunner: { job, retriesExhausted, onProgress in
                guard let server = try? servers.fetch(id: job.connectionId) else { return nil }
                let client = RemoteFileClientFactory.make(for: server, password: servers.password(for: server.id) ?? "")
                let isPhotos = job.sourceId == PhotoLibrarySource.id
                let source: any BackupSourceReading = isPhotos
                    ? PhotoKitBackupSource()
                    : SourceCopyBackupSource(database: database, roots: roots)
                let exporter: any AssetFileExporting = isPhotos
                    ? PhotoKitOriginalExporter()
                    : SourceCopyBackupExporter(database: database, roots: roots, servers: servers, sourceId: job.sourceId)
                let settings = job.settings
                return BackupRunner(
                    job: job,
                    destination: BackupDestination(connectionId: server.id, connectionName: server.name),
                    client: client,
                    store: store,
                    source: source,
                    exporter: exporter,
                    workDirectory: workDirectory,
                    deviceId: BackupDeviceIdentity.current(),
                    retriesExhausted: retriesExhausted,
                    freeBytes: { Self.freeBytes() },
                    gate: { Self.blockingCondition(settings, network: network, power: power) },
                    onProgress: onProgress
                )
            },
            photosChange: { Self.photosChange(since: $0) },
            network: network,
            power: power
        )
    }

    static func blockingCondition(_ settings: BackupSettings, network: NetworkMonitor, power: PowerMonitor) -> BackupJobState.Status? {
        if settings.onlyOnWiFi, network.isExpensivePath { return .waitingForWiFi }
        if settings.onlyWhileCharging, !power.isCharging { return .waitingToCharge }
        return nil
    }

    static func freeBytes() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    /// Whether any asset was added, changed or removed since `archived`. An
    /// unreadable or expired token counts as a change.
    static func photosChange(since archived: Data?) -> (changed: Bool, token: Data?) {
        let library = PHPhotoLibrary.shared()
        let current = try? NSKeyedArchiver.archivedData(withRootObject: library.currentChangeToken, requiringSecureCoding: true)
        guard let archived,
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: archived),
              let changes = try? library.fetchPersistentChanges(since: token) else {
            return (true, current)
        }
        for change in changes {
            guard let details = try? change.changeDetails(for: .asset) else { return (true, current) }
            if !details.insertedLocalIdentifiers.isEmpty || !details.updatedLocalIdentifiers.isEmpty {
                return (true, current)
            }
        }
        return (false, current)
    }
}

extension BackupCoordinator {
    /// Starts the watchers that need the app running: Photos changes, the
    /// 5-minute tick for folder and server sources, and network/power changes.
    func startWatching(photoLibrary: PhotoLibraryService) {
        observeLibrary(photoLibrary)
        environment.network?.setPathChangeHandler { [weak self] _, _ in
            Task { @MainActor in self?.conditionsChanged() }
        }
        environment.power?.setPowerChangeHandler { [weak self] _, _ in
            Task { @MainActor in self?.conditionsChanged() }
        }
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self, !Task.isCancelled else { return }
                self.sourcesTick()
            }
        }
    }

    private func observeLibrary(_ photoLibrary: PhotoLibraryService) {
        withObservationTracking {
            _ = photoLibrary.assetChangeToken
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.photoLibraryDidChange()
                self.observeLibrary(photoLibrary)
            }
        }
    }
}
