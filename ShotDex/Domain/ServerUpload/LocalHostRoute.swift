import Foundation

/// Which host to dial for a connection named by mDNS (FS-15.04 §7).
///
/// A `.local` name resolves only on the home network: multicast DNS is not
/// carried by a VPN. Away from home, over a VPN another app set up, the
/// address the name had the last time it resolved still routes home — so
/// that address is dialled instead. Every other host passes through.
enum LocalHostRoute {
    struct Choice: Equatable, Sendable {
        /// What to dial.
        var host: String
        /// A newly learned address to remember for next time.
        var remember: String?
    }

    static func isMulticastDNS(_ host: String) -> Bool {
        var name = host.lowercased()
        while name.hasSuffix(".") { name.removeLast() }
        return name.hasSuffix(".local") && name.count > ".local".count
    }

    /// `resolved`: the name's IPv4 address now, nil when it does not
    /// resolve. `lastKnown`: the address remembered from last time.
    static func choose(host: String, resolved: String?, lastKnown: String?) -> Choice {
        guard isMulticastDNS(host) else { return Choice(host: host, remember: nil) }
        if let resolved {
            return Choice(host: host, remember: resolved == lastKnown ? nil : resolved)
        }
        return Choice(host: lastKnown ?? host, remember: nil)
    }
}
