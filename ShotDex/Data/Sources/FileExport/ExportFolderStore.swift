import Foundation
import Observation

/// A folder Export… wrote to (FS-03.07b §4): a security-scoped bookmark and
/// what the row says about it.
struct ExportFolder: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var bookmark: Data
    /// The folder's own name: `Exports`.
    var name: String
    /// Where it is: `T7`, `iCloud Drive`, `On My iPhone`.
    var place: String
    /// The path it resolved to last, to tell two picks of one folder apart.
    var path: String
    /// Set for a drive on the cable: unplugged is *Not connected*, not gone.
    var isOnExternalDrive = false
    var volumeUUID: String?

    /// `T7 › Exports`.
    var title: String { place.isEmpty ? name : "\(place) › \(name)" }
}

/// What a remembered folder is right now.
enum ExportFolderState: Equatable, Sendable {
    case available(URL)
    /// Its drive is unplugged: dimmed, kept, no new pick needed later.
    case notConnected
    /// Deleted, or its drive formatted: dropped from the recents.
    case gone
}

/// The folders Export… remembers: the one in use first, at most five
/// (FS-03.07b §4, §9). In the app's settings, never the database.
@MainActor
@Observable
final class ExportFolderStore {
    static let recentLimit = 5

    private(set) var recents: [ExportFolder] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: SettingsKeys.fileExportFolders),
           let decoded = try? JSONDecoder().decode([ExportFolder].self, from: data) {
            recents = decoded
        }
    }

    var current: ExportFolder? { recents.first }

    /// A folder from the system picker: bookmarked and put first. Picking
    /// one already in the list moves it up rather than adding it twice.
    @discardableResult
    func remember(_ url: URL) throws -> ExportFolder {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        let folder = try Self.folder(for: url)
        recents.removeAll { $0.path == folder.path }
        recents.insert(folder, at: 0)
        if recents.count > Self.recentLimit { recents.removeLast(recents.count - Self.recentLimit) }
        persist()
        return folder
    }

    /// Makes `folder` the one in use.
    func use(_ folder: ExportFolder) {
        guard let index = recents.firstIndex(where: { $0.id == folder.id }) else { return }
        recents.insert(recents.remove(at: index), at: 0)
        persist()
    }

    /// Opens a remembered folder. A bookmark the system calls stale is made
    /// again now that it opened; one that will not open is *Not connected*
    /// when it lives on a drive, and gone — dropped — otherwise.
    func resolve(_ folder: ExportFolder) -> ExportFolderState {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, bookmarkDataIsStale: &isStale) else {
            return unreachable(folder)
        }
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        guard (try? url.checkResourceIsReachable()) == true else { return unreachable(folder) }
        if isStale, let renewed = try? url.bookmarkData(),
           let index = recents.firstIndex(where: { $0.id == folder.id }) {
            recents[index].bookmark = renewed
            recents[index].path = url.standardizedFileURL.path
            persist()
        }
        return .available(url)
    }

    private func unreachable(_ folder: ExportFolder) -> ExportFolderState {
        if folder.isOnExternalDrive { return .notConnected }
        forget(folder)
        return .gone
    }

    func forget(_ folder: ExportFolder) {
        recents.removeAll { $0.id == folder.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        defaults.set(data, forKey: SettingsKeys.fileExportFolders)
    }

    /// The row's words for a picked URL: a drive by its volume name, a
    /// provider by its service, as the cloud folders name them (FS-17.05).
    static func folder(for url: URL) throws -> ExportFolder {
        let bookmark = try url.bookmarkData()
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeUUIDStringKey, .volumeIsInternalKey, .volumeIsRemovableKey]
        let values = try? url.resourceValues(forKeys: keys)
        let isExternal = values?.volumeIsInternal == false || values?.volumeIsRemovable == true
        let place = isExternal ? (values?.volumeName ?? FilesFolderClient.describe(url).service) : FilesFolderClient.describe(url).service
        return ExportFolder(
            bookmark: bookmark,
            name: url.lastPathComponent,
            place: place,
            path: url.standardizedFileURL.path,
            isOnExternalDrive: isExternal,
            volumeUUID: values?.volumeUUIDString
        )
    }
}
