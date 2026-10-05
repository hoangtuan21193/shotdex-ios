import Foundation
import Photos
import ShotDexKit

/// Where an asset's bytes come from: PhotoKit in the app, files on disk in
/// the tests (FS-03.07b §9: copied in blocks, never whole in memory).
protocol ExportAssetSource: Sendable {
    /// Writes one file of the asset to `url`, downloading it from iCloud when
    /// it is not on this device. `progress` gets 0…1 for a download.
    func copy(
        _ file: FileExportSourceFile,
        of item: FileExportItem,
        to url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

/// The one step a Current Version export adds between the render and the
/// metadata — a watermark (FS-05.04). Nil until that plan supplies it; when
/// it throws, the photo is left out, never written without its stamp.
protocol ExportStamping: Sendable {
    func stamp(_ result: PhotoRenderResult, for item: FileExportItem) async throws -> PhotoRenderResult
}

/// How a Current Version photo is made from its source file.
struct FileExportRenderOptions: Sendable, Equatable {
    var preset: ResizePreset = .original
    /// Resolved: JPEG or HEIC, never Same as Original.
    var format: PhotoOutputFormat = .jpeg
    var quality = 0.8
    var metadata: MetadataLevel = .all
}

/// Renders Current Version: read the source, render, resize, stamp, write
/// with the source's metadata at the level. The app's is the kit's
/// renderer; the seam keeps the runner testable.
protocol ExportRendering: Sendable {
    func inspect(_ url: URL) async throws -> PhotoRenderSourceInfo
    func render(
        _ source: PhotoRenderSourceInfo,
        options: FileExportRenderOptions,
        stamp: (any ExportStamping)?,
        item: FileExportItem,
        to url: URL
    ) async throws
}

/// One export: the plan with every name, and how to make each file.
struct FileExportJob: Sendable {
    let plan: FileExportPlan
    let mode: FileExportMode
    var version: FileExportVersion = .edited
    var render = FileExportRenderOptions()
    /// The watermark (FS-05.04): `WatermarkExportStamping` when the sheet's
    /// row is on, else nil.
    var stamp: (any ExportStamping)?
}

/// What the sheet shows while a file is made (FS-03.07c §2).
enum FileExportStep: Sendable, Equatable {
    /// Downloading from iCloud, with its fraction when known.
    case preparing(Double?)
    case converting
    case writing
}

/// What came of a run, by asset id.
struct FileExportReport: Sendable, Equatable {
    /// Paths written per asset, relative to the export folder.
    var written: [String: [String]] = [:]
    /// Files already written, `id|name` — a retry never writes them twice.
    var writtenOutputs: Set<String> = []
    var failed: [String: FileExportFailure] = [:]
    /// A destination problem that stopped the batch.
    var stoppedBy: FileExportFailure?
    var wasCancelled = false
    var bytesWritten: Int64 = 0

    var writtenCount: Int { written.count }

    /// Every asset of the plan not written yet — Export Remaining.
    func remaining(in plan: FileExportPlan) -> [String] {
        plan.writtenEntries.map(\.id).filter { written[$0] == nil }
    }

    /// Only the ones that failed — Retry Failed.
    var failedIds: [String] { Array(failed.keys) }
}

/// Runs a planned export one asset at a time (FS-03.07c §2): prepare →
/// copy, or render → stamp → metadata → write, each file under its part
/// name until it is whole. A photo's problem leaves the batch running; the
/// destination's stops it. Cancelling stops at the next block.
actor FileExportRunner {
    enum Event: Sendable {
        /// Starting an asset: its index in the run, the run's size, the file
        /// it becomes.
        case started(index: Int, total: Int, entry: FileExportPlan.Entry)
        case step(id: String, FileExportStep)
        /// One file of an asset written.
        case finished(id: String, bytes: Int64)
        /// An asset is through — written, or left out.
        case assetDone(id: String)
    }

    private let source: any ExportAssetSource
    private let writer: any ExportDestinationWriter
    private let rendering: any ExportRendering
    private let workDirectory: URL
    private let onEvent: @Sendable (Event) -> Void
    private(set) var report = FileExportReport()

    /// The prefix of the scratch folder a render's source sits in.
    static let prefix = "ShotDexExport-"

    init(
        source: any ExportAssetSource,
        writer: any ExportDestinationWriter,
        rendering: any ExportRendering,
        workDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(FileExportRunner.prefix)\(UUID().uuidString)", isDirectory: true),
        onEvent: @escaping @Sendable (Event) -> Void = { _ in }
    ) {
        self.source = source
        self.writer = writer
        self.rendering = rendering
        self.workDirectory = workDirectory
        self.onEvent = onEvent
    }

    /// Runs the plan, or only `ids` of it (Export Remaining, Retry Failed);
    /// what is already written is never written again.
    func run(_ job: FileExportJob, only ids: Set<String>? = nil) async -> FileExportReport {
        report.stoppedBy = nil
        report.wasCancelled = false
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let entries = job.plan.writtenEntries.filter { entry in
            report.written[entry.id] == nil && (ids?.contains(entry.id) ?? true)
        }
        for folder in Set(entries.map(\.folder)) { await writer.sweepLeftoverParts(in: folder) }
        let prefetcher = source as? any ExportPrefetching
        if let prefetcher {
            await prefetcher.prepare(entries.flatMap { entry in
                entry.outputs.compactMap { output in
                    (output.source ?? Self.renderSources(of: entry.item, version: job.version).first).map { (entry.item, $0) }
                }
            })
        }
        defer { if let prefetcher { Task { await prefetcher.cancelAll() } } }
        for (index, entry) in entries.enumerated() {
            if Task.isCancelled {
                report.wasCancelled = true
                break
            }
            onEvent(.started(index: index, total: entries.count, entry: entry))
            do {
                let paths = try await export(entry, job: job)
                report.failed[entry.id] = nil
                report.written[entry.id] = paths
            } catch is CancellationError {
                report.wasCancelled = true
                break
            } catch {
                let failure = Self.failure(for: error)
                if failure.stopsBatch {
                    report.stoppedBy = failure
                    break
                }
                report.failed[entry.id] = failure
            }
            onEvent(.assetDone(id: entry.id))
        }
        return report
    }

    private func export(_ entry: FileExportPlan.Entry, job: FileExportJob) async throws -> [String] {
        var paths: [String] = []
        for output in entry.outputs {
            let key = "\(entry.id)|\(output.name)"
            if report.writtenOutputs.contains(key) {
                paths.append(ServerUploadPath.join(entry.folder, output.name))
                continue
            }
            let path: String
            if let file = output.source {
                path = try await copy(file, of: entry, as: output)
            } else {
                path = try await render(entry, as: output, job: job)
            }
            report.writtenOutputs.insert(key)
            paths.append(path)
        }
        return paths
    }

    /// A file as it is, straight into its part name at the destination.
    private func copy(_ file: FileExportSourceFile, of entry: FileExportPlan.Entry, as output: FileExportPlan.Output) async throws -> String {
        let id = entry.id
        let item = entry.item
        let source = source
        let onEvent = onEvent
        onEvent(.step(id: id, .writing))
        let written = try await writer.write(name: output.name, in: entry.folder, replacing: output.replaces) { url in
            try await source.copy(file, of: item, to: url) { fraction in
                onEvent(.step(id: id, .preparing(fraction)))
            }
        }
        report.bytesWritten += written.bytes
        onEvent(.finished(id: id, bytes: written.bytes))
        return written.path
    }

    /// Current Version of a photo: its source on this device, rendered once
    /// straight into the part name at the destination.
    private func render(_ entry: FileExportPlan.Entry, as output: FileExportPlan.Output, job: FileExportJob) async throws -> String {
        let id = entry.id
        let item = entry.item
        let candidates = Self.renderSources(of: item, version: job.version)
        guard let preferred = candidates.first else { throw FileExportFailure.unreadable }
        let folder = workDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = source
        let rendering = rendering
        let onEvent = onEvent
        onEvent(.step(id: id, .preparing(nil)))
        // The RAW of a pair the decoder can't read falls back to its JPEG;
        // a RAW alone stays an error (FS-03.04b §4). Never a preview.
        let info = try await ReadableSource.load(preferred: preferred, among: candidates, isRAW: \.isRAW) { file in
            let url = folder.appendingPathComponent(file.filename.isEmpty ? "source" : file.filename)
            try? FileManager.default.removeItem(at: url)
            try await source.copy(file, of: item, to: url) { fraction in
                onEvent(.step(id: id, .preparing(fraction)))
            }
            return try await rendering.inspect(url)
        }
        try Task.checkCancellation()
        onEvent(.step(id: id, .converting))
        let options = job.render
        let stamp = job.stamp
        let written = try await writer.write(name: output.name, in: entry.folder, replacing: output.replaces) { url in
            try await rendering.render(info, options: options, stamp: stamp, item: item, to: url)
            onEvent(.step(id: id, .writing))
        }
        report.bytesWritten += written.bytes
        onEvent(.finished(id: id, bytes: written.bytes))
        return written.path
    }

    /// The files a Current Version render may read, preferred first.
    /// Edited is the version Photos shows: its render when the photo was
    /// edited there, else the photo. Original is the file as shot: the RAW
    /// first, its JPEG if the decoder can't read it.
    static func renderSources(of item: FileExportItem, version: FileExportVersion) -> [FileExportSourceFile] {
        let photo = item.files.first { $0.role == .photo }
        let alternate = item.files.first { $0.role == .alternatePhoto }
        let originals = [photo, alternate].compactMap { $0 }
        if version == .edited, let edited = item.files.first(where: { $0.role == .editedPhoto }) {
            return [edited]
        }
        // RAW first, the rendered twin after.
        return originals.filter(\.isRAW) + originals.filter { !$0.isRAW }
    }

    /// Sorts what a step threw into what the summary says.
    static func failure(for error: Error) -> FileExportFailure {
        if let failure = error as? FileExportFailure { return failure }
        if UnsupportedRAWError.matches(error) { return .unsupportedRAW }
        if let fetch = error as? OriginalFetchError {
            switch fetch {
            case .missing: return .noLongerAvailable
            case .incomplete: return .downloadFailed
            case .outOfSpace: return .full
            }
        }
        if let editing = error as? PhotoEditingError {
            switch editing {
            case .cannotDecode, .missingSource, .unavailable: return .unreadable
            default: return .renderFailed
            }
        }
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain {
            switch nsError.code {
            case PHPhotosError.Code.networkAccessRequired.rawValue, PHPhotosError.Code.networkError.rawValue:
                return .downloadFailed
            case PHPhotosError.Code.accessUserDenied.rawValue, PHPhotosError.Code.accessRestricted.rawValue:
                return .noLongerAvailable
            default:
                return .unreadable
            }
        }
        return .unreadable
    }
}
