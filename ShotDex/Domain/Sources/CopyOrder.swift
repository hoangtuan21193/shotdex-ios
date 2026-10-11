import Foundation

/// Which copy of a photo ShotDex opens, edits and — from All Photos —
/// deletes by default (FS-19.02 §3): a file on this device, then Photos
/// with its original on the device, then an external drive, then a server,
/// then iCloud — a Photos item whose original is only there, or a cloud
/// placeholder.
enum CopyOrder {
    struct Candidate: Sendable {
        let copyId: String
        /// `photos` · `file` · `server`
        let kind: String
        /// `photos` · `folder` · `drive` · `server`
        let sourceKind: String
        var isOnline = true
        /// A file not downloaded yet, or a Photos item whose original is
        /// only in iCloud.
        var isCloudPlaceholder = false
    }

    static func rank(_ copy: Candidate) -> Int {
        if copy.isCloudPlaceholder { return 4 }
        let place = switch copy.sourceKind {
        case "folder": 0
        case "photos": 1
        case "drive": 2
        case "server": 3
        default: 5
        }
        // One that cannot be opened now goes behind every one that can.
        return copy.isOnline || copy.kind == "photos" ? place : place + 10
    }

    static func sorted(_ copies: [Candidate]) -> [Candidate] {
        copies.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
}
