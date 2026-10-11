import Foundation

/// How the viewer shows its photos (FS-01.08c §2). Single is the pager; the
/// other two are Compare. On a compact window 2-Up is drawn stacked — Select
/// above, Candidate below — and called Compare.
enum ViewerMode: String, CaseIterable, Sendable {
    case single
    case twoUp
    case survey

    /// The modes the segmented control offers in a window of this class.
    ///
    /// A compact window (iPhone, the Duo's cover) offers Single · Compare,
    /// and only in a viewer that was opened as a comparison: a viewer opened
    /// from one photo there has no way into Compare (§7, planboard Q4). A
    /// wide window offers all three from any viewer.
    static func available(for windowClass: VideoStudioWindowClass, isComparing: Bool) -> [ViewerMode] {
        if windowClass.isCompact {
            return isComparing ? [.single, .twoUp] : []
        }
        return [.single, .twoUp, .survey]
    }

    /// The segment's title. 2-Up is "Compare" where it is drawn stacked.
    func title(isCompact: Bool) -> String {
        switch self {
        case .single:
            String(localized: "Single", comment: "Viewer mode segment: one photo at a time")
        case .twoUp:
            isCompact
                ? String(localized: "Compare", comment: "Viewer mode segment on iPhone: two photos stacked")
                : String(localized: "2-Up", comment: "Viewer mode segment: two photos side by side")
        case .survey:
            String(localized: "Survey", comment: "Viewer mode segment: every compared photo at once")
        }
    }
}

/// The photos being compared and who plays which part (FS-01.08c §3–§7).
/// Pure: the model holds one and the view draws it.
///
/// **Select** is the reference frame; **Candidate** is one of the others,
/// stepped through one at a time in 2-Up. The **working frame** is the one
/// a key or a flag button acts on — set by a tap, ringed in amber. None of
/// this touches a flag: flags live in `PhotoMarks`.
struct CompareSession: Equatable, Sendable {
    /// Compare needs two photos to mean anything. There is no upper bound.
    static let minimumCount = 2

    /// Every photo in the comparison, in the order it was chosen.
    private(set) var ids: [String]
    private(set) var selectId: String
    /// Position in `candidates` of the Candidate frame.
    private(set) var candidateIndex: Int
    private(set) var workingId: String
    var mode: ViewerMode

    /// From a selection, in selection order: the first photo chosen is Select.
    /// Nil below two distinct photos.
    init?(selection: [String], mode: ViewerMode = .twoUp) {
        var seen = Set<String>()
        let unique = selection.filter { seen.insert($0).inserted }
        guard unique.count >= Self.minimumCount, let first = unique.first else { return nil }
        ids = unique
        selectId = first
        candidateIndex = 0
        workingId = first
        self.mode = mode
    }

    /// From the photo on screen in a wide window's Single viewer: Select is
    /// that photo, Candidate the next cell of the grid — or the one before
    /// it when it is the last (§7). Nil when it has no neighbour.
    init?(viewing: String, next: String?, previous: String?, mode: ViewerMode = .twoUp) {
        guard let other = next ?? previous, other != viewing else { return nil }
        self.init(selection: [viewing, other], mode: mode)
    }

    var count: Int { ids.count }

    /// Everything but Select, in comparison order.
    var candidates: [String] { ids.filter { $0 != selectId } }

    var candidateId: String {
        let all = candidates
        return all[min(candidateIndex, all.count - 1)]
    }

    /// The frames on screen: two in 2-Up, all of them in Survey.
    var visibleIds: [String] {
        mode == .survey ? ids : [selectId, candidateId]
    }

    /// `Candidate 1 of 3`.
    var candidateLabel: String {
        String(
            localized: "Candidate \(candidateIndex + 1) of \(candidates.count)",
            comment: "Compare: the label on the candidate frame and its position among the others"
        )
    }

    /// `4 Photos`.
    var title: String {
        String(localized: "\(count) Photos", table: MarkCopy.table, comment: "Compare: title, how many photos are being compared (plural)")
    }

    // MARK: Moving through the candidates

