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

    init(browser: any LocalServerBrowsing, giveUpAfter: Duration = .seconds(5)) {
        self.browser = browser
        self.giveUpAfter = giveUpAfter
    }

    func start() {
        state = .searching
        isSearching = true
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
    }

    private func handle(_ event: LocalServerBrowserEvent) {
        switch event {
        case .denied:
            state = .denied
            isSearching = false
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
