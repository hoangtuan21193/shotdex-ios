import Foundation

/// One frame of a burst as the frame picker sees it (FS-02.05 §2): its id,
/// and what Photos says about it — read only; the app cannot write either.
struct BurstFrame: Equatable, Sendable, Identifiable {
    let id: String
    /// Photos suggested this frame (`PHAssetBurstSelectionType.autoPick`).
    var isSuggested: Bool
    /// The user chose this frame in Photos (`.userPick`).
    var isPickedInPhotos: Bool
}

/// The frame picker's state (FS-02.05 §4): frames in capture order, which
/// are kept, which one is on the big frame. Pure; the model holds one.
///
/// Kept is the opposite of Compare's tap: here a tap keeps a frame, and
/// Delete N counts the frames **not** kept. Nothing is kept on open — the
/// app never picks for the user, the same rule as Duplicates.
struct BurstSelection: Equatable, Sendable {
    private(set) var frames: [BurstFrame]
    private(set) var keptIds: Set<String> = []
    private(set) var currentIndex = 0

    init(frames: [BurstFrame]) {
        self.frames = frames
    }

    var count: Int { frames.count }
    var current: BurstFrame? { frames.indices.contains(currentIndex) ? frames[currentIndex] : nil }
    var hasSuggestions: Bool { frames.contains(where: \.isSuggested) }

    func isKept(_ id: String) -> Bool { keptIds.contains(id) }

    /// The frames Delete N sends, in capture order.
    var deleteIds: [String] { frames.map(\.id).filter { !keptIds.contains($0) } }

    /// At least one frame kept and at least one to go (§4): the whole burst
    /// is deleted from the viewer, never from here.
    var canDelete: Bool { !keptIds.isEmpty && !deleteIds.isEmpty }

    // MARK: Moving

    mutating func show(_ index: Int) {
        guard frames.indices.contains(index) else { return }
        currentIndex = index
    }

    mutating func show(id: String) {
        if let index = frames.firstIndex(where: { $0.id == id }) { currentIndex = index }
    }

    // MARK: Keeping

    /// A tap on the big frame: keep it, or take the keep back.
    mutating func toggleKeepCurrent() {
        guard let id = current?.id else { return }
        if keptIds.contains(id) { keptIds.remove(id) } else { keptIds.insert(id) }
    }

    /// Keep Only Suggested: exactly the frames Photos suggested.
    mutating func keepOnlySuggested() {
        guard hasSuggestions else { return }
        keptIds = Set(frames.filter(\.isSuggested).map(\.id))
    }

    /// Keep Only This, from the big frame's menu.
    mutating func keepOnly(_ id: String) {
        guard frames.contains(where: { $0.id == id }) else { return }
        keptIds = [id]
    }

    /// After a delete: the frames that went leave, the kept ones stay kept.
    mutating func remove(_ gone: Set<String>) {
        let currentId = current?.id
        frames.removeAll { gone.contains($0.id) }
        keptIds.subtract(gone)
        if let currentId, let index = frames.firstIndex(where: { $0.id == currentId }) {
            currentIndex = index
        } else {
            currentIndex = min(currentIndex, max(0, frames.count - 1))
        }
    }

    // MARK: Words

    /// `Frame 3 of 24`.
    var title: String {
        String(
            localized: "Frame \(currentIndex + 1) of \(count)",
            comment: "Burst frame picker: which frame is on the big frame"
        )
    }

    /// `Delete 22 Photos`, or `Delete` while nothing can go.
    var deleteTitle: String {
        let count = deleteIds.count
        guard canDelete else {
            return String(localized: "Delete", comment: "Burst frame picker: the delete button while no frame is kept")
        }
        return String(localized: "Delete \(count) Photos", table: MarkCopy.table,
                      comment: "Compare: deletes every Rejected photo in the comparison (plural)")
    }

    /// The line under the delete button.
    var deleteFootnote: String {
        keptIds.isEmpty
            ? String(
                localized: "Keep at least one frame. To delete the whole burst, use Delete in the viewer.",
                comment: "Burst frame picker: why Delete is off with no frame kept"
            )
            : String(localized: "Photos move to Recently Deleted.", comment: "Burst frame picker: where deleted frames go")
    }

    /// `Frame 3 of 24, Suggested, kept` (§7).
    func accessibilityLabel(at index: Int) -> String {
        guard frames.indices.contains(index) else { return "" }
        let frame = frames[index]
        var parts = [String(localized: "Frame \(index + 1) of \(count)", comment: "Burst frame picker: which frame is on the big frame")]
        if frame.isSuggested { parts.append(Self.suggestedTitle) }
        if frame.isPickedInPhotos { parts.append(Self.pickedInPhotosTitle) }
        parts.append(keptIds.contains(frame.id)
            ? String(localized: "kept", comment: "VoiceOver: a burst frame chosen to keep")
            : String(localized: "not kept", comment: "VoiceOver: a burst frame not chosen to keep"))
        return parts.joined(separator: ", ")
    }

    static var suggestedTitle: String {
        String(localized: "Suggested", comment: "Burst frame picker: label on a frame Photos suggested")
    }

    static var pickedInPhotosTitle: String {
        String(localized: "Picked in Photos", comment: "Burst frame picker: label on a frame the user chose in Photos")
    }
}

/// One row of the Bursts tab (FS-06.06 §7b): the burst, its cover, when it
/// was shot. Frame and suggestion counts come in when the row shows (NF-01
/// rule 1), so they are optional until then.
struct BurstSummary: Equatable, Sendable, Identifiable {
    /// The burst identifier PhotoKit groups the frames by.
    let id: String
    /// The representative frame, for the cover and the viewer.
    let coverId: String
    let date: Date?
    var frameCount: Int?
    var suggestedCount: Int?

    /// `24 frames`.
    var framesTitle: String? {
        frameCount.map { String(localized: "\($0) frames", table: "Bursts", comment: "Bursts tab: how many frames a burst has") }
    }

    /// `2 suggested by Photos` / `No suggestion`.
    var suggestionTitle: String? {
        guard let suggestedCount else { return nil }
        return suggestedCount == 0
            ? String(localized: "No suggestion", comment: "Bursts tab: Photos suggested no frame of this burst")
            : String(localized: "\(suggestedCount) suggested by Photos", table: "Bursts", comment: "Bursts tab: frames Photos suggested")
    }

    /// Newest first; a burst with no date sorts last.
    static func sorted(_ bursts: [BurstSummary]) -> [BurstSummary] {
        bursts.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Whether the row stays: a burst the app sees fewer than two frames of
    /// is not a burst any more — after a delete, or under `.limited`.
    var isListed: Bool { (frameCount ?? 2) >= 2 }

    /// `3 bursts`.
    static func countTitle(_ count: Int) -> String {
        String(localized: "\(count) bursts", table: "Bursts", comment: "Bursts tab: the summary line, how many bursts")
    }
}
