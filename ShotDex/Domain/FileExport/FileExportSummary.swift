import Foundation

/// The words of the summary (FS-03.07c §2–3): one headline, a detail line,
/// the photos not exported with their reasons, and which way on it offers.
struct FileExportSummary: Equatable {
    struct Failure: Equatable {
        let name: String
        let reason: String
    }

    let headline: String
    let detail: String
    let failures: [Failure]
    /// Nothing went wrong and nothing was left out.
    let isClean: Bool
    /// The batch stopped: every unwritten photo can go once the folder is back.
    let offersExportRemaining: Bool
    let offersRetry: Bool
    /// The folder refused the write.
    let offersAnotherFolder: Bool

    init(plan: FileExportPlan?, report: FileExportReport?, preflight: FileExportFailure?, folder: ExportFolder?) {
        let folderName = folder?.name ?? ""
        let drive = folder.map { $0.isOnExternalDrive ? $0.place : $0.name } ?? ""
        let total = plan?.writtenEntries.count ?? 0
        let written = report?.writtenCount ?? 0
        let skipped = plan?.skipCount ?? 0
        let byId = Dictionary(uniqueKeysWithValues: (plan?.entries ?? []).map { ($0.id, $0.item.filename) })
        failures = (report?.failed ?? [:])
            .map { Failure(name: byId[$0.key] ?? $0.key, reason: $0.value.photoReason) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let stop = preflight ?? report?.stoppedBy
        var details: [String] = []
        switch stop {
        case .disconnected?:
            headline = ExportCopy.disconnected(drive, done: written, total: total)
        case .full?:
            headline = ExportCopy.full(drive, done: written, total: total)
        case .permissionDenied?:
            headline = ExportCopy.cantWrite
        case .notEnoughSpace(let needed, let free)?:
            headline = ExportCopy.notEnoughSpace(folderName, needed: needed, free: free)
        default:
            headline = ExportCopy.exported(written, to: folderName)
            if !failures.isEmpty { details.append(ExportCopy.notExported(failures.count)) }
        }
        if skipped > 0 { details.append(ExportCopy.skipped(skipped) + ".") }
        detail = details.joined(separator: " ")
        isClean = stop == nil && failures.isEmpty && !(report?.wasCancelled ?? false)
        let remaining = plan.map { plan in report.map { $0.remaining(in: plan).count } ?? plan.writtenEntries.count } ?? 0
        offersExportRemaining = (stop?.stopsBatch == true || report?.wasCancelled == true) && remaining > 0
            && stop != .permissionDenied && preflight == nil
        offersRetry = !offersExportRemaining && !failures.isEmpty
        offersAnotherFolder = stop == .permissionDenied
    }
}
