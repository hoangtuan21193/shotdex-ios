import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Publishes the library's *collections* to Spotlight — smart albums, camera
/// bodies, lenses and places — so "Canon EOS R6" typed into Spotlight offers to
/// open those photos.
///
/// Photos themselves are deliberately not indexed. A photo library can hold
/// six figures of items, Spotlight would carry a copy of their metadata outside
/// the app, and the app's promise is that photo metadata never leaves the
/// device's own store. Collections are a few dozen rows and say nothing about
/// any individual photo.
@MainActor
final class SpotlightIndexer {
    /// One domain per kind, so a kind can be re-indexed without disturbing the
    /// others and the whole set can be cleared on demand.
    private enum Domain: String, CaseIterable {
        case smartAlbum = "shotdex.smartAlbum"
        case camera = "shotdex.camera"
        case lens = "shotdex.lens"
    }

    /// Identifier prefix so `continueUserActivity` can tell what was tapped.
    static let identifierPrefix = "shotdex://"

    private let libraryQueries: LibraryQueries
    private let smartAlbumStore: SmartAlbumStore

    init(libraryQueries: LibraryQueries, smartAlbumStore: SmartAlbumStore) {
        self.libraryQueries = libraryQueries
        self.smartAlbumStore = smartAlbumStore
    }

    /// Rebuilds the index. Cheap enough to run on launch: a handful of
    /// `SELECT DISTINCT`s and one write to Spotlight.
    func reindex() async {
        let cameras = (try? libraryQueries.distinctCameraBodies()) ?? []
        let lenses = (try? libraryQueries.distinctLenses()) ?? []
        let albums = (try? smartAlbumStore.fetchAllOrdered()) ?? []

        var items: [CSSearchableItem] = []
        items.append(contentsOf: albums.map {
            item(
                domain: .smartAlbum,
                key: $0.id,
                title: $0.name,
                description: String(localized: "Smart album in ShotDex")
            )
        })
        items.append(contentsOf: cameras.map {
            item(
                domain: .camera,
                key: $0,
                title: $0,
                description: String(localized: "Photos taken with this camera")
            )
        })
        items.append(contentsOf: lenses.map {
            item(
                domain: .lens,
                key: $0,
                title: $0,
                description: String(localized: "Photos taken with this lens")
            )
        })

        let index = CSSearchableIndex.default()
        // Replace wholesale rather than diff: the set is small, and a diff
        // would leave rows behind for gear that has left the library.
        try? await index.deleteSearchableItems(
            withDomainIdentifiers: Domain.allCases.map(\.rawValue)
        )
        guard !items.isEmpty else { return }
        try? await index.indexSearchableItems(items)
    }

    /// Removes everything this app put in Spotlight — used by "Clear local
    /// metadata index" in Settings, so one switch clears both stores.
    func clear() async {
        try? await CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: Domain.allCases.map(\.rawValue)
        )
    }

    /// Turns a tapped Spotlight result back into something the app can open.
    static func request(forSpotlightIdentifier identifier: String) -> IntentRouter.Request? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let body = identifier.dropFirst(identifierPrefix.count)
        guard let separator = body.firstIndex(of: "/") else { return nil }
        let kind = String(body[body.startIndex..<separator])
        let value = String(body[body.index(after: separator)...])
        switch kind {
        case "camera": return .camera(value)
        // A lens or a saved album is best served by the same free-text search
        // the user would have typed, which already resolves both.
        case "lens", "smartAlbum": return .search(value)
        default: return nil
        }
    }

    private func item(
        domain: Domain,
        key: String,
        title: String,
        description: String
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title
        attributes.contentDescription = description
        attributes.keywords = [title, "ShotDex", "photos"]
        let kind = domain.rawValue.replacingOccurrences(of: "shotdex.", with: "")
        return CSSearchableItem(
            uniqueIdentifier: "\(Self.identifierPrefix)\(kind)/\(key)",
            domainIdentifier: domain.rawValue,
            attributeSet: attributes
        )
    }
}
