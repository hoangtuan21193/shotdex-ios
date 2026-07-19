import Foundation
import Network
import os

/// The interface class of the current network path, for display in the
/// indexing progress UI.
enum NetworkConnectionType: Sendable, Equatable {
    case wifi
    case cellular
    case wired
    case other
    case offline

    var displayName: String {
        switch self {
        case .wifi: String(localized: "Wi-Fi")
        case .cellular: String(localized: "Cellular")
        case .wired: String(localized: "Wired")
        case .other: String(localized: "Network")
        case .offline: String(localized: "Offline")
        }
    }
}

/// Watches the network path so index runs can decide whether streaming EXIF
/// from iCloud is acceptable: Wi-Fi always, cellular only if the user opted in.
final class NetworkStatusService: Sendable {
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "network")

    private let monitor = NWPathMonitor()
    /// Starts true so we never stream over a metered path before the first
    /// path update arrives.
    private let expensive = OSAllocatedUnfairLock(initialState: true)
    private let connection = OSAllocatedUnfairLock(initialState: NetworkConnectionType.other)

    init() {
        let expensive = self.expensive
        let connection = self.connection
        monitor.pathUpdateHandler = { path in
            let type = Self.connectionType(of: path)
            let isExpensive = path.isExpensive || path.isConstrained
            expensive.withLock { $0 = isExpensive }
            connection.withLock { $0 = type }
            Self.logger.debug(
                "path update: \(type.displayName, privacy: .public), status \(String(describing: path.status), privacy: .public), expensive \(path.isExpensive), constrained \(path.isConstrained)"
            )
        }
        monitor.start(queue: DispatchQueue(label: "com.hoangtuan.shotdex.network-monitor"))
    }

    /// True on cellular, personal hotspot, or Low Data Mode paths.
    var isExpensivePath: Bool {
        expensive.withLock { $0 }
    }

    /// Interface class of the current path (polled by the indexing UI).
    var connectionType: NetworkConnectionType {
        connection.withLock { $0 }
    }

    private static func connectionType(of path: NWPath) -> NetworkConnectionType {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .other
    }

    deinit {
        monitor.cancel()
    }
}
