import Foundation
import Observation

/// The "Servers Found on This Network" section of the Add Connection form
/// (FS-15.04 §2): searching, found, nothing after a while, or no permission.
@MainActor
@Observable
final class ServerDiscoveryModel {
    enum State: Equatable {
        case searching
        case found([DiscoveredServer])
        case none
        case denied
    }

    private(set) var state: State = .searching
    /// Still listening after something was found — the header's spinner.
    private(set) var isSearching = false

    private let browser: any LocalServerBrowsing
    private let giveUpAfter: Duration
    private var timeout: Task<Void, Never>?
    /// The browser reports "denied" the moment the system shows its Local
    /// Network prompt, before the user answers. The first denial is that
    /// prompt; only a denial after the app is active again is an answer.
    private var hasSeenPrompt = false
    private var isRunning = false

    init(browser: any LocalServerBrowsing, giveUpAfter: Duration = .seconds(5)) {
        self.browser = browser
        self.giveUpAfter = giveUpAfter
    }

    func start() {
        state = .searching
        isSearching = true
        isRunning = true
        browser.start { [weak self] event in self?.handle(event) }
        let giveUpAfter = giveUpAfter
        timeout = Task { [weak self] in
            try? await Task.sleep(for: giveUpAfter)
            guard !Task.isCancelled, let self else { return }
            self.isSearching = false
            if self.state == .searching { self.state = .none }
        }
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        browser.stop()
        isSearching = false
        isRunning = false
    }

    /// The app is active again — the permission prompt closed, or the user
    /// came back from Settings. A browser that was refused stays refused, so
    /// look again (FS-15.04 §2).
    func appBecameActive() {
        guard isRunning else { return }
        let wasDenied = state == .denied || !hasSeenPrompt && deniedWhilePrompting
        guard wasDenied else { return }
        hasSeenPrompt = true
        deniedWhilePrompting = false
        timeout?.cancel()
        browser.stop()
        start()
    }

    private var deniedWhilePrompting = false

    private func handle(_ event: LocalServerBrowserEvent) {
        switch event {
        case .denied:
            if hasSeenPrompt {
                state = .denied
                isSearching = false
            } else {
                // The system is asking right now; keep the spinner.
                deniedWhilePrompting = true
            }
        case .records(let records):
            guard state != .denied else { return }
            let servers = DiscoveredServerMerge.merge(records)
            if !servers.isEmpty {
                state = .found(servers)
            } else if case .found = state {
                // Everything went away: back to the empty message once the
                // first look is over, else keep searching.
                state = isSearching ? .searching : .none
            }
        }
    }
}
