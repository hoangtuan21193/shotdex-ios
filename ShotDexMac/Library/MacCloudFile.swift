import Darwin
import Foundation
import os
import GRDB
import SwiftUI

/// A folder photo's file: where it is, and whether it is on this Mac or
/// still only in iCloud Drive (or another provider behind Finder).
struct MacPhotoFile: Equatable, Sendable {
    let url: URL
    /// In the cloud, not downloaded: reading it would start a download.
    let isPlaceholder: Bool
    /// Bytes the file takes, when the provider says.
    let size: Int64?
    /// The folder source it is in ("2026 Japan").
    let sourceName: String?
    /// Where it is, the way Finder names it ("iCloud Drive/2026 Japan/IMG_4120.JPG").
    let displayPath: String
    /// The provider's name, for "Downloading from iCloud Drive…".
    let provider: String
    /// The copy in its source, for the download and the read after it; nil in the demo.
    var copy: FolderSourceRunner.CloudFile?
}

enum MacPhotoFiles {
    /// The photo's file copy — one on this Mac when it has one, else the
    /// placeholder — resolved against its source's folder and looked at
    /// without opening it; nil for a Photos or server photo. Off the main
    /// actor: a database read and a bookmark.
    @MainActor
    static func resolve(_ id: String, dependencies: MacDependencies) async -> MacPhotoFile? {
        #if DEBUG
        if let demo = MacDemoLibrary.cloudFile(for: id) {
            return dependencies.cloudDownloads.finished.contains(id) ? nil : demo
        }
        #endif
        let database = dependencies.database
        let roots = dependencies.folderRoots
        // A tile scrolled past, a photo stepped over: the lookup stops between steps.
        let lookup = Task.detached(priority: .userInitiated) { () -> MacPhotoFile? in
            guard let row = try? await database.reader.read({ db in
                try Row.fetchOne(db, sql: """
                    SELECT c.sourceId, c.relativePath, c.isCloudPlaceholder FROM photo_copies c LEFT JOIN sources s ON s.id = c.sourceId
                    WHERE c.photoId = ? AND c.kind = 'file' AND c.missingSince IS NULL AND c.relativePath IS NOT NULL
                    ORDER BY c.isCloudPlaceholder, s.createdAt, c.relativePath LIMIT 1
                    """, arguments: [id])
            }), !Task.isCancelled else { return nil }
            let sourceId: String = row["sourceId"], path: String = row["relativePath"]
            guard let url = roots.fileURL(sourceId: sourceId, relativePath: path), !Task.isCancelled else { return nil }
            // The index's word, or the file's own now: a file macOS evicted since the read is a placeholder too.
            let indexed: Bool = row["isCloudPlaceholder"] ?? false
            return file(url, sourceName: roots.root(sourceId)?.lastPathComponent, indexedAsPlaceholder: indexed,
                        copy: FolderSourceRunner.CloudFile(sourceId: sourceId, relativePath: path, size: nil))
        }
        return await withTaskCancellationHandler { await lookup.value } onCancel: { lookup.cancel() }
    }

    nonisolated static func file(_ url: URL, sourceName: String?, indexedAsPlaceholder: Bool,
                                 copy: FolderSourceRunner.CloudFile?) -> MacPhotoFile {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let values = try? fresh.resourceValues(forKeys: [.fileSizeKey])
        let size = values?.fileSize.flatMap { $0 > 0 ? Int64($0) : nil } ?? CloudPlaceholder.size(of: url)
        let isPlaceholder = indexedAsPlaceholder || isDataless(url)
        return MacPhotoFile(url: url, isPlaceholder: isPlaceholder, size: size, sourceName: sourceName,
                            displayPath: displayPath(url), provider: provider(url),
                            copy: copy.map { FolderSourceRunner.CloudFile(sourceId: $0.sourceId, relativePath: $0.relativePath, size: size) })
    }

    /// Only in the cloud right now: iCloud Drive says not downloaded; any
    /// other provider (Dropbox, OneDrive…) leaves a dataless file. A local
    /// copy with a newer version waiting (`.downloaded`) reads fine.
    nonisolated static func isDataless(_ url: URL) -> Bool {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        if let status = try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus {
            return status == .notDownloaded
        }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }

