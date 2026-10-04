import Foundation

/// The running sheet's numbers (FS-03.07c §2): `Exporting 212 of 500`, the
/// bytes and time left, and the file being made with its step.
struct FileExportProgress: Sendable, Equatable {
    var total = 0
    /// Assets finished in this run.
    var done = 0
    var totalBytes: Int64 = 0
    var bytesWritten: Int64 = 0
    /// The asset being made now: its original name and the file it becomes.
    var currentName: String?
    var currentTarget: String?
    var step: FileExportStep?
    var rate = TransferRateEstimate()

    /// 1-based, for `Exporting k of n`.
    var current: Int { min(total, done + 1) }
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }

    mutating func apply(_ event: FileExportRunner.Event, at now: Date = Date()) {
        switch event {
        case .started(_, _, let entry):
            currentName = entry.item.filename
            currentTarget = entry.outputs.first.map { ServerUploadPath.join(entry.folder, $0.name) }
            step = nil
        case .step(_, let step):
            self.step = step
        case .finished(_, let bytes):
            bytesWritten += bytes
            rate.record(bytesWritten, at: now)
        case .assetDone:
            done += 1
        }
    }

    var headline: String {
        ExportCopy.exporting(current, of: total)
    }

    /// `1.4 of 3.2 GB · about 4 min left`.
    var detail: String {
        let written = ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
        let all = ByteCountFormatter.string(fromByteCount: max(totalBytes, bytesWritten), countStyle: .file)
        var line = ExportCopy.bytesOf(written, all)
        if let seconds = rate.secondsLeft(total: max(totalBytes, bytesWritten)) {
            line += " · " + ExportCopy.timeLeft(seconds)
        }
        return line
    }
}
