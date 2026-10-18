import Foundation
import Observation

/// The app-level banner (FS-03.14c §4, E9): "Golden added to My Looks" ·
/// Undo, over whatever screen is up — Library, the viewer or the editor —
/// because a file sent by AirDrop arrives wherever the user happens to be.
/// Not the editor's own 3 s undo toast, which only knows the editor.
@MainActor
@Observable
final class AppBannerModel {
    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let text: String
        /// "Undo", "Details"; nil for a banner that only says something.
        let actionTitle: String?

        /// Long enough to read a line and reach the button; a plain line
        /// goes as quickly as the action toast.
        var duration: Duration {
            #if DEBUG
            if AppBannerModel.isSticky { return .seconds(3600) }
            #endif
            return actionTitle == nil ? .milliseconds(1600) : .seconds(4)
        }
    }

    private(set) var current: Banner?
    private var action: (() -> Void)?
    /// A receive's report, opened by the banner's Details.
    var presentedReport: PresetImportReport?
    /// Hosts on screen, oldest first: only the newest — the surface on top —
    /// draws the banner and presents Details.
    private(set) var hosts: [UUID] = []

    func appear(_ host: UUID) { hosts.removeAll { $0 == host }; hosts.append(host) }
    func disappear(_ host: UUID) { hosts.removeAll { $0 == host } }
    func isTop(_ host: UUID) -> Bool { hosts.last == host }

    #if DEBUG
    /// `-ShotDexStickyBanner`: a UI script photographs the banner on each
    /// screen, which a four-second banner does not survive.
    /// `-ShotDexStickyDetails` puts up the Details variant instead.
    nonisolated static let isSticky = ["-ShotDexStickyBanner", "-ShotDexStickyDetails"]
        .contains(where: ProcessInfo.processInfo.arguments.contains)

    init() {
        if ProcessInfo.processInfo.arguments.contains("-ShotDexStickyDetails") {
            let report = PresetImportReport(entries: [
                .init(name: "Harbour", status: .skipped, lines: [.init(kind: .skipped, text: "Already in My Looks")]),
            ])
            show("Harbour not added", actionTitle: "Details") { [weak self] in self?.presentedReport = report }
        } else if Self.isSticky {
            show("Golden added to My Looks", actionTitle: "Undo") {}
        }
    }
    #endif

    /// A new banner replaces the one showing; its button runs `action`.
    func show(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        current = Banner(text: text, actionTitle: action == nil ? nil : actionTitle)
        self.action = action
    }

    func performAction() {
        let action = action
        dismiss()
        action?()
    }

    func dismiss() {
        current = nil
        action = nil
    }

    /// The timer's end: only the banner it was started for goes.
    func expire(_ id: Banner.ID) {
        guard current?.id == id else { return }
        dismiss()
    }
}
