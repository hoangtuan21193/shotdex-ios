import Foundation
import Photos

/// Keeps the Photos background-upload extension in step with the jobs
/// (FS-22.02 §3c): on only while there is a Photos → WebDAV job and full
/// Photos access, with the jobs and their sign-ins handed over through the
/// App Group.
enum BackupUploadExtensionSync {
    /// The jobs the extension may serve. The extension cannot look a
    /// `.local` name up first, so it gets the address the name last had —
    /// which works at home and over a VPN from another app (FS-15.04 §7).
    static func config(jobs: [BackupJob], servers: [FileServer], addresses: any ServerAddressBook = DefaultsServerAddressBook()) -> BackupUploadConfig {
        var config = BackupUploadConfig()
        for job in jobs where job.sourceId == PhotoLibrarySource.id {
            guard let server = servers.first(where: { $0.id == job.connectionId }), server.transferProtocol == .webdav else { continue }
            let scheme = server.usesTLS ? "https" : "http"
            config.jobs.append(BackupUploadConfig.Job(
                jobId: job.id,
                baseURL: "\(scheme)://\(dialledHost(server, addresses: addresses)):\(server.port)",
                folder: job.folder,
                settings: job.settings,
                account: server.id
            ))
        }
        return config
    }

    private static func dialledHost(_ server: FileServer, addresses: any ServerAddressBook) -> String {
        guard LocalHostRoute.isMulticastDNS(server.host), let known = addresses.address(for: server.id) else { return server.host }
        return known
    }

    /// On only with full access — Photos refuses the extension otherwise.
    static func shouldEnable(_ config: BackupUploadConfig, status: PHAuthorizationStatus) -> Bool {
        !config.jobs.isEmpty && status == .authorized
    }

    /// Writes the config and sign-ins, then turns the extension on or off.
    @MainActor
    static func apply(jobs: [BackupJob], servers: FileServerStore) {
        let all = (try? servers.fetchAll()) ?? []
        let config = config(jobs: jobs, servers: all)
        // Sign-ins of connections no longer served leave the shared Keychain.
        let kept = Set(config.jobs.map(\.account))
        for gone in Set(BackupUploadShared.readConfig().jobs.map(\.account)).subtracting(kept) {
            BackupUploadShared.setAuthorization(nil, account: gone)
        }
        BackupUploadShared.writeConfig(config)
        for job in config.jobs {
            guard let server = all.first(where: { $0.id == job.account }) else { continue }
            let password = servers.password(for: server.id) ?? ""
            let header = server.username.isEmpty ? nil : "Basic " + Data("\(server.username):\(password)".utf8).base64EncodedString()
            BackupUploadShared.setAuthorization(header, account: job.account)
        }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        // Before Photos access is asked, reading `uploadJobExtensionEnabled`
        // opens the system prompt (measured on iOS 26.5): it would cover the
        // welcome screen, which must ask nothing (FS-21 §3). There is nothing
        // to turn on without access anyway.
        guard status != .notDetermined else { return }
        let enable = shouldEnable(config, status: status)
        let library = PHPhotoLibrary.shared()
        if #available(iOS 27.0, *) {
            if enable, !library.uploadJobExtensionEnabled {
                try? library.enableUploadJobExtension(with: nil)
            } else if !enable, library.uploadJobExtensionEnabled {
                try? library.disableUploadJobExtension()
            }
        } else if #available(iOS 26.1, *) {
            if enable != library.uploadJobExtensionEnabled {
                try? library.setUploadJobExtensionEnabled(enable)
            }
        }
    }
}
