import Foundation
import GRDB
import Observation
import UIKit

/// New Backup and Edit (FS-22.01 §2): what the sheet edits, the choices it
/// offers, and the checks before Start.
@MainActor @Observable
final class BackupFormModel {
    struct SourceOption: Identifiable, Equatable {
        let id: String
        let name: String
        /// photos · folder · drive · server
        let kind: String
        let count: Int
        let isOnline: Bool

        var systemImage: String {
            switch kind {
            case "photos": "photo.on.rectangle"
            case "drive": "externaldrive"
            case "server": "server.rack"
            default: "folder"
            }
        }
    }

    /// The job being edited; nil for New Backup.
    let editing: BackupJob?
    private(set) var sources: [SourceOption] = []
    private(set) var connections: [FileServer] = []

    var sourceId: String?
    var connectionId: String?
    var folder: String = ""
    var settings = BackupSettings()
    /// "This backup already exists." after Start, when it does.
    var duplicateError = false

    private let database: AppDatabase
    private let store: BackupStore
    private let servers: FileServerStore

    init(database: AppDatabase, store: BackupStore, servers: FileServerStore, editing: BackupJob? = nil) {
        self.database = database
        self.store = store
        self.servers = servers
        self.editing = editing
        reloadChoices()
        if let editing {
            sourceId = editing.sourceId
            connectionId = editing.connectionId
            folder = editing.folder
            settings = editing.settings
        } else {
            sourceId = PhotoLibrarySource.id
            connectionId = (try? servers.mostRecentlyUsed())?.id ?? connections.first?.id
            folder = defaultFolder
        }
    }

    func reloadChoices() {
        connections = (try? servers.fetchAll()) ?? []
        let photosCount = (try? database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_metadata WHERE mediaType IN (1, 2)")
        }) ?? 0
        var options = [SourceOption(id: PhotoLibrarySource.id, name: String(localized: "Photos Library", comment: "Backup source: the Photos library"), kind: "photos", count: photosCount, isOnline: true)]
        let counts = (try? SourceStore(database: database).photoCounts()) ?? [:]
        let rows = (try? database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT id, kind, name, status FROM sources WHERE kind != 'photos' ORDER BY createdAt, id")
        }) ?? []
        for row in rows {
            let id: String = row["id"]
            let status: String? = row["status"]
            options.append(SourceOption(id: id, name: row["name"], kind: row["kind"], count: counts[id] ?? 0, isOnline: status != "offline"))
        }
        sources = options
    }

    var isEditing: Bool { editing != nil }
    var connection: FileServer? { connections.first { $0.id == connectionId } }
    var source: SourceOption? { sources.first { $0.id == sourceId } }

    /// Start stays off until source, connection and folder are set.
    var canStart: Bool { sourceId != nil && connection != nil && !folder.trimmingCharacters(in: .whitespaces).isEmpty }

    /// `Backup/iPhone` inside the connection's Folder.
    var defaultFolder: String {
        ServerUploadPath.join(connection?.folder ?? "", "Backup/\(BackupDevice.kindName)")
    }

    func choose(connection id: String) {
        let wasDefault = folder == defaultFolder
        connectionId = id
        if wasDefault || folder.isEmpty { folder = defaultFolder }
    }

    /// `23,904 items · 18,210 not backed up yet · about 412 GB`.
    var summary: String {
        guard let sourceId else { return "" }
        let (count, bytes) = sizeOfSource(sourceId)
        let done = editing.flatMap { try? store.handledItemCount(jobId: $0.id) } ?? 0
        let left = max(0, count - done)
        var parts = [
            String(localized: "\(count.formatted()) items", comment: "New Backup: items in the source"),
            String(localized: "\(left.formatted()) not backed up yet", comment: "New Backup: items the job has still to copy"),
        ]
        if bytes > 0 {
            parts.append(String(localized: "about \(Int64(Double(bytes) * Double(left) / Double(max(count, 1))).formatted(.byteCount(style: .file)))", comment: "New Backup: estimated size still to copy"))
        }
        return parts.joined(separator: " · ")
    }

    private func sizeOfSource(_ id: String) -> (Int, Int64) {
        let media: String = switch settings.content {
        case .photosAndVideos: "1, 2"
        case .photosOnly: "1"
        case .videosOnly: "2"
        }
        return (try? database.reader.read { db -> (Int, Int64) in
            let row: Row?
            if id == PhotoLibrarySource.id {
                row = try Row.fetchOne(db, sql: "SELECT COUNT(*) AS n, COALESCE(SUM(fileSize), 0) AS b FROM photo_metadata WHERE mediaType IN (\(media))")
            } else {
                row = try Row.fetchOne(db, sql: """
                    SELECT COUNT(*) AS n, COALESCE(SUM(c.size), 0) AS b FROM photo_copies c
                    LEFT JOIN photo_metadata m ON m.assetId = c.photoId
                    WHERE c.sourceId = ? AND c.missingSince IS NULL AND COALESCE(m.mediaType, 1) IN (\(media))
                    """, arguments: [id])
            }
            return (row?["n"] ?? 0, row?["b"] ?? 0)
        }) ?? (0, 0)
    }

    /// Saves the job; returns it, or nil when the same backup already exists.
    func save() -> BackupJob? {
        guard let sourceId, let connectionId, canStart else { return nil }
        let folder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if let existing = try? store.existingJob(sourceId: sourceId, connectionId: connectionId, folder: folder),
           existing.id != editing?.id {
            duplicateError = true
            return nil
        }
        if var job = editing {
            job.folder = folder
            job.settings = settings
            try? store.update(job)
            return job
        }
        let job = BackupJob(sourceId: sourceId, connectionId: connectionId, folder: folder, settings: settings)
        do {
            try store.add(job)
        } catch {
            duplicateError = true
            return nil
        }
        return job
    }
}

/// The device's kind as a folder name: `iPhone`, `iPad`.
enum BackupDevice {
    @MainActor static var kindName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}
