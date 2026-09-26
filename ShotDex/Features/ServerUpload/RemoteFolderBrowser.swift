import Foundation
import Observation

/// One browse of a connection's folders (FS-15.02 §2a): one connection for
/// every screen pushed, each folder listed once and kept.
@MainActor
@Observable
final class RemoteFolderBrowser {
    enum Listing: Equatable {
        case loading
        case loaded([String])
        case failed(RemoteFileError)
    }

    private(set) var listings: [String: Listing] = [:]
    /// New Folder failed; the screen shows it and clears it.
    var createError: RemoteFileError?

    private let client: any RemoteFileClient
    private var connection: Task<Void, Error>?

    init(client: any RemoteFileClient) {
        self.client = client
    }

    func listing(for path: String) -> Listing {
        listings[path] ?? .loading
    }

    /// Lists `path` unless it already is; `force` is Try Again, which also
    /// reconnects when the connection itself was what failed.
    func load(_ path: String, force: Bool = false) async {
        if !force, let current = listings[path], current != .loading { return }
        listings[path] = .loading
        do {
            try await connect()
            let names = try await client.folderNames(in: path)
            listings[path] = .loaded(RemoteFolderListing.visible(names))
        } catch {
            listings[path] = .failed(Self.remoteError(error))
        }
    }

    /// Makes `name` inside `path` and returns the new folder's path, or nil
    /// with `createError` set. A folder that is already there is simply
    /// opened.
    func createFolder(named typed: String, in path: String) async -> String? {
        guard let name = RemoteFolderListing.validatedName(typed) else { return nil }
        let newPath = ServerUploadPath.join(path, name)
        do {
            try await connect()
            try await client.createDirectory(newPath)
            if case .loaded(let names) = listings[path], !names.contains(name) {
                listings[path] = .loaded(RemoteFolderListing.visible(names + [name]))
            }
            return newPath
        } catch {
            createError = Self.remoteError(error)
            return nil
        }
    }

    func close() async {
        connection?.cancel()
        connection = nil
        await client.disconnect()
    }

    private func connect() async throws {
        if connection == nil {
            let client = client
            connection = Task { try await client.connect() }
        }
        do {
            try await connection?.value
        } catch {
            // The next Try Again dials again instead of replaying this failure.
            connection = nil
            throw error
        }
    }

    private static func remoteError(_ error: Error) -> RemoteFileError {
        (error as? RemoteFileError) ?? .other(error.localizedDescription)
    }
}
