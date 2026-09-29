import Foundation

/// The waiting room "Add to ShotDex" drops looks into and the app empties on
/// its next launch or return (FS-03.14c §4). One source for both processes,
/// like `WidgetShared/`: the group, the folder, and the ceilings.
enum LookInboxLocation {
    static let appGroupIdentifier = "group.com.hoangtuan.shotdex"
    static let pendingFolderName = "PendingLooks"
    /// Per file, the `.shotdexlook` ceiling of FS-03.14a §2.
    static let maximumFileBytes = 16 * 1024 * 1024
    static let maximumPendingFiles = 50
    static let maximumPendingBytes = 50 * 1024 * 1024

    static func pendingDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(pendingFolderName, isDirectory: true)
    }

    enum Refusal: Equatable {
        case tooLarge(name: String)
        case inboxFull(name: String)

        var message: String {
            switch self {
            case let .tooLarge(name): "\(name) is larger than 16 MB — not a look"
            case let .inboxFull(name): "\(name) wasn't added: 50 looks are already waiting. Open ShotDex first."
            }
        }
    }

    struct Deposit: Equatable {
        var added = 0
        var refused: [Refusal] = []
    }

    /// Copies `files` into `directory`, one folder each, checking every size
    /// the file system reports **before** a byte is read, and the waiting
    /// room's own totals. Nothing is parsed here — the app reads the files.
    static func deposit(_ files: [URL], into directory: URL) -> Deposit {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var (count, bytes) = totals(in: directory)
        var result = Deposit()
        for file in files {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let name = file.lastPathComponent
            guard size <= maximumFileBytes else {
                result.refused.append(.tooLarge(name: name))
                continue
            }
            guard count < maximumPendingFiles, bytes + size <= maximumPendingBytes else {
                result.refused.append(.inboxFull(name: name))
                continue
            }
            let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                try manager.copyItem(at: file, to: folder.appendingPathComponent(name))
                count += 1
                bytes += size
                result.added += 1
            } catch {
                try? manager.removeItem(at: folder)
            }
        }
        return result
    }

    /// Files and bytes already waiting.
    static func totals(in directory: URL) -> (files: Int, bytes: Int) {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var files = 0
        var bytes = 0
        for folder in folders {
            for file in (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
                files += 1
                bytes += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }
        return (files, bytes)
    }
}
