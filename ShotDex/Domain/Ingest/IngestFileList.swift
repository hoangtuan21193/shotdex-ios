import Foundation

/// A card import's file list (FS-20 §7, board `MAC_IngestProgress`): the
/// last few photos done, the one in hand with its step, and the next few
/// waiting — a window on the batch, never all 811 rows. Fed by the run's
/// events in order; pure, so it is tested without a card.
struct IngestFileList: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let id: String
        /// The primary file's name on the card: `IMG_6293.CR3`.
        let name: String
        let bytes: Int64
        /// Where it lands under the destination (`RAW/2026`), once planned.
        var folder: String?
    }

    enum State: Equatable, Sendable {
        case waiting
        /// Bytes going in, as a share of the photo.
        case copying(Double)
        /// The part file is being read back against the card's SHA-256.
        case verifying
        case verified
        case backingUp
        case backedUp
        case failed
        /// The photo is in and verified; only its backup copy failed.
        case backupFailed
    }

    struct Row: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let bytes: Int64
        let folder: String?
        var state: State
    }

    /// Board `MAC_IngestProgress`: three done, the one in hand, two waiting.
    static let doneShown = 3
    static let waitingShown = 2

    private(set) var order: [Entry] = []
    private var position: [String: Int] = [:]
    /// The last photos finished (done or failed), oldest first.
    private(set) var done: [Row] = []
    private(set) var inHand: Row?
    /// The first photo of `order` not started yet.
    private var cursor = 0
    /// How much of the photo in hand is in, across its files.
    private var inHandShare = 0.0

    init(order: [Entry] = []) {
        self.order = order
        reindex()
    }

    /// The runner's order, known once the plan is made; the names stay.
    mutating func reorder(_ ids: [String], folders: [String: String]) {
        let byId = Dictionary(order.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let started = Set(done.map(\.id) + [inHand?.id].compactMap { $0 })
        var next = ids.compactMap { id -> Entry? in
            guard var entry = byId[id] else { return nil }
            entry.folder = folders[id]
            return entry
        }
        // Photos already under way keep their place in front.
        let front = next.filter { started.contains($0.id) }
        next.removeAll { started.contains($0.id) }
        order = front + next
        reindex()
        cursor = front.count
    }

    var waiting: [Row] {
        order[min(cursor, order.count)..<min(cursor + Self.waitingShown, order.count)]
            .map { Row(id: $0.id, name: $0.name, bytes: $0.bytes, folder: $0.folder, state: .waiting) }
    }

    /// Everything the list shows, top to bottom.
    var rows: [Row] { done + [inHand].compactMap { $0 } + waiting }

    /// Waiting photos beyond the rows shown: "399 more waiting".
    var moreWaiting: Int { max(0, order.count - cursor - waiting.count) }

    /// Where the photo in hand goes, else the next one.
    var folder: String? { inHand?.folder ?? waiting.first?.folder }

    mutating func set(_ id: String, _ stage: IngestFileStage) {
        take(id)
        switch stage {
        case .copying:
            // A second file of a pair goes on from the share the first left.
            inHand?.state = .copying(inHandShare)
        case .verifying: inHand?.state = .verifying
        case .backingUp: inHand?.state = .backingUp
        }
    }

    mutating func copied(_ id: String, fraction: Double) {
        guard inHand?.id == id else { return }
        inHandShare = min(1, max(0, fraction))
        inHand?.state = .copying(inHandShare)
    }

    mutating func verified(_ id: String) {
        take(id)
        inHand?.state = .verified
    }

    mutating func backedUp(_ id: String) {
        take(id)
        inHand?.state = .backedUp
    }

    mutating func failed(_ id: String) {
        take(id)
        let wasBackingUp = inHand?.state == .backingUp
        inHand?.state = wasBackingUp ? .backupFailed : .failed
    }

    /// The runner moved past the photo in hand.
    mutating func finishInHand() {
        guard let row = inHand else { return }
        done.append(row)
        if done.count > Self.doneShown { done.removeFirst(done.count - Self.doneShown) }
        inHand = nil
    }

    /// Makes `id` the photo in hand, finishing the one before.
    private mutating func take(_ id: String) {
        guard inHand?.id != id else { return }
        finishInHand()
        inHandShare = 0
        guard let index = position[id] else {
            inHand = Row(id: id, name: (id as NSString).lastPathComponent, bytes: 0, folder: nil, state: .waiting)
            return
        }
        let entry = order[index]
        inHand = Row(id: entry.id, name: entry.name, bytes: entry.bytes, folder: entry.folder, state: .waiting)
        cursor = max(cursor, index + 1)
    }

    private mutating func reindex() {
        position = Dictionary(order.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }
}
