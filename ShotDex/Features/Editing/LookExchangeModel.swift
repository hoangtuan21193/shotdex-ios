import Foundation
import Observation
import UniformTypeIdentifiers

/// An import of Lightroom presets and looks, as the editor shows it
/// (FS-03.14a §3): the file picker, "Reading 120 of 500" with Cancel, then
/// the report. Nothing is stored until every file is read.
@MainActor
@Observable
final class LookExchangeModel {
    /// The system document picker for Import XMP Preset.
    var isPickingFiles = false
    /// The sheet: while reading it shows progress, then the report.
    var isSheetPresented = false
    private(set) var progress: (read: Int, total: Int)?
    private(set) var report: PresetImportReport?

    private let looks: LookPresetStore
    private let luts: ImportedLUTStore
    private var task: Task<Void, Never>?

    init(looks: LookPresetStore, luts: ImportedLUTStore) {
        self.looks = looks
        self.luts = luts
    }

    /// What the picker offers: every format an import reads (14a §1).
    static var importTypes: [UTType] {
        ["xmp", "lrtemplate", "dng", "shotdexlook", "cube"].compactMap { UTType(filenameExtension: $0) }
    }

    func startImport(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        task?.cancel()
        report = nil
        progress = (0, urls.count)
        isSheetPresented = true
        task = Task { [weak self] in
            let plan = await Task.detached(priority: .userInitiated) { () -> PresetImporter.Plan? in
                let accessed = urls.map { $0.startAccessingSecurityScopedResource() }
                defer { for (url, did) in zip(urls, accessed) where did { url.stopAccessingSecurityScopedResource() } }
                return try? PresetImporter.read(urls) { read, total in
                    Task { @MainActor [weak self] in self?.progress = (read, total) }
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            // Security-scoped access again for the .cube files the stores copy.
            let accessed = urls.map { $0.startAccessingSecurityScopedResource() }
            defer { for (url, did) in zip(urls, accessed) where did { url.stopAccessingSecurityScopedResource() } }
            guard let plan else {
                isSheetPresented = false
                progress = nil
                return
            }
            report = PresetImporter.apply(plan, looks: looks, luts: luts)
            progress = nil
        }
    }

    /// Cancel adds nothing: the stores are only written once reading is done.
    func cancelImport() {
        task?.cancel()
        task = nil
        progress = nil
        report = nil
        isSheetPresented = false
    }

    func dismissReport() {
        isSheetPresented = false
        report = nil
    }

    #if DEBUG
    /// `-ShotDexImportFixtures`: a UI script cannot drive the document
    /// picker, so this launch argument imports three presets written here —
    /// one of each outcome — the first time My Looks is shown.
    private var hasImportedFixtures = false

    func importFixturesIfAsked() {
        guard !hasImportedFixtures, ProcessInfo.processInfo.arguments.contains("-ShotDexImportFixtures") else { return }
        hasImportedFixtures = true
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("preset-fixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func xmp(_ attributes: String, name: String) -> String {
            """
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:Version="15.4" \(attributes)>
            <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">\(name)</rdf:li></rdf:Alt></crs:Name>
            </rdf:Description></rdf:RDF></x:xmpmeta>
            """
        }
        let files: [(String, String)] = [
            ("Golden.xmp", xmp(#"crs:Exposure2012="+0.50" crs:HueAdjustmentRed="-20""#, name: "Golden")),
            ("Matte Fade.xmp", xmp(#"crs:Exposure2012="+3.00" crs:HasCrop="True" crs:CropTop="0.1" crs:Contrast2012="-30""#, name: "Matte Fade")),
            ("Broken.xmp", "<x:xmpmeta><rdf:RDF><unclosed>"),
        ]
        let urls = files.map { name, text in
            let url = folder.appendingPathComponent(name)
            try? Data(text.utf8).write(to: url)
            return url
        }
        startImport(urls)
    }
    #endif
}
