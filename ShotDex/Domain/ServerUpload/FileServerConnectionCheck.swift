import Foundation

/// Settings → File Servers → Test Connection (FS-15.01 §3): reach, log in,
/// open the folder, write a small file and remove it — stopping at the first
/// step that fails, because that step is the one the user has to fix.
enum FileServerConnectionCheck {
    enum Step: Equatable, Sendable {
        case connect
        case folder
        case write
    }

    enum Outcome: Equatable, Sendable {
        case connected
        case failed(Step, RemoteFileError)
    }

    static func run(client: any RemoteFileClient, folder: String) async -> Outcome {
        let folder = ServerUploadPath.normalizedFolder(folder)
        do {
            try await client.connect()
        } catch {
            return .failed(.connect, remote(error))
        }
        defer { Task { await client.disconnect() } }

        do {
            guard try await client.directoryExists(folder) else {
                return .failed(.folder, .folderMissing(folder.isEmpty ? "/" : folder))
            }
        } catch {
            return .failed(.folder, remote(error))
        }

        let probe = ServerUploadPath.join(folder, ".shotdex-write-test-\(UUID().uuidString.prefix(8))")
        let local = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(TemporaryWorkspace.serverUploadPrefix)probe-\(UUID().uuidString)")
        do {
            try Data("ShotDex".utf8).write(to: local)
            defer { try? FileManager.default.removeItem(at: local) }
            try await client.upload(local, to: probe) { _ in }
            try await client.remove(probe)
        } catch {
            let failure = remote(error)
            if case .folderMissing = failure { return .failed(.write, .permissionDenied(folder)) }
            return .failed(.write, failure)
        }
        return .connected
    }

    private static func remote(_ error: Error) -> RemoteFileError {
        (error as? RemoteFileError) ?? .other((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }
}
