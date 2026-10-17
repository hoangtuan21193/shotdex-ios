import Foundation

/// Whether Import can start, and the footer that says why not (FS-20 §6,
/// §8): nothing checked, a destination that does not open, a backup drive
/// that is on but not plugged in, or not enough room for the whole batch —
/// checked before the first byte, so nothing is written.
struct IngestReadiness: Sendable, Equatable {
    struct Drive: Sendable, Equatable {
        let name: String
        let isConnected: Bool
        /// Nil when the drive does not say.
        let freeBytes: Int64?
    }

    var checkedCount: Int
    var checkedBytes: Int64
    var destination: Drive?
    /// Nil when backup is off.
    var backup: Drive?

    enum Blocker: Sendable, Equatable {
        case nothingChecked
        case noDestination
        case destinationNotConnected(String)
        case backupNotConnected(String)
        case notEnoughSpace(needed: Int64, free: Int64, drive: String)
    }

    var blocker: Blocker? {
        guard checkedCount > 0 else { return .nothingChecked }
        guard let destination else { return .noDestination }
        guard destination.isConnected else { return .destinationNotConnected(destination.name) }
        if let backup, !backup.isConnected { return .backupNotConnected(backup.name) }
        for drive in [destination, backup].compactMap({ $0 }) {
            if let free = drive.freeBytes, free < checkedBytes {
                return .notEnoughSpace(needed: checkedBytes, free: free, drive: drive.name)
            }
        }
        return nil
    }

    var canImport: Bool { blocker == nil }

    /// The footer under the inspector when Import is dimmed.
    var footer: String? {
        switch blocker {
        case nil, .nothingChecked: nil
        case .noDestination:
            String(localized: "Choose where the photos go.", table: IngestCopy.table, comment: "Card import footer: no destination yet")
        case .destinationNotConnected(let name):
            String(localized: "Connect “\(name)” or choose another destination.", table: IngestCopy.table,
                   comment: "Card import footer: the destination drive is unplugged")
        case .backupNotConnected(let name):
            String(localized: "Connect “\(name)” or turn off backup.", table: IngestCopy.table,
                   comment: "Card import footer: backup is on but its drive is unplugged")
        case .notEnoughSpace(let needed, let free, let drive):
            String(localized: "Needs \(IngestCopy.bytes(needed)), \(IngestCopy.bytes(free)) free on \(drive).", table: IngestCopy.table,
                   comment: "Card import footer: not enough room; bytes needed, bytes free, drive name")
        }
    }
}
