import Foundation

/// Whether a photo's original can be opened now (FS-19.01b §1, FS-19.03 §6):
/// a Photos copy or a copy on an online source is enough. Otherwise the
/// viewer shows the saved preview, and Edit, Export, Share and dragging out
/// are dimmed with a line that says which source to bring back.
enum CopyReachability: Equatable, Sendable {
    case available
    case offline(sourceName: String, isServer: Bool)

    var canOpenOriginal: Bool { self == .available }

    /// Under the viewer's photo.
    var viewerNote: String? {
        guard case .offline(let name, let isServer) = self else { return nil }
        return isServer
            ? String(localized: "\(name) isn't reachable. Showing the saved preview.", comment: "Viewer: the server holding this photo is off; the cached preview is shown")
            : String(localized: "Connect \(name) to edit this photo.", comment: "Viewer: the drive holding this photo is unplugged; Edit and Export are dimmed")
    }
}

/// The status line of an offline source row (FS-19.01b §1, FS-19.03 §1).
enum SourceRowStatus {
    static func offlineLabel(isServer: Bool) -> String {
        isServer
            ? String(localized: "Not reachable", comment: "Sources: a server source whose server does not answer")
            : String(localized: "Not connected", comment: "Sources: a drive source that is unplugged")
    }

    static let passwordRejected = String(localized: "Password rejected", comment: "Sources: the server refused the saved password")
}
