#if DEBUG
import CoreGraphics
import Foundation
import ImageIO

/// `-ShotDexDemoLibrary`: the window over an in-memory library of landscape
/// pictures — the macOS desktop pictures — instead of the user's Photos.
/// What screenshots and the board comparison run on: no PhotoKit prompt,
/// the same days and EXIF every time, and never a photo of a person
/// (the user's own library has them; tests and screenshots must not).
enum MacDemoLibrary {
    static let argument = "-ShotDexDemoLibrary"

    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    /// Days as on board `Main`: Monday Sep 28 (48), Sunday Sep 27 (112),
    /// then shorter days back through September.
    static let days: [(month: Int, day: Int, count: Int)] = [(9, 28, 48), (9, 27, 112), (9, 26, 21), (9, 24, 9), (9, 21, 36)]

    @MainActor
    static func dependencies() -> MacDependencies {
        let database = (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        let dependencies = MacDependencies(database: database, photoLibrary: PhotoLibraryService())
        try? dependencies.metadataStore.saveBatch(rows(), cursorAssetId: nil)
        seedBackups(dependencies)
        return dependencies
    }

    /// Two jobs as on board `MAC_Backup`: one up to date, one whose server
    /// is out of reach. Nothing runs in the demo; the states are written.
    @MainActor
    private static func seedBackups(_ dependencies: MacDependencies) {
        let home = FileServer(name: "NAS Home", transferProtocol: .webdav, host: "nas.local", username: "demo")
        let studio = FileServer(name: "Studio SMB", transferProtocol: .smb, host: "studio.local", username: "demo")
        try? dependencies.fileServers.save(home, password: nil)
        try? dependencies.fileServers.save(studio, password: nil)
        var settings = BackupSettings()
        settings.onlyOnWiFi = false
        let first = BackupJob(sourceId: PhotoLibrarySource.id, connectionId: home.id, folder: "Backup/Mac", settings: settings)
        let second = BackupJob(sourceId: PhotoLibrarySource.id, connectionId: studio.id, folder: "Clients/2026", settings: settings, sortOrder: 1)
        try? dependencies.backups.add(first)
        try? dependencies.backups.add(second)
        var watching = BackupJobState(jobId: first.id)
        watching.lastCheckedAt = Int(Date().timeIntervalSince1970) - 120
        watching.hasFinishedFirstRun = true
        var stuck = BackupJobState(jobId: second.id)
        stuck.status = .unreachable
        stuck.statusTotal = 12
        stuck.statusDone = 0
        try? dependencies.backups.save(watching)
        try? dependencies.backups.save(stuck)
        dependencies.backupCoordinator.reload()
    }

    /// `-ShotDexSection backup`: the sidebar place the window opens on.
    static var section: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexSection"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func rows() -> [PhotoMetadata] {
        let lenses: [(camera: String, lens: String, focal: Double, aperture: Double, iso: Int)] = [
            ("ILCE-7M4", "FE 85mm F1.8", 85, 1.8, 400), ("EOS R6m2", "RF35mm F1.8 MACRO IS STM", 35, 1.4, 3200),
            ("X-T5", "XF16mmF2.8 R WR", 16, 11, 125), ("ILCE-7M4", "FE 24mm F1.4 GM", 24, 8, 100),
            ("X-T5", "XF56mmF1.2 R WR", 56, 1.2, 250), ("EOS R6m2", "RF70-200mm F2.8 L IS USM", 135, 1.8, 640),
            ("ILCE-7M4", "FE 50mm F1.2 GM", 50, 2, 800), ("X-T5", "XF23mmF1.4 R LM WR", 23, 2, 1600),
        ]
        let formats = ["HEIC", "RAF", "JPG", "ARW", "HEIC", "CR3", "JPG"]
        var rows: [PhotoMetadata] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for (dayIndex, day) in days.enumerated() {
            let start = calendar.date(from: DateComponents(year: 2026, month: day.month, day: day.day, hour: 18))!
            for n in 0..<day.count {
                let shot = lenses[(n + dayIndex) % lenses.count]
                let id = "demo-\(dayIndex)-\(n)"
                let ext = formats[(n + dayIndex * 3) % formats.count]
                rows.append(PhotoMetadata(
                    assetId: id, creationDate: Int(start.timeIntervalSince1970) - n * 90, modificationDate: nil, mediaType: 1,
                    cameraManufacturer: nil, cameraModel: shot.camera, normalizedCameraModel: shot.camera,
                    normalizedCameraManufacturer: nil, lensManufacturer: nil, lensModel: shot.lens, normalizedLensModel: shot.lens,
                    originalFilename: String(format: "DSC%05d.%@", 4100 + n, ext), iso: shot.iso, aperture: shot.aperture,
                    shutterSpeedSeconds: 1 / 250, shutterSpeedDisplay: "1/250", focalLength: shot.focal, focalLengthIn35mm: nil,
                    calculatedEquivalentFocalLength: nil, equivalentFocalLength: shot.focal, sensorFormat: nil, cropFactor: nil,
                    width: 6000, height: 4000, fileSize: 24_000_000, latitude: nil, longitude: nil, isFavorite: n % 11 == 3,
                    indexedAt: 1, exifStatus: ExifStatus.indexed.rawValue
                ))
            }
        }
        return rows
    }