    /// iCloud Drive's folder by its name; another provider's by the name Finder shows.
    nonisolated static func displayPath(_ url: URL) -> String {
        let path = url.path
        if let range = path.range(of: "/Library/Mobile Documents/com~apple~CloudDocs/") {
            return String(localized: "iCloud Drive", comment: "Mac viewer: the cloud provider's name") + "/" + path[range.upperBound...]
        }
        if let range = path.range(of: "/Library/CloudStorage/") {
            let rest = path[range.upperBound...]
            let folder = rest.prefix { $0 != "/" }
            return provider(url) + rest.dropFirst(folder.count)
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    nonisolated static func provider(_ url: URL) -> String {
        let path = url.path
        if let range = path.range(of: "/Library/CloudStorage/") {
            // "Dropbox", "OneDrive-Personal", "GoogleDrive-name@example.com": the part before the dash.
            let folder = path[range.upperBound...].prefix { $0 != "/" }
            return String(folder.prefix { $0 != "-" })
        }
        return String(localized: "iCloud Drive", comment: "Mac viewer: the cloud provider's name")
    }
}

/// The downloads the viewer started, one per photo the user opened
/// (FS-19.01b §4: the read of a source never downloads). Shared so the
/// photo, the inspector and the filmstrip agree; the source is read again
/// after each, so the photo gets its EXIF.
@MainActor
@Observable
final class MacCloudDownloads {
    enum Phase: Equatable {
        /// 0…1 when the provider says how far, nil while it does not.
        case downloading(Double?)
        /// The user pressed Cancel: waits for Download, never restarts by itself.
        case stopped
        case failed
        /// Not started: the file and 1 GB of headroom do not fit; bytes short.
        case notEnoughSpace(Int64)
    }

    private(set) var phases: [String: Phase] = [:]
    /// Downloaded since launch: the photo and its facts are read again.
    private(set) var finished: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// Which task is the photo's current one: one cancelled, or ending late, changes nothing.
    @ObservationIgnored private var generations: [String: Int] = [:]
    @ObservationIgnored private let runner: FolderSourceRunner

    init(runner: FolderSourceRunner) {
        self.runner = runner
    }

    /// Starts bringing the file down, unless it already is coming, is down,
    /// or stopped by the user or a failure (those wait for a press: `force`).
    func start(_ id: String, file: MacPhotoFile, force: Bool = false) {
        // Down once, gone again (macOS evicted it): it is a placeholder like any other.
        if file.isPlaceholder, finished.contains(id), tasks[id] == nil {
            finished.remove(id)
            phases[id] = nil
        }
        guard tasks[id] == nil, !finished.contains(id), force || phases[id] == nil else { return }
        phases[id] = .downloading(nil)
        let downloader = Self.downloader
        let runner = runner
        let generation = bump(id)
        tasks[id] = Task { [weak self] in
            let progress: @Sendable (Double?) -> Void = { fraction in
                Task { @MainActor [weak self] in
                    guard self?.generations[id] == generation, case .downloading? = self?.phases[id] else { return }
                    self?.phases[id] = .downloading(fraction)
                }
            }
            let outcome: Result<FolderSourceRunner.DownloadOutcome, any Error>
            do {
                if let copy = file.copy {
                    outcome = .success(try await runner.download(copy, with: downloader, progress: progress))
                } else {
                    try await downloader.download(file.url, progress: progress)
                    outcome = .success(.downloaded)
                }
            } catch {
                outcome = .failure(error)
            }
            guard let self, generations[id] == generation else { return }
            tasks[id] = nil
            switch outcome {
            case .success(.downloaded):
                phases[id] = nil
                finished.insert(id)
            case .success(.notEnoughSpace(let short)): phases[id] = .notEnoughSpace(short)
            case .success(.unavailable): phases[id] = .failed
            case .failure(let error): phases[id] = error is CancellationError ? .stopped : .failed
            }
        }
    }

    /// Cancel: the wait stops and the photo says it is still in the cloud.
    /// Nothing is evicted — a file macOS finishes anyway simply arrives.
    func cancel(_ id: String) {
        guard tasks[id] != nil else { return }
        bump(id)
        tasks[id]?.cancel()
        tasks[id] = nil
        phases[id] = .stopped
    }

    /// The viewer moved to another photo or closed: its download stops, and
    /// starts again when the user comes back to it.
    func leave(_ id: String) {
        // A failure is tried again on the way back (space freed, network back); Cancel is kept.
        if phases[id] == .failed { phases[id] = nil }
        if case .notEnoughSpace? = phases[id] { phases[id] = nil }
        guard tasks[id] != nil else { return }
        bump(id)
        tasks[id]?.cancel()
        tasks[id] = nil
        phases[id] = nil
    }

    @discardableResult
    private func bump(_ id: String) -> Int {
        let generation = (generations[id] ?? 0) + 1
        generations[id] = generation
        return generation
    }

    private static var downloader: any CloudFileDownloading {
        #if DEBUG
        if MacDemoLibrary.isOn { return MacDemoCloudDownloader() }
        #endif
        return MacProviderDownloader()
    }
}

/// iCloud Drive: `startDownloadingUbiquitousItem`, then a look four times a
/// second until it is current, how far shown by the bytes already on disk,
/// and the provider's own error read each time. Any other provider: a
/// coordinated read, which is how Finder asks it for the file (no fraction).
/// Cancelling stops the wait; nothing is evicted.
struct MacProviderDownloader: CloudFileDownloading {
    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        guard (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true else {
            progress(nil)
            try await coordinatedRead(url)
            progress(1)
            return
        }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        while true {
            var fresh = url
            fresh.removeAllCachedResourceValues()
            let values = try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey,
                                                             .fileSizeKey, .totalFileAllocatedSizeKey])
            if let error = values?.ubiquitousItemDownloadingError { throw error }
            if values?.ubiquitousItemDownloadingStatus == .current { break }
            if let size = values?.fileSize, size > 0, let allocated = values?.totalFileAllocatedSize, allocated > 0 {
                progress(min(1, Double(allocated) / Double(size)))
            } else {
                progress(nil)
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        progress(1)
    }

    private func coordinatedRead(_ url: URL) async throws {
        let coordinator = NSFileCoordinator()
        let isCancelled = OSAllocatedUnfairLock(initialState: false)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    // A cancel before the coordinator started would not reach it.
                    if isCancelled.withLock({ $0 }) { continuation.resume(throwing: CancellationError()); return }
                    var failure: NSError?
                    coordinator.coordinate(readingItemAt: url, options: [], error: &failure) { _ in }
                    if let failure { continuation.resume(throwing: failure) } else { continuation.resume() }
                }
            }
        } onCancel: {
            isCancelled.withLock { $0 = true }
            coordinator.cancel()
        }
        try Task.checkCancellation()
    }
}

