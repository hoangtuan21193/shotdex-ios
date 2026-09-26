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
    /// The port-445 sweep for machines without Bonjour (FS-15.04 §4b).
    private let scanner: (any LocalNetworkScanning)?
    private var scanTask: Task<Void, Never>?
    private var records: [BonjourRecord] = []
    private var scanned: [ScannedHost] = []
    private var bonjourAddresses: Set<String> = []
    private var resolvedHosts: Set<String> = []
    private var hasTimedOut = false
    private var isScanFinished = true

    init(browser: any LocalServerBrowsing, scanner: (any LocalNetworkScanning)? = nil, giveUpAfter: Duration = .seconds(5)) {
        self.browser = browser
        self.scanner = scanner
        self.giveUpAfter = giveUpAfter
    }

    func start() {
        state = .searching
        isSearching = true
        isRunning = true
        hasTimedOut = false
        records = []
        scanned = []
        browser.start { [weak self] event in self?.handle(event) }
        let giveUpAfter = giveUpAfter
        timeout = Task { [weak self] in
            try? await Task.sleep(for: giveUpAfter)
            guard !Task.isCancelled, let self else { return }
            self.hasTimedOut = true
            self.settleIfDone()
        }
        if let scanner {
            isScanFinished = false
            scanTask = Task { [weak self] in
                await scanner.scan { host in
                    Task { @MainActor in self?.found(host) }
                }
                guard !Task.isCancelled else { return }
                self?.isScanFinished = true
                self?.settleIfDone()
            }
        }
    }

    /// Searching ends once the wait is over and the sweep is done.
    private func settleIfDone() {
        guard hasTimedOut, isScanFinished else { return }
        isSearching = false
        if state == .searching { state = .none }
    }

    private func found(_ host: ScannedHost) {
        guard isRunning, !scanned.contains(host) else { return }
        scanned.append(host)
        refresh()
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        scanTask?.cancel()
        scanTask = nil
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
            self.records = records
            resolveBonjourAddresses()
            refresh()
        }
    }

    /// Recomputes the rows from Bonjour and the sweep.
    private func refresh() {
        guard state != .denied else { return }
        let servers = DiscoveredServerMerge.merge(records, scanned: scanned, bonjourAddresses: bonjourAddresses)
        if !servers.isEmpty {
            state = .found(servers)
        } else if case .found = state {
            // Everything went away: back to the empty message once the
            // first look is over, else keep searching.
            state = isSearching ? .searching : .none
        }
    }

    /// Bonjour hosts' IPv4 addresses, so a Mac found both ways shows once.
    private func resolveBonjourAddresses() {
        guard let scanner else { return }
        let hosts = Set(records.compactMap { $0.host.map(DiscoveredServerMerge.normalizedHost) }).subtracting(resolvedHosts)
        guard !hosts.isEmpty else { return }
        resolvedHosts.formUnion(hosts)
        Task { [weak self] in
            let addresses = await scanner.addresses(of: Array(hosts))
            guard let self else { return }
            self.bonjourAddresses.formUnion(addresses)
            self.refresh()
        }
    }
}