    /// Landscape desktop pictures, decoded once, cycled over the tiles.
    private static let pictures: [CGImage] = {
        let folder = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails", isDirectory: true)
        let names = ["Big Sur Coastline", "Catalina Rock", "Big Sur Mountains", "Catalina Coast", "Big Sur Waters Edge",
                     "Catalina Evening", "Big Sur Horizon", "Catalina Shoreline", "Big Sur Road", "Catalina Clouds",
                     "Big Sur Shore Rocks", "Catalina Sunset", "Big Sur Aerial", "Catalina Silhouette"]
        return names.compactMap { name in
            let url = folder.appendingPathComponent(name + ".heic")
            return CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
    }()

    static func picture(for assetId: String) -> CGImage? {
        guard !pictures.isEmpty else { return nil }
        let index = abs(assetId.hashValue == 0 ? 0 : Int(assetId.split(separator: "-").last.flatMap { Int($0) } ?? 0))
        let day = Int(assetId.split(separator: "-").dropFirst().first.flatMap { Int($0) } ?? 0)
        return pictures[(index + day * 5) % pictures.count]
    }
}
#endif

#if DEBUG
import os
import ServiceManagement

/// `-ShotDexAgentProbe seed|remove`: a test job for the helper on the real
/// database — Photos → a WebDAV server at 127.0.0.1:1 that is never there,
/// so the helper runs, writes Can't Reach and copies nothing. `remove`
/// deletes it and unregisters the helper.
enum MacAgentProbe {
    static let serverName = "Agent Probe"
    static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "agent")

    static var mode: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexAgentProbe"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func runIfAsked(_ dependencies: MacDependencies) {
        switch mode {
        case "seed":
            let existing = ((try? dependencies.fileServers.fetchAll()) ?? []).first { $0.name == serverName }
            let server = existing ?? FileServer(name: serverName, transferProtocol: .webdav, host: "127.0.0.1", port: 1,
                                                username: "probe", usesTLS: false)
            if existing == nil { try? dependencies.fileServers.save(server, password: nil) }
            var settings = BackupSettings()
            settings.onlyOnWiFi = false
            let job = BackupJob(sourceId: PhotoLibrarySource.id, connectionId: server.id, folder: "Probe", settings: settings)
            if (try? dependencies.backups.existingJob(sourceId: job.sourceId, connectionId: server.id, folder: "Probe")) == nil {
                try? dependencies.backups.add(job)
                dependencies.backupControl.jobsChanged(start: job.id)
            }
            log.notice("probe seeded; agent status \(MacAgentLink.service.status.rawValue)")
        case "remove":
            for server in ((try? dependencies.fileServers.fetchAll()) ?? []) where server.name == serverName {
                for job in ((try? dependencies.backups.jobs()) ?? []) where job.connectionId == server.id {
                    try? dependencies.backups.delete(id: job.id)
                }
                try? dependencies.fileServers.delete(id: server.id)
            }
            dependencies.backupControl.jobsChanged()
            Task {
                try? await MacAgentLink.service.unregister()
                log.notice("probe removed; agent status \(MacAgentLink.service.status.rawValue)")
                exit(0)
            }
        default:
            break
        }
    }
}
#endif
