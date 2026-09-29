import Foundation
import Observation
import ShotDexKit

/// One saved look: a named edit the user can put on any photo.
///
/// Stores a **look-only** recipe — tone, colour, curve, film look — never the
/// crop, masks, markup or drawing. Same cut `EditClipboard` makes and for the
/// same reason it documents: a preset carrying one photo's face mask and 4:5
/// crop would wreck every photo it touched.
struct LookPreset: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var recipe: PhotoEditRecipe
    var createdAt: Date
    /// Made here, or brought in from a preset file (FS-03.14c §6) — what the
    /// "Imported" label reads.
    var source: LookSource = .shotdex
    /// The receive (an import, an opened file) that brought it, so Undo can
    /// take the whole receive back.
    var receiveID: UUID?
    /// The preset file it came from, kept byte for byte beside it (D35) so a
    /// later build can map it again; a file name in the store's folder.
    var originalPresetFile: String?
    /// An imported look's settings the preset named (E6): applying it
    /// changes only those. Nil for a look made here — the whole look cut.
    var namedSettings: Set<LookSettingKey>?

    init(id: UUID = UUID(), name: String, recipe: PhotoEditRecipe, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.recipe = EditorSyncScope.look.apply(recipe, onto: .identity)
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, recipe, createdAt, source, receiveID, originalPresetFile, namedSettings
    }

    /// The fields added with the file store decode as absent when they are,
    /// so one old look is not lost for a field it never had.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        recipe = try container.decode(PhotoEditRecipe.self, forKey: .recipe)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        source = (try? container.decodeIfPresent(LookSource.self, forKey: .source)) ?? .shotdex
        receiveID = try? container.decodeIfPresent(UUID.self, forKey: .receiveID)
        originalPresetFile = try? container.decodeIfPresent(String.self, forKey: .originalPresetFile)
        namedSettings = try? container.decodeIfPresent(Set<LookSettingKey>.self, forKey: .namedSettings)
    }

    /// This look on `recipe`: the whole look cut, or only the named settings.
    func applied(onto recipe: PhotoEditRecipe) -> PhotoEditRecipe {
        EditorSyncScope.applyLook(self.recipe, named: namedSettings, onto: recipe)
    }
}

enum LookSource: String, Codable, Sendable {
    case shotdex, imported
}

