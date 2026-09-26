import Foundation

/// One Bonjour service a browser saw on the local network, resolved as far
/// as the browser got: `_smb._tcp` on "Hoang's MacBook" at
/// `Hoangs-MacBook.local:445`, or a `_device-info._tcp` record carrying only
/// the model in its TXT data.
struct BonjourRecord: Hashable, Sendable {
    /// The service instance name — what Finder shows, and how the records of
    /// one machine find each other.
    let name: String
    /// `_smb._tcp`, without the domain.
    let type: String
    /// The resolved host (`Hoangs-MacBook.local`), nil until resolved.
    var host: String?
    var port: Int?
    var txt: [String: String] = [:]
}

/// A computer or NAS found on the network (FS-15.04 §2): every service it
/// advertises folded into one row.
struct DiscoveredServer: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case laptop
        case desktop
        case nas
    }

    /// One way in, in the order the row's protocol menu lists them.
    struct Offer: Hashable, Sendable {
        let service: Service
        let host: String
        let port: Int
    }

    /// The protocols the network can advertise — more than ShotDex may speak
    /// yet; `transferProtocol` says which ones it does.
    enum Service: Int, Hashable, Sendable, Comparable {
        case smb
        case sftp
        case webdavHTTPS
        case webdav
        case ftp

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .smb: "SMB"
            case .sftp: "SFTP"
            case .webdavHTTPS: "WebDAV (HTTPS)"
            case .webdav: "WebDAV"
            case .ftp: "FTP"
            }
        }

        /// The connection type this service fills in, nil while ShotDex has
        /// no client for it.
        var transferProtocol: FileServer.TransferProtocol? {
            switch self {
            case .smb: .smb
            case .sftp: .sftp
            case .webdavHTTPS, .webdav: RemoteFileClientFactory.supports(.webdav) ? .webdav : nil
            case .ftp: RemoteFileClientFactory.supports(.ftp) ? .ftp : nil
            }
        }
    }

    let name: String
    let kind: Kind
    /// Supported offers only, best first.
    let offers: [Offer]

    var id: String { name }

    /// `SMB · SFTP` for the row.
    var protocolSummary: String {
        offers.map(\.service.title).joined(separator: " · ")
    }
}

/// Folds raw Bonjour records into one row per machine (FS-15.04 §2, §4).
enum DiscoveredServerMerge {
    static let serviceTypes = [
        "_smb._tcp", "_sftp-ssh._tcp", "_ssh._tcp", "_webdavs._tcp", "_webdav._tcp", "_ftp._tcp",
    ]
    static let deviceInfoType = "_device-info._tcp"

    /// `supports` drops services ShotDex has no client for yet — by default
    /// those without a `transferProtocol`.
    static func merge(
        _ records: some Sequence<BonjourRecord>,
        supports: (DiscoveredServer.Service) -> Bool = { $0.transferProtocol != nil }
    ) -> [DiscoveredServer] {
        let byName = Dictionary(grouping: records, by: \.name)
        return byName.compactMap { name, records in
            let types = Set(records.map(\.type))
            var offers: [DiscoveredServer.Offer] = []
            for record in records {
                guard let service = service(for: record.type, alongside: types),
                      supports(service),
                      let host = record.host.map(normalizedHost), !host.isEmpty,
                      let port = record.port
                else { continue }
                offers.append(.init(service: service, host: host, port: port))
            }
            guard !offers.isEmpty else { return nil }
            offers.sort { $0.service < $1.service }
            let model = records.first { $0.type == deviceInfoType }?.txt["model"]
            return DiscoveredServer(name: name, kind: kind(forModel: model), offers: offers)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// `_ssh._tcp` counts only on a machine that does not also advertise
    /// `_sftp-ssh._tcp` — a Mac with Remote Login advertises both, and one
    /// SFTP entry is enough.
    static func service(for type: String, alongside types: Set<String>) -> DiscoveredServer.Service? {
        switch type {
        case "_smb._tcp": .smb
        case "_sftp-ssh._tcp": .sftp
        case "_ssh._tcp": types.contains("_sftp-ssh._tcp") ? nil : .sftp
        case "_webdavs._tcp": .webdavHTTPS
        case "_webdav._tcp": .webdav
        case "_ftp._tcp": .ftp
        default: nil
        }
    }

    /// `MacBookPro18,3` → laptop, `Mac14,3`/`iMac21,1`/`Macmini9,1` → desktop,
    /// anything else (Synology, QNAP, no record) → NAS.
    static func kind(forModel model: String?) -> DiscoveredServer.Kind {
        guard let model else { return .nas }
        if model.hasPrefix("MacBook") { return .laptop }
        if model.hasPrefix("Mac") || model.hasPrefix("iMac") { return .desktop }
        return .nas
    }

    /// Bonjour hands back `Hoangs-MacBook.local.` — the trailing dot is DNS
    /// syntax nobody types.
    static func normalizedHost(_ host: String) -> String {
        host.hasSuffix(".") ? String(host.dropLast()) : host
    }
}

extension FileServerDraft {
    /// Tapping a found server (FS-15.04 §3): name, protocol, host and port
    /// filled in; a default port stays empty, the way the form shows it.
    mutating func apply(_ offer: DiscoveredServer.Offer, from server: DiscoveredServer) {
        guard let transferProtocol = offer.service.transferProtocol else { return }
        self.server.name = server.name
        self.server.transferProtocol = transferProtocol
        self.server.host = offer.host
        if transferProtocol == .webdav { self.server.usesTLS = offer.service == .webdavHTTPS }
        portText = offer.port == self.server.defaultPort ? "" : String(offer.port)
    }
}

/// The shares an SMB server lists, as the Choose… list shows them
/// (FS-15.04 §5): no administrative `$` shares, Finder order.
enum SMBShareNames {
    static func visible(_ names: some Sequence<String>) -> [String] {
        names
            .filter { !$0.hasSuffix("$") && !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
