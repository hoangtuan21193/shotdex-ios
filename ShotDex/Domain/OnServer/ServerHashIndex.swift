import Foundation

/// The ledger of SHA-256s on the NAS (FS-19.07 §12.2): one per server
/// source, at its root, in the same segment format as Backup's shared index
/// (`BackupContentIndex`) — each device writes only its own segments, so
/// two devices never write one file over SMB or WebDAV, which have no lock.
/// One line is one file, its path under the source's root.
enum ServerHashIndex {
    /// Relative to the source's root.
    static let folder = ".shotdex/hash-index"
}
