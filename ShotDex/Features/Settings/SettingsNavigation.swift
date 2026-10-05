import Foundation
import Observation

/// Where the reader is inside Settings, and where a search result is about to
/// send them.
///
/// One instance per presentation — it is created in the full-screen cover's
/// content, so closing Settings forgets the query and the selected item
/// without a `UserDefaults` key for either. Neither is worth persisting: a
/// search term belongs to the question being asked, and "which item was I on"
/// is answered better by the first item than by whatever was open last week.
@MainActor
@Observable
final class SettingsNavigation {

    /// The sidebar item shown in the detail pane. Only the wide layout reads it.
    var selection: SettingsSection? = .photoLibrary

    /// What the compact layout has pushed. Empty means the root list itself.
    var compactPath: [SettingsDestination] = []

    /// What is typed in the search field. Empty means show the settings, not
    /// results.
    var query: String = ""

    /// Whether the search field holds the screen. Bound rather than left to
    /// SwiftUI so that picking a result can put the keyboard away — a result
    /// that scrolls the list behind a keyboard has answered the question in a
    /// place the reader cannot see.
    var isSearchPresented: Bool = false

    /// The row a search result asked for, waiting for its list to appear.
    private(set) var pendingScrollTarget: SettingsRowLabel?

    /// The row currently lit up so the eye can find it.
    private(set) var flashedRow: SettingsRowLabel?

    @ObservationIgnored private var flashTask: Task<Void, Never>?

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Opens the page holding a result and asks its list to scroll to the row.
    ///
    /// Clearing the query is part of the same move: a result that leaves the
    /// results list on screen has taken the reader somewhere they cannot see.
    /// A page that is a screen of its own (Resize Presets, File Servers,
    /// Support) is the answer itself, so nothing is left waiting to scroll —
    /// a target no list claims would fire on whichever page drew it next.
    func open(_ entry: SettingsSearchEntry, usesSplitView: Bool) {
        let drawsRows: Bool
        if usesSplitView {
            selection = entry.section
            drawsRows = entry.section.drawsRows
        } else {
            let destination = SettingsDestination.containing(entry.label)
            compactPath = [destination]
            drawsRows = destination.drawsRows
        }
        pendingScrollTarget = drawsRows ? entry.label : nil
        query = ""
        isSearchPresented = false
    }

    /// Hands the pending row to whichever list is ready to scroll, once.
    ///
    /// Once, because the detail pane is rebuilt when the selection changes and
    /// would otherwise scroll again every time the reader came back to it.
    func consumeScrollTarget() -> SettingsRowLabel? {
        defer { pendingScrollTarget = nil }
        return pendingScrollTarget
    }

    /// Lights a row up, and puts it out again on its own clock.
    ///
    /// The timer lives here rather than in the view's `task`, because that task
    /// is keyed to `pendingScrollTarget` — consuming the target changes the key
    /// and cancels the very task that would be counting. Measured: the
    /// highlight was over before the next frame.
    func flash(_ label: SettingsRowLabel) {
        flashTask?.cancel()
        flashedRow = label
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: AppTheme.Motion.searchFlashDuration)
            guard !Task.isCancelled, let self, self.flashedRow == label else { return }
            self.flashedRow = nil
        }
    }

    /// Keeps the reader's place when the window crosses the size-class line.
    func layoutChanged(usesSplitView: Bool) {
        if usesSplitView {
            selection = SettingsLayout.selection(afterExpanding: compactPath)
            compactPath = []
        } else {
            compactPath = SettingsLayout.path(afterCollapsing: selection)
        }
    }
}
