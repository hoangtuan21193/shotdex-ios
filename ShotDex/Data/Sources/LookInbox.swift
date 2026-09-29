import Foundation

/// Looks that arrive from outside the app (FS-03.14c §4): a `.shotdexlook`
/// opened from AirDrop, Files, Messages or Mail. Each file is **copied** in,
/// imported through the same reader as Import, and the copy deleted whether
/// it worked or not (D44). A file that is still here when the app starts —
/// the app was killed mid-import — is imported then, once.
@MainActor
final class LookInbox {
    private let looks: LookPresetStore
    private let luts: ImportedLUTStore?
    private let banner: AppBannerModel
    private let directory: URL
    private var isDraining = false
    private var drainsAgain = false

    nonisolated static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LookInbox", isDirectory: true)
    }

    init(looks: LookPresetStore, luts: ImportedLUTStore?, banner: AppBannerModel, directory: URL = LookInbox.defaultDirectory()) {
        self.looks = looks
        self.luts = luts
        self.banner = banner
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Files waiting, oldest first.
    var pending: [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        )) ?? []
        return folders
            .sorted { creation($0) < creation($1) }
            .compactMap { folder in
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))?.first
            }
    }

    /// An opened file: copied in, then imported.
    @discardableResult
    func receive(_ url: URL) async -> PresetImportReport? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            banner.show("Couldn't open \(url.lastPathComponent)")
            return nil
        }
        // iOS hands a document over in Documents/Inbox; it is ours to delete.
        if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
        return await drain()
    }

    /// Imports every file waiting as one receive, shows its banner and
    /// empties the inbox. A receive that lands while this runs goes next.
    @discardableResult
    func drain() async -> PresetImportReport? {
        guard !isDraining else {
            drainsAgain = true
            return nil
        }
        isDraining = true
        defer { isDraining = false }
        var last: PresetImportReport?
        repeat {
            drainsAgain = false
            let files = pending
            guard !files.isEmpty else { break }
            let plan = await Task.detached(priority: .userInitiated) { try? PresetImporter.read(files) }.value
            for file in files { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            guard let plan else { continue }
            let receiveID = UUID()
            let report = PresetImporter.apply(plan, looks: looks, luts: luts, receiveID: receiveID)
            announce(report, receiveID: receiveID)
            last = report
        } while drainsAgain
        return last
    }

    /// Undo on the banner: every look and LUT the receive added.
    func undo(_ receiveID: UUID) {
        looks.removeReceive(receiveID)
        luts?.removeReceive(receiveID)
    }

    private func announce(_ report: PresetImportReport, receiveID: UUID) {
        let message = Self.bannerMessage(for: report)
        if message.showsDetails {
            banner.show(message.text, actionTitle: "Details") { [weak banner] in banner?.presentedReport = report }
        } else {
            banner.show(message.text, actionTitle: "Undo") { [weak self] in self?.undo(receiveID) }
        }
    }

    /// "Golden added to My Looks" · Undo when everything came in as it was;
    /// "3 looks added · 1 skipped" · Details when anything was ≈ or ✕.
    static func bannerMessage(for report: PresetImportReport) -> (text: String, showsDetails: Bool) {
        let clean = report.entries.allSatisfy { $0.status == .added }
        if report.entries.count == 1, let entry = report.entries.first {
            switch entry.status {
            case .added:
                let toLUTs = entry.lines.contains { $0.text == "Added to LUTs" }
                return ("\(entry.name) added to \(toLUTs ? "LUTs" : "My Looks")", false)
            case .addedWithChanges: return ("\(entry.name) added with changes", true)
            case .skipped: return ("\(entry.name) not added", true)
            }
        }
        return (report.header, !clean)
    }

    private func creation(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}
