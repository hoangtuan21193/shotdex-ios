import Foundation
import Network
import Testing
@testable import ShotDex

/// FS-17 AC-71: a socket error from either library reads as something the
/// user can act on, never as "Network.NWError error 61".
@Suite struct NetworkErrorMappingTests {
    /// SMBClient throws the Network framework's own `NWError`, which bridges
    /// to the domain "Network.NWError", not "NWErrorDomain" (measured
    /// 2026-09-29: a server that was off showed the raw description).
    @Test func networkFrameworkErrorsMapLikePosixOnes() {
        #expect(mapNetworkError(NWError.posix(.ECONNREFUSED), host: "nas.local") as? RemoteFileError == .unreachable(host: "nas.local"))
        #expect(mapNetworkError(NWError.posix(.EHOSTUNREACH), host: "nas.local") as? RemoteFileError == .unreachable(host: "nas.local"))
        #expect(mapNetworkError(NWError.posix(.ETIMEDOUT), host: "nas.local") as? RemoteFileError == .unreachable(host: "nas.local"))
        #expect(mapNetworkError(NWError.posix(.ECONNRESET), host: "nas.local") as? RemoteFileError == .connectionLost)
        #expect(mapNetworkError(NWError.posix(.EPERM), host: "nas.local") as? RemoteFileError == .localNetworkDenied)
    }

    @Test func posixErrorsStillMap() {
        let refused = NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNREFUSED))
        #expect(mapNetworkError(refused, host: "nas.local") as? RemoteFileError == .unreachable(host: "nas.local"))
        let reset = NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNRESET))
        #expect(mapNetworkError(reset, host: "nas.local") as? RemoteFileError == .connectionLost)
    }

    @Test func refusedReadsAsSomethingToCheck() {
        let message = mapNetworkError(NWError.posix(.ECONNREFUSED), host: "nas.local").localizedDescription
        #expect(message == "Can't reach nas.local. Check that it's on and on the same network.")
    }
}
