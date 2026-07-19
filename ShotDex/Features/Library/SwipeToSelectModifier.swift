import SwiftUI

/// Shared constants for the swipe-to-select gesture.
enum SwipeToSelect {
    /// Named coordinate space that must be set on the ScrollView hosting
    /// the grid, so tile frames and drag locations line up while scrolling.
    static let coordinateSpaceName = "swipeSelect"
}

/// Events emitted while a swipe-select drag runs. `changed` carries the
/// asset ids of the full grid-order range from the drag's start tile to the
/// tile currently under the finger, recomputed each move — the screen
/// applies it on top of a baseline snapshot captured at `began`, so
/// backtracking un-does.
enum SwipeSelectEvent {
    case began
    case changed(rangeIds: [String], select: Bool)
    case ended
}

/// Collects visible tile frames, keyed by asset id, in the named space.
private struct SwipeSelectFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this tile's frame for swipe-select hit-testing. Attach to
    /// the tile wrapper in the grid's ForEach (not inside PhotoGridTile).
    /// Reports nothing when disabled, so browsing pays zero layout cost.
    func swipeSelectFrame(id: String, enabled: Bool) -> some View {
        background {
            if enabled {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SwipeSelectFrameKey.self,
                        value: [id: geometry.frame(in: .named(SwipeToSelect.coordinateSpaceName))]
                    )
                }
            }
        }
    }

    /// iOS-Photos-style swipe selection on a photo grid. Attach to the grid
    /// container. A drag that starts mostly horizontal selects (or deselects,
    /// when starting on a selected tile) the grid-order range it covers;
    /// mostly-vertical drags are left to the ScrollView. `isDragActive`
    /// should drive `.scrollDisabled` on the hosting ScrollView.
    func swipeToSelect(
        isEnabled: Bool,
        orderedItems: [some PhotoGridDisplayable],
        isSelected: @escaping (String) -> Bool,
        isDragActive: Binding<Bool>,
        onEvent: @escaping (SwipeSelectEvent) -> Void
    ) -> some View {
        modifier(SwipeToSelectModifier(
            isEnabled: isEnabled,
            orderedItems: orderedItems,
            isSelected: isSelected,
            isDragActive: isDragActive,
            onEvent: onEvent
        ))
    }
}

private struct SwipeToSelectModifier<Item: PhotoGridDisplayable>: ViewModifier {
    let isEnabled: Bool
    let orderedItems: [Item]
    let isSelected: (String) -> Bool
    @Binding var isDragActive: Bool
    let onEvent: (SwipeSelectEvent) -> Void

    /// One drag's lifecycle: direction lock first, then range tracking.
    private enum Phase {
        case idle
        case undecided
        case active(startId: String, select: Bool, lastId: String)
        /// Vertical drag or start outside any tile — ignore until touch up.
        case rejected
    }

    @State private var tileFrames: [String: CGRect] = [:]
    @State private var phase: Phase = .idle
    /// Grid-order ids snapshotted once at drag start — mapping the whole
    /// item array per finger move would be O(n) at library scale.
    @State private var dragOrderedIds: [String] = []

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(SwipeSelectFrameKey.self) { tileFrames = $0 }
            .simultaneousGesture(drag, including: isEnabled ? .all : .subviews)
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { reset() }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(SwipeToSelect.coordinateSpaceName))
            .onChanged(handleChanged)
            .onEnded { _ in finish() }
    }

    private func handleChanged(_ value: DragGesture.Value) {
        switch phase {
        case .rejected:
            return

        case .idle, .undecided:
            switch SwipeSelectionEngine.activation(translation: value.translation) {
            case .undecided:
                phase = .undecided
            case .scroll:
                phase = .rejected
            case .select:
                guard let startId = SwipeSelectionEngine.tileId(
                    at: value.startLocation, frames: tileFrames
                ) else {
                    phase = .rejected
                    return
                }
                let select = !isSelected(startId)
                phase = .active(startId: startId, select: select, lastId: startId)
                isDragActive = true
                dragOrderedIds = orderedItems.map(\.assetId)
                onEvent(.began)
                emitRange(startId: startId, currentId: startId, select: select)
            }

        case .active(let startId, let select, let lastId):
            // In a gap between tiles: keep the last hit tile as the range end.
            guard let currentId = SwipeSelectionEngine.tileId(
                at: value.location, frames: tileFrames
            ), currentId != lastId else { return }
            phase = .active(startId: startId, select: select, lastId: currentId)
            emitRange(startId: startId, currentId: currentId, select: select)
        }
    }

    private func emitRange(startId: String, currentId: String, select: Bool) {
        let ids = SwipeSelectionEngine.rangeIds(
            orderedIds: dragOrderedIds,
            startId: startId,
            currentId: currentId
        )
        onEvent(.changed(rangeIds: ids, select: select))
    }

    private func finish() {
        if case .active = phase {
            onEvent(.ended)
        }
        reset()
    }

    private func reset() {
        phase = .idle
        isDragActive = false
        dragOrderedIds = []
    }
}