/// The user's own looks.
///
/// The 48 film looks are a fixed enum; this is the shelf beside them. Without
/// it, Sync is the only way to reuse an edit and the edit dies with the session
/// — which is why "save this as a preset" is the feature photographers ask for
/// first and the one that makes a shoot's second day faster than its first.
///
/// One JSON file in Application Support plus a folder for the preset files
/// imported looks came from (FS-03.14c §6, D34) — the same shape as the
/// imported-LUT store. User data, so never in `photo_metadata`.
@MainActor
@Observable
final class LookPresetStore {
    private(set) var presets: [LookPreset] = []

    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("looks.json") }
    private var presetNamesURL: URL { directory.appendingPathComponent("preset-names.json") }
    /// Names the user gave built-in film looks (14c §3): only the Presets
    /// panel reads them; the look itself keeps its identity.
    private(set) var presetNames: [String: String] = [:]
    private var originalsDirectory: URL { directory.appendingPathComponent("Originals", isDirectory: true) }

    nonisolated static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Looks", isDirectory: true)
    }

    /// `defaults` is only read once: looks this build kept in `UserDefaults`
    /// before the file store move into the file and the key goes. The app is
    /// unreleased — this keeps a development phone's looks, it is not a
    /// compatibility layer.
    init(directory: URL = LookPresetStore.defaultDirectory(), defaults: UserDefaults = .standard) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path),
           let legacy = defaults.data(forKey: SettingsKeys.lookPresets) {
            presets = Self.decode(legacy)
            persist()
            defaults.removeObject(forKey: SettingsKeys.lookPresets)
        }
        reload()
    }

    func reload() {
        presetNames = (try? Data(contentsOf: presetNamesURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        guard let data = try? Data(contentsOf: fileURL) else {
            presets = []
            return
        }
        presets = Self.decode(data)
    }

    /// A built-in film look's name on the Presets panel.
    func displayName(of filter: PhotoFilter) -> String {
        presetNames[filter.rawValue] ?? filter.displayName
    }

    /// Renames a built-in film look on the panel. Another built-in's name is
    /// refused like a look's; the look's own name puts it back.
    @discardableResult
    func rename(_ filter: PhotoFilter, to name: String) -> RenameRefusal? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }
        let others = PhotoFilter.allCases.filter { $0 != filter }.map(displayName(of:))
        if others.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            var number = 2
            while others.contains(where: { $0.caseInsensitiveCompare("\(trimmed) (\(number))") == .orderedSame }) { number += 1 }
            return .nameTaken(suggestion: "\(trimmed) (\(number))")
        }
        presetNames[filter.rawValue] = trimmed == filter.displayName ? nil : trimmed
        if let data = try? JSONEncoder().encode(presetNames) { try? data.write(to: presetNamesURL, options: .atomic) }
        return nil
    }

    /// One look this build cannot read is dropped on its own; it used to
    /// empty the whole list.
    private static func decode(_ data: Data) -> [LookPreset] {
        let decoded = (try? JSONDecoder().decode(LossyArray<LookPreset>.self, from: data).elements) ?? []
        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    /// Where a look's preset file is kept, when it has one.
    func originalPresetURL(for preset: LookPreset) -> URL? {
        preset.originalPresetFile.map { originalsDirectory.appendingPathComponent($0) }
    }

    /// Puts a look at the front of the shelf, with the bytes of the preset
    /// file it came from beside it (D35). The lower-level half of an import;
    /// naming rules are the caller's.
    func insert(_ preset: LookPreset, original: (data: Data, pathExtension: String)? = nil) {
        var preset = preset
        if let original {
            try? FileManager.default.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
            let name = "\(preset.id.uuidString).\(original.pathExtension)"
            do {
                try original.data.write(to: originalsDirectory.appendingPathComponent(name), options: .atomic)
                preset.originalPresetFile = name
            } catch {
                preset.originalPresetFile = nil
            }
        }
        presets.insert(preset, at: 0)
        persist()
    }

    /// Saves a look under `name`. A name already in use is overwritten rather
    /// than duplicated: "Golden Hour" twice in a strip is two tiles the user
    /// cannot tell apart.
    @discardableResult
    func save(_ recipe: PhotoEditRecipe, name: String) -> LookPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let look = EditorSyncScope.look.apply(recipe, onto: .identity)
        // An identity look is a preset that does nothing; offering it would be
        // a tile that appears to fail.
        guard !look.isIdentity else { return nil }

        var preset = LookPreset(name: trimmed, recipe: look)
        if let existing = presets.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            // Keeps its identity, takes a new timestamp: re-saving a look *is*
            // the newest thing the user did to their looks, and the old date
            // made the strip re-order itself on the next launch for no action
            // the user took.
            preset.id = existing.id
            presets.removeAll { $0.id == existing.id }
        }
        presets.insert(preset, at: 0)
        persist()
        return preset
    }

    /// Why a rename did not happen (FS-03.14c §3, chốt E8).
    enum RenameRefusal: Error, Equatable {
        case emptyName
        /// Another look already has the name; `suggestion` is the first free
        /// "‹name› (2)", "(3)"…
        case nameTaken(suggestion: String)
    }

    /// Renames a look. A name another look already has — any case — is
    /// refused with a free one to offer instead: two tiles with one name are
    /// two tiles the user cannot tell apart. The look's own name, in any
    /// case, is allowed.
    @discardableResult
    func rename(_ preset: LookPreset, to name: String) -> RenameRefusal? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return nil }
        if isTaken(trimmed, except: preset.id) {
            return .nameTaken(suggestion: freeName(like: trimmed, except: preset.id))
        }
        presets[index].name = trimmed
        persist()
        return nil
    }

    private func isTaken(_ name: String, except id: UUID) -> Bool {
        presets.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// `name` is `base`, or `base` with a " (n)" the name rules added — any case.
    static func isName(_ name: String, aVariantOf base: String) -> Bool {
        if name.caseInsensitiveCompare(base) == .orderedSame { return true }
        let prefix = base + " ("
        guard name.count > prefix.count + 1,
              name.lowercased().hasPrefix(prefix.lowercased()),
              name.hasSuffix(")")
        else { return false }
        let digits = name.dropFirst(prefix.count).dropLast()
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    /// "‹name› (n)" with the smallest n ≥ 2 no other look has.
    func freeName(like name: String, except id: UUID) -> String {
        var number = 2
        while isTaken("\(name) (\(number))", except: id) { number += 1 }
        return "\(name) (\(number))"
    }

    /// What adding an imported look did (FS-03.14a §3).
    enum ImportOutcome: Equatable {
        case added(LookPreset)
        /// Same name, same settings: already on the shelf, nothing added.
        case alreadyInMyLooks
    }

    /// Adds a look from a preset file. It never overwrites a look the user
    /// has: a name already taken gets the first free "(n)"; a look with the
    /// same name and the same settings is already here and adds nothing (D50).
    @discardableResult
    func addImported(
        _ recipe: PhotoEditRecipe,
        name: String,
        original: (data: Data, pathExtension: String)? = nil,
        receiveID: UUID? = nil,
        namedSettings: Set<LookSettingKey>? = nil
    ) -> ImportOutcome {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Imported Look" : trimmed
        let look = EditorSyncScope.look.apply(recipe, onto: .identity)
        // The same file imported again: its settings under its name, or the
        // "(n)" name an earlier import of it was given.
        if presets.contains(where: { Self.isName($0.name, aVariantOf: base) && $0.recipe == look }) {
            return .alreadyInMyLooks
        }
        let id = UUID()
        let finalName = isTaken(base, except: id) ? freeName(like: base, except: id) : base
        var preset = LookPreset(id: id, name: finalName, recipe: look)
        preset.source = .imported
        preset.receiveID = receiveID
        preset.namedSettings = namedSettings
        insert(preset, original: original)
        return .added(presets[0])
    }

    /// Deletes a look and the preset file kept beside it.
    func delete(_ preset: LookPreset) {
        if let stored = presets.first(where: { $0.id == preset.id }), let url = originalPresetURL(for: stored) {
            try? FileManager.default.removeItem(at: url)
        }
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    /// Undo of a receive (14c §4): every look it added goes, with the
    /// preset files kept beside them.
    func removeReceive(_ receiveID: UUID) {
        for preset in presets where preset.receiveID == receiveID { delete(preset) }
    }

    /// What a new preset is called before the user types anything. Numbered so
    /// two saves in a row do not collide in the overwrite rule above.
    func suggestedName() -> String {
        var index = presets.count + 1
        var candidate = "Look \(index)"
        while presets.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
            index += 1
            candidate = "Look \(index)"
        }
        return candidate
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