#if DEBUG
/// The demo's iCloud photo: thirty seconds of download with a real fraction,
/// long enough for a script to see the bar and press Cancel.
struct MacDemoCloudDownloader: CloudFileDownloading {
    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        for step in 0...40 {
            progress(Double(step) / 40)
            try await Task.sleep(for: .milliseconds(750))
        }
    }
}
#endif

/// The photo's place in the viewer while its file is in the cloud (board
/// `MAC_ViewerCloudDownload`): cloud, name, "Downloading from iCloud Drive…",
/// a bar with bytes, and Cancel; after Cancel, Download.
struct MacCloudDownloadView: View {
    let name: String
    let file: MacPhotoFile
    let phase: MacCloudDownloads.Phase?
    let cancel: () -> Void
    let download: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "icloud.and.arrow.down").font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary).padding(.bottom, 14)
                .accessibilityHidden(true)
            Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4)
            if case .downloading(let fraction)? = phase {
                MacDownloadBar(fraction: fraction)
                    .padding(.top, 16)
                    .accessibilityElement()
                    .accessibilityLabel(String(localized: "Download Progress", comment: "Mac viewer: the iCloud download bar"))
                    .accessibilityValue(fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
                if let bytes = bytes(fraction) {
                    Text(bytes).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().padding(.top, 6)
                }
                Button(String(localized: "Cancel", comment: "Mac viewer: stop the iCloud download"), action: cancel)
                    .controlSize(.large)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .tint(.primary)
                    // Not Esc: Esc closes the viewer, which stops the download too.
                    .padding(.top, 14)
            } else {
                Button(phase == nil || phase == .stopped ? String(localized: "Download", comment: "Mac viewer: bring the photo down from iCloud")
                                                         : String(localized: "Try Again", comment: "Mac viewer: download the photo again after a failure"),
                       action: download)
                    .controlSize(.large)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: 320)
        // Top-anchored in a fixed block: Cancel does not make the panel jump.
        .frame(height: 170, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        switch phase {
        case .downloading?:
            String(localized: "Downloading from \(file.provider)…", comment: "Mac viewer: the photo is coming down; the provider's name")
        case .failed?:
            String(localized: "Couldn’t download from \(file.provider). Check the connection and try again.",
                   comment: "Mac viewer: the iCloud download failed; the provider's name")
        case .notEnoughSpace(let short)?:
            String(localized: "Not enough space on this Mac. Free up \(ByteCountFormatter.string(fromByteCount: short, countStyle: .file)) and try again.",
                   comment: "Mac viewer: the iCloud download would not fit; the bytes to free")
        case .stopped?, nil:
            file.size.map {
                String(localized: "In \(file.provider) · \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))",
                       comment: "Mac viewer: the photo is only in the cloud; the provider and the file size")
            } ?? String(localized: "In \(file.provider)", comment: "Mac viewer: the photo is only in the cloud; the provider's name")
        }
    }

    private func bytes(_ fraction: Double?) -> String? {
        guard let size = file.size else { return nil }
        let total = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        guard let fraction else { return total }
        let done = ByteCountFormatter.string(fromByteCount: Int64(Double(size) * fraction), countStyle: .file)
        return String(localized: "\(done) of \(total)", comment: "Mac viewer: bytes downloaded of the file's size")
    }
}

/// The board's bar: a 220×4 track with the accent fill; while the provider
/// says nothing, a segment sweeps across it.
struct MacDownloadBar: View {
    let fraction: Double?
    @State private var sweeps = false

    var body: some View {
        Capsule().fill(MacTheme.fill2)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    if let fraction {
                        Capsule().fill(MacTheme.accent)
                            .frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
                            .animation(.linear(duration: 0.25), value: fraction)
                    } else {
                        Capsule().fill(MacTheme.accent)
                            .frame(width: proxy.size.width * 0.3)
                            .offset(x: sweeps ? proxy.size.width * 0.7 : 0)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: sweeps)
                            .onAppear { sweeps = true }
                    }
                }
            }
            .clipShape(Capsule())
            .frame(width: 220, height: 4)
    }
}
