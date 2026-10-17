import Foundation

/// What went wrong in a card import, and how far it reaches (FS-20 §8): a
/// problem with **one file** leaves the batch running; a problem with the
/// **card** or the **destination** stops it — the rule of FS-15.02 §4 and
/// FS-03.07c §3.
enum IngestFailure: Error, Equatable, Sendable, Hashable {
    // One file.
    /// What was written does not read back as what the card holds, twice.
    case checksumMismatch
    /// The card would not give this file up.
    case unreadable

    // The batch.
    /// The card was pulled out, or the camera switched off.
    case cardDisconnected
    /// The destination went away, filled up, or refused.
    case destination(FileExportFailure)

    var stopsBatch: Bool {
        switch self {
        case .checksumMismatch, .unreadable: false
        case .cardDisconnected, .destination: true
        }
    }
}
