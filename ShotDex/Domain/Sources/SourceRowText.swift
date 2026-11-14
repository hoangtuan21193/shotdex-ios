import Foundation

/// The words of one row in Settings › Sources and the Sources group
/// (FS-19.01b §1, boards `PH_SettingsSources`, `PH_Sources`).
struct SourceRowText: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case photos
        case onDevice
        case iCloudDrive
        case drive
        case server(protocolName: String)
    }

    enum Status: Equatable, Sendable {
        case online
        case reading(done: Int, total: Int)
        case offline
        case needsAccess
        case passwordRejected
        /// The server answers, the connection's folder is gone (renamed or
        /// moved on the server).
        case folderMissing
    }

    let kind: Kind
    let status: Status
    let count: Int
    /// Photos access, for the Photos Library row.
    var photosAccess: String? = nil
    /// Photos access is limited, denied or not asked: the Photos row is
    /// grey-dotted like any source not fully there.
    var photosAccessIsFull = true
    var lastReadAt: Date? = nil

    /// The grey capsule after the name.
    var badge: String {
        switch kind {
        case .photos: String(localized: "Photos", comment: "Sources: badge of the Photos library row")
        #if os(macOS)
        case .onDevice: String(localized: "This Mac", comment: "Mac Sources: badge of a folder on this Mac")
        case .drive: String(localized: "External", comment: "Mac Sources: badge of an external drive")
        #else
        case .onDevice: String(localized: "On My iPhone", comment: "Sources: badge of a folder on this device")
        #endif
        case .iCloudDrive: String(localized: "iCloud Drive", comment: "Sources: badge of a folder in iCloud Drive")
        #if !os(macOS)
        case .drive: String(localized: "USB-C Drive", comment: "Sources: badge of an external drive")
        #endif
        case .server: String(localized: "Server", comment: "Sources: badge of a server source")
        }
    }

    /// The line under the name.
    func detail(now: Date = Date()) -> String {
        let items = String(localized: "\(count) items", comment: "Sources: how many photos and videos a source holds")
        switch status {
        case .reading(let done, let total):
            return total > 0
                ? String(localized: "\(done) of \(total) read", comment: "Sources: a read in progress")
                : String(localized: "Reading… \(done) items so far", comment: "Sources: a read in progress, total not known yet")
        case .offline:
            return kind == .drive || kind == .onDevice || kind == .iCloudDrive
                ? String(localized: "Not connected · \(count) photos kept", comment: "Sources: an unplugged drive, its photos stay")
                : String(localized: "Not reachable · \(count) photos kept", comment: "Sources: a server that does not answer")
        case .needsAccess:
            #if os(macOS)
            return String(localized: "ShotDex needs permission to read this folder.", comment: "Mac Sources: a folder whose permission was lost")
            #else
            return String(localized: "Choose the folder again in Files to let ShotDex read it.", comment: "Sources: a folder whose permission was lost")
            #endif
        case .passwordRejected:
            return String(localized: "Password rejected", comment: "Sources: the server refused the saved password")
        case .folderMissing:
            return String(localized: "Folder not found on the server · \(count) photos kept",
                          comment: "Sources: the connection's folder was renamed or moved on the server; its photos stay")
        case .online:
            var parts: [String] = []
            if case .photos = kind, let photosAccess { parts.append(photosAccess) }
            if case .server(let name) = kind { parts.append(name) }
            parts.append(items)
            if let lastReadAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                // The formatter calls zero seconds — and a stamp a fraction
                // ahead of the clock — "in 0 sec."; a read that just ended
                // is a second ago.
                let ago = formatter.localizedString(for: min(lastReadAt, now.addingTimeInterval(-1)), relativeTo: now)
                parts.append(String(localized: "indexed \(ago)", comment: "Sources: when a source was last read, e.g. 'indexed 2 min ago'"))
            }
            return parts.joined(separator: " · ")
        }
    }

    /// Orange for a source the user has to act on.
    var needsAttention: Bool { status == .needsAccess || status == .passwordRejected || status == .folderMissing }

    /// The status dot: reading or there, grey when away or partly there,
    /// orange when the user has to act.
    enum Dot: Equatable, Sendable { case ok, away, attention }

    var dot: Dot {
        if needsAttention { return .attention }
        if status == .offline || (kind == .photos && !photosAccessIsFull) { return .away }
        return .ok
    }

    /// "Offline" capsule in the Sources group.
    var isOffline: Bool { status == .offline }
}
