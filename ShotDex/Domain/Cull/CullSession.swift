import Foundation

/// One culling pass over a set of photos (FS-01.12b §2): their order, where
/// the pass stands, and how to undo it. Pure — the marks themselves are
/// written by `PhotoMarks`; this only decides what the screen does next.
struct CullSession: Equatable, Sendable {
    /// One photo as the pass needs it: identity and capture date.
    struct Item: Equatable, Sendable {
        let id: String
        let captureDate: Date?
    }

    /// What setting a mark did to the pass.
    enum Advance: Equatable, Sendable {
        /// A star: stay on this photo.
        case stay
        /// A flag on any photo but the last: on to the next.
        case next
        /// A flag on the last photo: the summary card.
        case summary
    }

    /// Ids in capture order, oldest first.
    let ids: [String]
    private(set) var index: Int
    /// Each mark the pass set, newest last, with the photo it was set on.
    private(set) var history: [Step] = []

    struct Step: Equatable, Sendable {
        let index: Int
        let change: MarkChange
    }

    /// Capture order, oldest first — a shoot is reviewed the way it
    /// happened. Ties by id so the order is total; photos with no date last
    /// (FS-01.05 §1).
    static func ordered(_ items: [Item]) -> [String] {
        items.sorted { lhs, rhs in
            switch (lhs.captureDate, rhs.captureDate) {
            case let (l?, r?): l == r ? lhs.id < rhs.id : l < r
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.id < rhs.id
            }
        }.map(\.id)
    }

    /// A pass over `items`, opened at `startId` when given (Cull From Here),
    /// else at the first photo without a flag — or the first photo when
    /// every one has one (FS-01.12b §2, AC-3).
    static func start(items: [Item], flagged: (String) -> Bool, startId: String? = nil) -> CullSession {
        let ids = ordered(items)
        let index = startId.flatMap { ids.firstIndex(of: $0) }
            ?? ids.firstIndex { !flagged($0) }
            ?? 0
        return CullSession(ids: ids, index: index)
    }

    private init(ids: [String], index: Int) {
        self.ids = ids
        self.index = index
    }

    var currentId: String? { ids.indices.contains(index) ? ids[index] : nil }
    var isLast: Bool { index == ids.count - 1 }

    /// `37 / 240`.
    var counter: String { "\(index + 1) / \(ids.count)" }

    mutating func move(to newIndex: Int) {
        guard ids.indices.contains(newIndex) else { return }
        index = newIndex
    }

    mutating func next() { move(to: index + 1) }
    mutating func previous() { move(to: index - 1) }

    /// Records a flag set on the current photo and moves on: the first pass
    /// is P/X through the whole shoot (FS-01.12b §5).
    mutating func didSetFlag(_ change: MarkChange) -> Advance {
        history.append(Step(index: index, change: change))
        if isLast { return .summary }
        index += 1
        return .next
    }

    /// Records stars set on the current photo, and stays: the second pass
    /// rates the keepers one by one.
    mutating func didSetRating(_ change: MarkChange) -> Advance {
        history.append(Step(index: index, change: change))
        return .stay
    }

    /// The last mark to take back, and the photo it was on — the screen
    /// goes back there (AC-1). Nil when the pass has set nothing.
    mutating func undo() -> MarkChange? {
        guard let step = history.popLast() else { return nil }
        index = step.index
        return step.change
    }

    var canUndo: Bool { !history.isEmpty }
}