    /// Steps the Candidate frame; Select stays where it is. Returns false at
    /// either end, where nothing moved.
    @discardableResult
    mutating func nextCandidate() -> Bool { stepCandidate(by: 1) }

    @discardableResult
    mutating func previousCandidate() -> Bool { stepCandidate(by: -1) }

    private mutating func stepCandidate(by delta: Int) -> Bool {
        let target = candidateIndex + delta
        guard candidates.indices.contains(target) else { return false }
        let wasWorking = workingId == candidateId
        candidateIndex = target
        // The working frame is a place on screen as much as a photo: working
        // on the candidate and swiping to the next one keeps working on it.
        if wasWorking { workingId = candidateId }
        return true
    }

    /// Candidate becomes Select and Select takes its place among the
    /// candidates (§3). Flags are not touched.
    mutating func makeSelect(_ id: String? = nil) {
        let newSelect = id ?? candidateId
        guard newSelect != selectId, ids.contains(newSelect) else { return }
        let oldSelect = selectId
        selectId = newSelect
        candidateIndex = candidates.firstIndex(of: oldSelect) ?? 0
    }

    /// A tap on a frame: it becomes the one keys and flag buttons act on.
    mutating func setWorking(_ id: String) {
        guard ids.contains(id) else { return }
        workingId = id
    }

    // MARK: Removing

    /// Whether Remove from Comparison can run: never below two photos.
    var canRemove: Bool { count > Self.minimumCount }

    /// Takes a photo out of the comparison (§4). The photo and its flag are
    /// untouched — it simply stops being compared.
    @discardableResult
    mutating func remove(_ id: String) -> Bool {
        guard canRemove, ids.contains(id) else { return false }
        drop([id])
        return true
    }

    /// Keep Only This (§5): every *other* photo gets Reject, this one loses
    /// a Reject it had; a Pick on it stays. Returns the two id lists for the
    /// flag writer, in comparison order.
    func keepOnly(_ id: String, flag: (String) -> PhotoFlag?) -> (reject: [String], unreject: [String]) {
        let reject = ids.filter { $0 != id && flag($0) != .reject }
        let unreject = flag(id) == .reject ? [id] : []
        return (reject, unreject)
    }

    // MARK: After a deletion

    enum AfterDeletion: Equatable {
        /// Two or more left: stay in the mode in use.
        case stay
        /// One left: back to the Single viewer on it.
        case single(String)
        /// None left: back to the grid.
        case grid
    }

    /// Drops the deleted photos and says where the viewer goes (§6).
    mutating func afterDeletion(gone: Set<String>) -> AfterDeletion {
        let remaining = ids.filter { !gone.contains($0) }
        switch remaining.count {
        case 0:
            return .grid
        case 1:
            return .single(remaining[0])
        default:
            drop(gone)
            return .stay
        }
    }

    /// Removes ids and re-seats Select, Candidate and the working frame on
    /// photos that are still here. Callers keep at least two.
    private mutating func drop(_ gone: some Sequence<String>) {
        let gone = Set(gone)
        let oldCandidate = candidateId
        let oldCandidateIndex = candidateIndex
        ids.removeAll { gone.contains($0) }
        if gone.contains(selectId) { selectId = ids[0] }
        let all = candidates
        if let kept = all.firstIndex(of: oldCandidate) {
            candidateIndex = kept
        } else {
            candidateIndex = min(oldCandidateIndex, all.count - 1)
        }
        if gone.contains(workingId) { workingId = selectId }
    }

    // MARK: Folding

    /// The Duo closing mid-comparison (§2): the cover has no Survey and no
    /// side-by-side, so both become the stacked Compare. From Survey the
    /// working frame becomes Select — it is the photo being looked at.
    mutating func fold() {
        if mode == .survey {
            makeSelect(workingId)
            // The candidate is the photo after the new Select in the order
            // the comparison was built, so the stack reads like the grid.
            if let position = ids.firstIndex(of: selectId) {
                let after = ids[(position + 1) % ids.count]
                candidateIndex = candidates.firstIndex(of: after) ?? 0
            }
        }
        if mode != .single { mode = .twoUp }
    }
}
