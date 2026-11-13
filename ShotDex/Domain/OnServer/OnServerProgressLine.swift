import Foundation

/// The words under a smart album's conditions while the on-server check
/// runs (FS-19.07 §7): `38 photos left to check on WIN › Photos`, the
/// reason it waits, or `Checked 3 min ago` once it is done. One number per
/// line, and the place it counts on named (user 2026-11-08: the album and
/// Activity showed different counts with nothing saying they counted
/// different folders; "too many numbers").
enum OnServerProgressLine {
    /// Which device the words are on — the one that reads again what another
    /// device got wrong.
    enum ThisDevice: Equatable, Sendable { case iPhone, iPad, mac }

    struct Input: Equatable, Sendable {
        var progress: OnServerProgress
        var wait: OnServerSchedule.Wait?
        var finishedAt: Date?
        var sourceName: String
        /// The folder of the source the count is on; nil or empty for all of it.
        var folder: String? = nil
        /// Photos access is `.limited`.
        var isLimited = false
        /// Devices whose hashes the random check found wrong (§12.4), by
        /// name; nil for one that sent none.
        var mismatchFrom: [String?] = []
        var thisDevice: ThisDevice
    }

    /// One line per fact, top first.
    static func lines(_ input: Input, now: Date = Date()) -> [String] {
        let p = input.progress
        let left = max(0, p.total - p.checked)
        let first: String
        if let wait = input.wait {
            first = left > 0 ? "\(text(for: wait)) · \(photosLeft(left))" : text(for: wait)
        } else if left == 0, let finishedAt = input.finishedAt {
            let ago = finishedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            first = String(localized: "Checked \(ago)", comment: "On-server check: done, and when; e.g. Checked 3 min ago")
        } else {
            first = words(AttributedString(localized: "^[\(left) photo](inflect: true) left to check on \(scope(input))",
                                           comment: "On-server check: running; photos with no answer yet, and the server (› folder) counted on, e.g. 38 photos left to check on WIN › Photos"))
        }
        var out = [first]
        if !input.mismatchFrom.isEmpty {
            out.append(mismatch(input.mismatchFrom, on: input.thisDevice))
        }
        if p.editedOnlyMissing > 0 {
            out.append(words(AttributedString(localized: "^[\(p.editedOnlyMissing) edited photo](inflect: true) without the edit on \(input.sourceName)",
                                              comment: "On-server check: photos edited in Photos whose original is on the server but whose edit is not, e.g. 136 edited photos without the edit on WIN")))
        }
        if input.isLimited {
            out.append(String(localized: "Only photos ShotDex can access are checked.",
                              comment: "On-server check: Photos access is limited"))
        }
        return out
    }

    /// `19,443 photos left`, after a wait.
    static func photosLeft(_ count: Int) -> String {
        words(AttributedString(localized: "^[\(count) photo](inflect: true) left",
                                comment: "On-server check: photos with no answer yet, after the reason it waits, e.g. Waiting for Wi-Fi · 38 photos left"))
    }

    /// The folder of a server source the smart albums ask about, when they
    /// all ask about the same one — what the sidebar foot and Activity count
    /// on, so they show the album's number (user 2026-11-09: "38 left" in the
    /// album, "17,875 left" in the sidebar). Nil (the whole source) when no
    /// album asks, or albums ask about different folders.
    static func albumFolder(_ queries: [SmartAlbumQuery], sourceId: String) -> String? {
        let rules = queries.flatMap { $0.cleaned.allRules }
            .filter { ($0.field == .alsoOnServer || $0.field == .source) && $0.text == sourceId }
        func key(_ folder: String?) -> String {
            (folder ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
        }
        guard Set(rules.map { key($0.folder) }).count == 1, let first = rules.first, !key(first.folder).isEmpty else { return nil }
        return first.folder
    }

    /// `WIN` or `WIN › Photos › 2025`.
    static func scope(_ input: Input) -> String {
        let parts = (input.folder ?? "").split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return ([input.sourceName] + parts).joined(separator: " › ")
    }

    private static func words(_ text: AttributedString) -> String { String(text.characters) }

    /// `Hashes from Tuấn's MacBook didn't match — checking on this iPhone.`
    static func mismatch(_ names: [String?], on device: ThisDevice) -> String {
        let named = names.map {
            $0 ?? String(localized: "another device",
                         comment: "On-server check: stands for a device's name after \"Hashes from\" when the device sent none")
        }
        let from = Array(Set(named)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.formatted(.list(type: .and))
        // Three whole sentences, not one with a device word: "this iPhone /
        // iPad / Mac" takes a different form in languages with gender.
        return switch device {
        case .iPhone: String(localized: "Hashes from \(from) didn't match — checking on this iPhone.",
                             comment: "On-server check, a caption that may wrap to two lines: another device's file hashes were wrong and this iPhone reads the files itself. The argument is one or more device names as a list, e.g. \"Tuấn's MacBook and iPad\".")
        case .iPad: String(localized: "Hashes from \(from) didn't match — checking on this iPad.",
                           comment: "On-server check, a caption that may wrap to two lines: another device's file hashes were wrong and this iPad reads the files itself. The argument is one or more device names as a list, e.g. \"Tuấn's MacBook and iPhone\".")
        case .mac: String(localized: "Hashes from \(from) didn't match — checking on this Mac.",
                          comment: "On-server check, a caption that may wrap to two lines: another device's file hashes were wrong and this Mac reads the files itself. The argument is one or more device names as a list, e.g. \"Tuấn's iPhone and iPad\".")
        }
    }

    static func text(for wait: OnServerSchedule.Wait) -> String {
        switch wait {
        case .wifi: String(localized: "Waiting for Wi‑Fi", comment: "On-server check: waits for Wi-Fi")
        case .charging: String(localized: "Waiting to Charge", comment: "On-server check: waits for power")
        case .space: String(localized: "Waiting for space", comment: "On-server check: less than 2 GB would be left free")
        case .unreachable(let name): String(localized: "\(name) isn't reachable", comment: "On-server check: the server did not answer")
        case .openApp: String(localized: "Open ShotDex to continue", comment: "On-server check: runs only while ShotDex is open")
        case .iCloudRefusing: String(localized: "iCloud isn't sending originals · trying again soon",
                                     comment: "On-server check: iCloud refused every download of a batch; the check waits and tries again")
        }
    }
}
