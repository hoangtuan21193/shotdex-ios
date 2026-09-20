import Foundation

/// An album a widget was pointed at from the Home Screen, waiting for the app
/// to render its photos.
///
/// The widget cannot read the photo library, so choosing an album in "Edit
/// Widget" cannot produce a picture by itself. The widget writes the ask here
/// and says so on screen; the app fills it the next time it is opened and
/// reloads the timeline. This is the one file the widget writes and the app
/// reads, the opposite direction from every other payload.
struct PhotoWidgetFrameRequest: Codable, Equatable, Identifiable {
    var albumId: String
    var title: String
    var requestedAt: Date

    var id: String { albumId }
}

struct PhotoWidgetFrameRequests: Codable, Equatable {
    var requests: [PhotoWidgetFrameRequest]

    static let fileName = "photo-widget-requests.json"
    /// How many albums are kept waiting. Beyond this the oldest ask is
    /// dropped: a user with six widgets pointed at six albums is served, and a
    /// stale ask from a widget that was deleted months ago is not.
    static let maximum = 8

    static let empty = PhotoWidgetFrameRequests(requests: [])

    static func read() -> PhotoWidgetFrameRequests {
        guard let url = WidgetSharedContainer.url?.appendingPathComponent(fileName)
        else { return .empty }
        return WidgetSharedContainer.decode(PhotoWidgetFrameRequests.self, at: url) ?? .empty
    }

    func write() {
        guard let url = WidgetSharedContainer.url?.appendingPathComponent(Self.fileName)
        else { return }
        try? WidgetSharedContainer.encode(self, to: url)
    }

    /// Adds an ask, newest first, without repeating one already queued. Pure,
    /// so the queue's rules are a test rather than something observed on a
    /// Home Screen.
    static func merged(
        _ existing: [PhotoWidgetFrameRequest],
        adding request: PhotoWidgetFrameRequest,
        limit: Int = maximum
    ) -> [PhotoWidgetFrameRequest] {
        var merged = existing.filter { $0.albumId != request.albumId }
        merged.insert(request, at: 0)
        return Array(merged.prefix(max(1, limit)))
    }

    /// Records that a widget wants this album's photos. Called from the widget
    /// process, so it reads and writes the file in one go rather than holding
    /// state.
    static func request(albumId: String, title: String, now: Date = .now) {
        let existing = read().requests
        let request = PhotoWidgetFrameRequest(albumId: albumId, title: title, requestedAt: now)
        guard existing.first(where: { $0.albumId == albumId }) == nil else { return }
        PhotoWidgetFrameRequests(requests: merged(existing, adding: request)).write()
    }

    static func clear(albumIds: Set<String>) {
        let remaining = read().requests.filter { !albumIds.contains($0.albumId) }
        PhotoWidgetFrameRequests(requests: remaining).write()
    }
}
