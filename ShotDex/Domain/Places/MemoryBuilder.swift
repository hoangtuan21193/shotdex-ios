import Foundation

/// One auto-curated collection offered on the Collections tab.
struct Memory: Identifiable, Hashable {
    enum Kind: Hashable {
        case trip
        case year(Int)
        case place(String)
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let assetIds: [String]
    let coverAssetId: String

    static func == (lhs: Memory, rhs: Memory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Builds memories out of signals the app already has, with no machine
/// learning anywhere.
///
/// Photos assembles its Memories from face recognition, scene classification
/// and a curation model. None of that exists here, and inventing a weak
/// imitation would produce collections the user cannot predict or trust. So a
/// memory here is always something the user could have found themselves: a
/// journey, a year, a place they keep going back to. The title says which.
enum MemoryBuilder {
    /// Most a user can skim on one row before it stops being a highlight.
    static let limit = 8
    /// Below this a "year" or a "place" is not a story, just a handful of
    /// photos that already sit one tap away in the grid.
    static let minimumPhotos = 12

    static func memories(
        from photos: [LocatedPhoto],
        trips: [Trip],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [Memory] {
        var result: [Memory] = []

        // Journeys first: they are the most specific thing the app can know.
        result.append(contentsOf: trips.prefix(3).map { trip in
            Memory(
                id: "trip-\(trip.id)",
                kind: .trip,
                title: trip.title,
                subtitle: trip.dateRangeLabel,
                assetIds: trip.assetIds,
                coverAssetId: trip.coverAssetId
            )
        })

        let tripIds = Set(trips.flatMap(\.assetIds))
        result.append(contentsOf: yearMemories(
            from: photos, excluding: tripIds, calendar: calendar, now: now
        ))
        result.append(contentsOf: placeMemories(from: photos, excluding: tripIds))

        return Array(result.prefix(limit))
    }

    /// One per completed year, newest first — the years the user can look back
    /// on. The current year is skipped: it is not over, so "2026" would keep
    /// changing under the same title.
    private static func yearMemories(
        from photos: [LocatedPhoto],
        excluding excluded: Set<String>,
        calendar: Calendar,
        now: Date
    ) -> [Memory] {
        let currentYear = calendar.component(.year, from: now)
        var byYear: [Int: [LocatedPhoto]] = [:]
        for photo in photos where !excluded.contains(photo.assetId) {
            guard let date = photo.creationDateValue else { continue }
            let year = calendar.component(.year, from: date)
            guard year < currentYear else { continue }
            byYear[year, default: []].append(photo)
        }

        return byYear
            .filter { $0.value.count >= minimumPhotos }
            .sorted { $0.key > $1.key }
            .prefix(3)
            .compactMap { year, members in
                let ordered = members.sorted {
                    ($0.creationDateValue ?? .distantPast) < ($1.creationDateValue ?? .distantPast)
                }
                guard let cover = ordered[ordered.count / 2].assetId as String? else { return nil }
                return Memory(
                    id: "year-\(year)",
                    kind: .year(year),
                    title: String(year),
                    subtitle: "\(ordered.count) photos",
                    assetIds: ordered.map(\.assetId),
                    coverAssetId: cover
                )
            }
    }

    /// The places the user keeps returning to, by photo count.
    private static func placeMemories(
        from photos: [LocatedPhoto],
        excluding excluded: Set<String>
    ) -> [Memory] {
        var byPlace: [String: [LocatedPhoto]] = [:]
        for photo in photos where !excluded.contains(photo.assetId) {
            guard let label = photo.placeLabel else { continue }
            byPlace[label, default: []].append(photo)
        }

        return byPlace
            .filter { $0.value.count >= minimumPhotos }
            .sorted { $0.value.count > $1.value.count }
            .prefix(2)
            .map { label, members in
                let ordered = members.sorted {
                    ($0.creationDateValue ?? .distantPast) > ($1.creationDateValue ?? .distantPast)
                }
                return Memory(
                    id: "place-\(label)",
                    kind: .place(label),
                    title: label,
                    subtitle: "\(ordered.count) photos",
                    assetIds: ordered.map(\.assetId),
                    coverAssetId: ordered[0].assetId
                )
            }
    }
}
