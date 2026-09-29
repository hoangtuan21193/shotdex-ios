import Foundation
import ShotDexKit

/// One import (FS-03.14a): read every picked file off the main actor, then
/// write the stores once when the whole lot is read — so Cancel and Undo mean
/// the same thing: nothing, or all of it.
enum PresetImporter {
    /// What reading produced, before anything is stored.
    struct Plan {
        struct Look {
            var name: String
            var recipe: PhotoEditRecipe
            var namedSettings: Set<LookSettingKey>?
            var original: (data: Data, pathExtension: String)?
            var lines: [PresetReportLine]
            var status: PresetImportReport.Status
            /// A LUT a `.shotdexlook` carries, added with the look.
            var embeddedLUT: LookFile.EmbeddedLUT?
        }

        struct LUT {
            var name: String
            var url: URL
        }

        var looks: [Look] = []
        var luts: [LUT] = []
        /// Files that did not become anything, with why.
        var skipped: [PresetImportReport.Entry] = []
    }

    enum Cancelled: Error { case cancelled }

    /// Reads `urls` in order. `progress(read, total)` after each file; throws
    /// `Cancelled` between files once the task is cancelled.
    static func read(_ urls: [URL], progress: (Int, Int) -> Void = { _, _ in }) throws -> Plan {
        var plan = Plan()
        for (index, url) in urls.enumerated() {
            if Task.isCancelled { throw Cancelled.cancelled }
            defer { progress(index + 1, urls.count) }
            let fileName = url.deletingPathExtension().lastPathComponent
            guard plan.looks.count < PresetImportLimits.maximumPresetsPerImport else {
                plan.skipped.append(.init(name: fileName, status: .skipped, lines: [.init(kind: .skipped, text: "Import the rest separately")]))
                continue
            }
            let kind: PresetImportLimits.Kind
            switch PresetImportLimits.check(url) {
            case let .success(found): kind = found
            case let .failure(refusal):
                plan.skipped.append(.init(name: fileName, status: .skipped, lines: [.init(kind: .skipped, text: refusal.message)]))
                continue
            }
            if kind == .cube {
                plan.luts.append(.init(name: fileName, url: url))
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                plan.looks.append(try look(from: data, kind: kind, fileName: fileName, pathExtension: url.pathExtension))
            } catch {
                plan.skipped.append(.init(name: fileName, status: .skipped, lines: [.init(kind: .skipped, text: message(for: error))]))
            }
        }
        return plan
    }

    private static func look(from data: Data, kind: PresetImportLimits.Kind, fileName: String, pathExtension: String) throws -> Plan.Look {
        if kind == .shotdexlook {
            let file = try LookFileCodec.decode(data)
            let named = file.namedSettings.map { Set($0.map(LookSettingKey.init(rawValue:))) }
            return Plan.Look(
                name: name(file.name, fallback: fileName), recipe: file.look, namedSettings: named,
                original: nil, lines: [], status: .added, embeddedLUT: file.lut
            )
        }
        let settings: LightroomSettings = switch kind {
        case .xmp: try LightroomXMPReader.read(data)
        case .lrtemplate: try LightroomTemplateReader.read(data)
        default: try PresetDNGReader.read(data: data)
        }
        let result = LightroomMapping.map(settings)
        let status = PresetImportReport.status(applied: result.appliedCount, lines: result.lines)
        return Plan.Look(
            name: name(settings.name, fallback: fileName),
            recipe: result.recipe,
            namedSettings: result.namedSettings,
            original: kind == .dng ? nil : (data, pathExtension.lowercased()),
            lines: result.lines,
            status: status,
            embeddedLUT: nil
        )
    }

    /// The preset's own name, else the file's — trimmed, 60 characters at
    /// most; a `$$$/…` localisation key is not a name (14a §4).
    static func name(_ presetName: String?, fallback: String) -> String {
        var candidate = presetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if candidate.isEmpty || candidate.hasPrefix("$$$/") { candidate = fallback }
        return String(candidate.prefix(60))
    }

    static func message(for error: any Error) -> String {
        switch error {
        case let failure as LightroomXMPReader.Failure: failure.message
        case let failure as LightroomTemplateReader.Failure: failure.message
        case let failure as PresetDNGReader.Failure: failure.message
        case let failure as LookFileError: failure.message
        case let refusal as PresetImportLimits.Refusal: refusal.message
        default: "The file couldn't be read"
        }
    }

    /// Writes a read plan into the stores, in file order at the front of My
    /// Looks, and says what happened. `receiveID` ties the lot together for
    /// Undo.
    @MainActor
    static func apply(
        _ plan: Plan,
        looks store: LookPresetStore,
        luts: ImportedLUTStore?,
        receiveID: UUID = UUID()
    ) -> PresetImportReport {
        var entries: [PresetImportReport.Entry] = []
        var added: [PresetImportReport.Entry] = []
        // Reverse, so the first file ends up first.
        for look in plan.looks.reversed() {
            guard look.status != .skipped else {
                added.insert(.init(name: look.name, status: .skipped, lines: look.lines), at: 0)
                continue
            }
            var recipe = look.recipe
            if let embedded = look.embeddedLUT, let luts {
                recipe.lutID = (try? luts.add(text: embedded.cube, name: embedded.name, receiveID: receiveID))?.id
            }
            let outcome = store.addImported(
                recipe, name: look.name, original: look.original, receiveID: receiveID, namedSettings: look.namedSettings
            )
            switch outcome {
            case let .added(preset):
                added.insert(.init(name: preset.name, status: look.status, lines: look.lines), at: 0)
            case .alreadyInMyLooks:
                added.insert(.init(name: look.name, status: .skipped, lines: [.init(kind: .skipped, text: "Already in My Looks")]), at: 0)
            }
        }
        entries += added
        for lut in plan.luts {
            do {
                let stored = try luts?.add(from: lut.url, receiveID: receiveID)
                entries.append(.init(name: stored?.displayName ?? lut.name, status: .added, lines: [.init(kind: .applied, text: "Added to LUTs")]))
            } catch {
                entries.append(.init(name: lut.name, status: .skipped, lines: [.init(kind: .skipped, text: LUTImportMessage.text(for: error))]))
            }
        }
        entries += plan.skipped
        return PresetImportReport(entries: entries)
    }
}
