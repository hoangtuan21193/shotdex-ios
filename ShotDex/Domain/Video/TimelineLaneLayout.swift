import Foundation

/// Assigns timeline items to stacked lanes so overlapping windows never draw on
/// top of each other. Used for the overlay lanes above the video track and the
/// music lanes below it; both feed the same greedy interval partitioning.
enum TimelineLaneLayout {
    struct Item: Equatable, Sendable {
        var id: UUID
        var start: Double
        var end: Double

        /// Reserved for a future "drag an item to another lane" gesture: when
        /// set, the assignment would honour it instead of packing greedily.
        /// Unused in v1 — the layout is derived purely from the time windows.
        var preferredLane: Int?

        init(id: UUID, start: Double, end: Double, preferredLane: Int? = nil) {
            self.id = id
            self.start = start
            self.end = end
            self.preferredLane = preferredLane
        }
    }

    /// Greedy interval partitioning. Items are sorted by (start, end, id) so the
    /// result depends only on the item set, never on the input order — a lane
    /// stays put unless a window actually moves. Each item takes the lowest lane
    /// whose current occupant ends at or before its start; touching windows
    /// (`end == start`) therefore share a lane.
    static func assignLanes(_ items: [Item], epsilon: Double = 0.0005) -> [UUID: Int] {
        let ordered = items.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var laneEnds: [Double] = []
        var assignment: [UUID: Int] = [:]
        for item in ordered {
            let end = max(item.start, item.end)
            if let lane = laneEnds.firstIndex(where: { $0 <= item.start + epsilon }) {
                laneEnds[lane] = end
                assignment[item.id] = lane
            } else {
                assignment[item.id] = laneEnds.count
                laneEnds.append(end)
            }
        }
        return assignment
    }

    /// Number of lanes an assignment occupies. Zero for an empty assignment —
    /// callers that always draw a lane clamp this to 1 themselves.
    static func laneCount(for assignment: [UUID: Int]) -> Int {
        guard let highest = assignment.values.max() else { return 0 }
        return highest + 1
    }
}
