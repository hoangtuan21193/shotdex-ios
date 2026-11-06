import Foundation

/// The words under a smart album's conditions while the on-server check
/// runs (FS-19.07 §7): `Checking · 12,408 of 54,920 · 38 GB to download`,
/// the reason it waits, or `Checked 3 min ago` once it is done.
enum OnServerProgressLine {
    /// Which device the words are on — the one that reads again what another
    /// device got wrong.
    enum ThisDevice: Equatable, Sendable { case iPhone, iPad, mac }

    struct Input: Equatable, Sendable {
        var progress: OnServerProgress
        var wait: OnServerSchedule.Wait?
        var finishedAt: Date?
        var sourceName: String
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
        let counts = String(localized: "\(p.checked.formatted()) of \(p.total.formatted())",
                            comment: "On-server check: items checked of all items")
        var first: String
        if let wait = input.wait {
            first = "\(text(for: wait)) · \(counts)"
        } else if p.checked >= p.total, let finishedAt = input.finishedAt {
            let ago = finishedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            first = String(localized: "Checked \(ago)", comment: "On-server check: done, and when; e.g. Checked 3 min ago")
        } else {
            first = String(localized: "Checking · \(counts)", comment: "On-server check: running; e.g. Checking · 12,408 of 54,920")
            if p.bytesToDownload > 0 {
                let bytes = p.bytesToDownload.formatted(.byteCount(style: .file))
                first += " · " + String(localized: "\(bytes) to download", comment: "On-server check: what is left to download from iCloud")
            }
        }
        var out = [first]
        if !input.mismatchFrom.isEmpty {
            out.append(mismatch(input.mismatchFrom, on: input.thisDevice))
        }
        if p.editedOnlyMissing > 0 {
            out.append(String(localized: "\(p.editedOnlyMissing.formatted()) Edited — edit not on \(input.sourceName)",
                              comment: "On-server check: items edited in Photos whose edit is not on the server"))
        }
        if input.isLimited {
            out.append(String(localized: "Only photos ShotDex can access are checked.",
                              comment: "On-server check: Photos access is limited"))
        }
        return out
    }

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
        }
    }
}
