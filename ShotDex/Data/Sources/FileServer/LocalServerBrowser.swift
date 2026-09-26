import dnssd
import Foundation
import Network

/// What a network browser reports (FS-15.04 §2).
enum LocalServerBrowserEvent: Sendable {
    /// Everything seen so far, resolved as far as it got.
    case records([BonjourRecord])
    /// Local Network access is off for ShotDex.
    case denied
}

/// Watches the local network for file servers while the Add Connection form
/// is open. A protocol so the form's model runs in a unit test against a
/// scripted browser.
@MainActor
protocol LocalServerBrowsing: AnyObject {
    func start(onEvent: @escaping @MainActor (LocalServerBrowserEvent) -> Void)
    func stop()
}

/// Bonjour over Network framework: one `NWBrowser` per service type, and
/// `DNSServiceResolve` for the host name — `NWBrowser` hands back a service
/// endpoint, and connecting to it would give an IP, which DHCP changes; the
/// connection keeps the `.local` name instead (FS-15.04 §3).
///
/// All state lives on `queue`; events hop to the main actor.
@MainActor
final class BonjourServerBrowser: LocalServerBrowsing {
    private let queue = DispatchQueue(label: "com.hoangtuan.shotdex.bonjour")
    private let state = BrowseState()

    func start(onEvent: @escaping @MainActor (LocalServerBrowserEvent) -> Void) {
        let state = state
        let queue = queue
        queue.async {
            state.start(on: queue) { event in
                Task { @MainActor in onEvent(event) }
            }
        }
    }

    func stop() {
        let state = state
        queue.async { state.stop() }
    }
}

/// The browsers, resolvers and records, touched only on the browser's queue.
private final class BrowseState: @unchecked Sendable {
    private var browsers: [NWBrowser] = []
    private var resolvers: [RecordKey: ServiceResolver] = [:]
    private var records: [RecordKey: BonjourRecord] = [:]
    private var emit: (@Sendable (LocalServerBrowserEvent) -> Void)?
    private var hasReportedDenied = false

    struct RecordKey: Hashable {
        let name: String
        let type: String
    }

    func start(on queue: DispatchQueue, emit: @escaping @Sendable (LocalServerBrowserEvent) -> Void) {
        stop()
        self.emit = emit
        for type in DiscoveredServerMerge.serviceTypes + [DiscoveredServerMerge.deviceInfoType] {
            let parameters = NWParameters()
            parameters.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: parameters)
            browser.stateUpdateHandler = { [weak self] newState in
                self?.handle(newState)
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.update(type: type, results: results, queue: queue)
            }
            browser.start(queue: queue)
            browsers.append(browser)
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers = []
        resolvers.values.forEach { $0.cancel() }
        resolvers = [:]
        records = [:]
        emit = nil
        hasReportedDenied = false
    }

    private func handle(_ state: NWBrowser.State) {
        // Local Network denied surfaces as a DNS policy error while waiting.
        if case .waiting(let error) = state, case .dns(let code) = error,
           code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied), !hasReportedDenied {
            hasReportedDenied = true
            emit?(.denied)
        }
    }

    private func update(type: String, results: Set<NWBrowser.Result>, queue: DispatchQueue) {
        var seen = Set<RecordKey>()
        for result in results {
            guard case .service(let name, _, let domain, _) = result.endpoint else { continue }
            let key = RecordKey(name: name, type: type)
            seen.insert(key)
            var txt: [String: String] = [:]
            if case .bonjour(let record) = result.metadata {
                txt = record.dictionary
            }
            var record = records[key] ?? BonjourRecord(name: name, type: type)
            record.txt = txt
            records[key] = record
            // Only services a connection is made to need an address.
            if type != DiscoveredServerMerge.deviceInfoType, resolvers[key] == nil {
                resolvers[key] = ServiceResolver(name: name, type: type, domain: domain, queue: queue) { [weak self] host, port in
                    guard let self, var record = self.records[key] else { return }
                    record.host = host
                    record.port = port
                    self.records[key] = record
                    self.publish()
                }
            }
        }
        // Gone from the network: drop the record and its resolver.
        for key in records.keys where key.type == type && !seen.contains(key) {
            records[key] = nil
            resolvers.removeValue(forKey: key)?.cancel()
        }
        publish()
    }

    private func publish() {
        emit?(.records(Array(records.values)))
    }
}

/// One `DNSServiceResolve`, delivering the SRV target and port once.
private final class ServiceResolver: @unchecked Sendable {
    private var ref: DNSServiceRef?
    private let onResolve: (String, Int) -> Void

    init(name: String, type: String, domain: String, queue: DispatchQueue, onResolve: @escaping (String, Int) -> Void) {
        self.onResolve = onResolve
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = DNSServiceResolve(
            &ref, 0, 0, name, type, domain,
            { _, _, _, errorCode, _, hostTarget, port, _, _, context in
                guard errorCode == kDNSServiceErr_NoError, let context, let hostTarget else { return }
                let resolver = Unmanaged<ServiceResolver>.fromOpaque(context).takeUnretainedValue()
                resolver.onResolve(String(cString: hostTarget), Int(UInt16(bigEndian: port)))
            },
            context
        )
        if status == kDNSServiceErr_NoError, let ref {
            DNSServiceSetDispatchQueue(ref, queue)
        } else {
            ref = nil
        }
    }

    func cancel() {
        if let ref { DNSServiceRefDeallocate(ref) }
        ref = nil
    }

    deinit { cancel() }
}
