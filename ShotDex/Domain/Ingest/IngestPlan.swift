import Foundation

/// The folders a card import files photos into, under the destination
/// source (FS-20 §6): literal folders and the tokens `{year}` and `{date}`,
/// from the day the photo was taken — `RAW/{year}/{date}` is
/// `RAW/2026/2026-10-03`, the same days as Export's Date Folders.
struct IngestFolderTemplate: Sendable, Hashable, Codable {
    var pattern: String

    static let yearDate = IngestFolderTemplate(pattern: "{year}/{date}")

    func folder(for date: Date, timeZone: TimeZone = .current) -> String {
        let day = ServerUploadPath.dayFolder(folder: "", captureDate: date, timeZone: timeZone)
        let year = String(day.prefix(4))
        let date = String(day.suffix(10))
        let filled = pattern.replacingOccurrences(of: "{year}", with: year).replacingOccurrences(of: "{date}", with: date)
        return filled.split(separator: "/").map { FileNameTemplate.cleaned(String($0)) }.filter { !$0.isEmpty }.joined(separator: "/")
    }
}

/// Every name of a card import, worked out before the first byte (FS-20
/// §7.1) by Export's own planner (FS-03.07b §5–6): the shared name tokens,
/// Keep Both always — an import never writes over a file — and the
/// import's own folders.
enum IngestPlan {
    /// A card tile as Export sees an asset: its files in the order they are
    /// copied, the primary first.
    static func exportItem(_ item: CardItem, camera: String? = nil, lens: String? = nil, now: Date = Date()) -> FileExportItem {
        let files = item.files.enumerated().map { index, file in
            let role: FileExportSourceFile.Role = switch (item.kind, index) {
            case (.video, _): .video
            case (_, 0): .photo
            case _ where CardCatalog.audioExtensions.contains(file.pathExtension): .audio
            default: .alternatePhoto
            }
            return FileExportSourceFile(key: file.path, filename: file.name, role: role,
                                        isRAW: PairingRule.isRaw(file.name), byteCount: file.size)
        }
        return FileExportItem(id: item.id, filename: item.primary.name, captureDate: item.date ?? now,
                              camera: camera, lens: lens, kind: item.kind == .video ? .video : .photo, files: files)
    }

    /// - Parameter existing: the names already in each folder of the
    ///   destination, read once (`folders(for:)` says which).
    static func make(
        _ items: [FileExportItem],
        template: FileNameTemplate,
        folders: IngestFolderTemplate,
        existing: [String: Set<String>],
        timeZone: TimeZone = .current
    ) -> FileExportPlan {
        FileExportPlan.make(
            items: items, mode: .unmodifiedOriginal, template: template, policy: .keepBoth,
            dateFolders: false, includesLivePhotoVideo: true, renderExtension: { _ in "" },
            existing: existing, timeZone: timeZone,
            folderFor: { folders.folder(for: $0.captureDate, timeZone: timeZone) }
        )
    }

    static func folders(for items: [FileExportItem], template: IngestFolderTemplate, timeZone: TimeZone = .current) -> [String] {
        Array(Set(items.map { template.folder(for: $0.captureDate, timeZone: timeZone) })).sorted()
    }
}
