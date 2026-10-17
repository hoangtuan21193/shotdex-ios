import Foundation

/// Which of a card's photos are new (FS-20 §5): a photo is **imported** when
/// the history has its file — same name, bytes and date — and the copy it
/// made is still in the destination. The background hash then corrects the
/// two cases the name can't tell (AC-22).
enum IngestStatus {
    struct Key: Hashable, Sendable {
        let name: String
        let bytes: Int64
        /// Seconds; the file's date on the card (plan K6).
        let capturedAt: Int64

        init(name: String, bytes: Int64, capturedAt: Int64) {
            self.name = name
            self.bytes = bytes
            self.capturedAt = capturedAt
        }

        init(_ file: CardFile) {
            self.init(name: file.name, bytes: file.size, capturedAt: Int64((file.modified ?? .distantPast).timeIntervalSince1970))
        }
    }

    struct Match: Sendable, Equatable {
        let sha256: String
        /// Deleted from the destination, or its source removed.
        let isCopyGone: Bool
    }

    /// What the background hash found for one card file.
    struct Hashed: Sendable, Equatable {
        let sha256: String
        /// The same content is already a photo in a folder source.
        let isInASource: Bool
    }

    /// The photo's primary file decides: history says imported and the copy
    /// is there → imported; a full hash that disagrees with the history makes
    /// it new again; a hash already in a source makes it imported though the
    /// history has no row (AC-22).
    static func isImported(_ item: CardItem, matches: [Key: Match], hashed: [String: Hashed] = [:]) -> Bool {
        let file = item.primary
        let hash = hashed[file.path]
        if let match = matches[Key(file)], !match.isCopyGone {
            if let hash, hash.sha256 != match.sha256 { return false }
            return true
        }
        return hash?.isInASource ?? false
    }

    /// One day of the grid (FS-20 §5): its photos, oldest first, and whether
    /// every one is imported — then it is a single collapsed row.
    struct Day: Sendable, Equatable, Identifiable {
        let date: Date
        let items: [CardItem]
        let importedIds: Set<String>

        var id: Date { date }
        var importedCount: Int { items.count { importedIds.contains($0.id) } }
        var newCount: Int { items.count - importedCount }
        var isFullyImported: Bool { newCount == 0 }
    }

    static func days(_ items: [CardItem], imported: Set<String>, calendar: Calendar = .current) -> [Day] {
        var order: [Date] = []
        var byDay: [Date: [CardItem]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.date ?? .distantPast)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(item)
        }
        return order.sorted().map { Day(date: $0, items: byDay[$0] ?? [], importedIds: imported.intersection((byDay[$0] ?? []).map(\.id))) }
    }
}

/// What is ticked on the Import from Card grid (FS-20 §5): new photos start
/// ticked, imported ones can't be; the count and size follow every file of
/// a ticked tile (AC-2).
struct IngestSelection: Sendable, Equatable {
    private(set) var checked: Set<String>
    let imported: Set<String>

    init(items: [CardItem], imported: Set<String>) {
        self.imported = imported
        checked = Set(items.map(\.id)).subtracting(imported)
    }

    mutating func toggle(_ id: String) {
        guard !imported.contains(id) else { return }
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }

    mutating func checkAll(_ items: [CardItem]) { checked = Set(items.map(\.id)).subtracting(imported) }
    mutating func uncheckAll() { checked = [] }

    func bytes(_ items: [CardItem]) -> Int64 {
        items.filter { checked.contains($0.id) }.reduce(0) { $0 + $1.byteCount }
    }
}
