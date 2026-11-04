import CoreGraphics
import Foundation
import os

/// A client for a `.local` connection that picks the address to dial on
/// first use (FS-15.04 §7): the name at home, the address it had last time
/// when it does not resolve — away from home, over a VPN from another app.
/// Every call then goes to the client built for that address.
final class RoutedRemoteFileClient: RemoteFileClient, @unchecked Sendable {
    private let server: FileServer
    private let addresses: any ServerAddressBook
    private let resolve: @Sendable (String) async -> String?
    private let make: @Sendable (FileServer) -> any RemoteFileClient
    private let routed = OSAllocatedUnfairLock<(any RemoteFileClient)?>(initialState: nil)

    init(
        server: FileServer,
        addresses: any ServerAddressBook,
        resolve: @escaping @Sendable (String) async -> String? = { await HostAddressLookup.ipv4(of: $0) },
        make: @escaping @Sendable (FileServer) -> any RemoteFileClient
    ) {
        self.server = server
        self.addresses = addresses
        self.resolve = resolve
        self.make = make
    }

    private func client() async -> any RemoteFileClient {
        if let existing = routed.withLock({ $0 }) { return existing }
        let choice = LocalHostRoute.choose(
            host: server.host,
            resolved: await resolve(server.host),
            lastKnown: addresses.address(for: server.id)
        )
        if let learned = choice.remember { addresses.setAddress(learned, for: server.id) }
        var target = server
        target.host = choice.host
        let made = make(target)
        return routed.withLock { stored in
            if let stored { return stored }
            stored = made
            return made
        }
    }

    func connect() async throws { try await client().connect() }
    func disconnect() async {
        guard let existing = routed.withLock({ $0 }) else { return }
        await existing.disconnect()
    }
    func fileSize(at path: String) async throws -> Int64? { try await client().fileSize(at: path) }
    func directoryExists(_ path: String) async throws -> Bool { try await client().directoryExists(path) }
    func fileNames(in directory: String) async throws -> Set<String> { try await client().fileNames(in: directory) }
    func folderNames(in directory: String) async throws -> Set<String> { try await client().folderNames(in: directory) }
    func createDirectory(_ path: String) async throws { try await client().createDirectory(path) }
    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await client().upload(localURL, to: path, progress: progress)
    }
    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await client().sha256(of: path, progress: progress)
    }
    func entries(in directory: String) async throws -> [RemoteEntry] { try await client().entries(in: directory) }
    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        try await client().readRange(path, offset: offset, length: length)
    }
    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await client().download(path, to: localURL, progress: progress)
    }
    func move(_ source: String, to destination: String) async throws { try await client().move(source, to: destination) }
    func copyOnServer(_ source: String, to destination: String) async throws -> Bool {
        try await client().copyOnServer(source, to: destination)
    }
    func remove(_ path: String) async throws { try await client().remove(path) }
    func removeEmptyDirectory(_ path: String) async throws { try await client().removeEmptyDirectory(path) }
    func removeFolderTree(_ path: String) async throws { try await client().removeFolderTree(path) }
    func storageSpace(at path: String) async throws -> StorageSpace? { try await client().storageSpace(at: path) }
    func systemThumbnail(at path: String, maxPixelSize: Int) async -> CGImage? {
        await client().systemThumbnail(at: path, maxPixelSize: maxPixelSize)
    }
}
