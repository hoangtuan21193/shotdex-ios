import Foundation

/// Whether the system RAW decoder on this iOS build reads a camera's files
/// (FS-03.04b §2). Judged per camera × iOS build, never per photo.
enum RAWDecoderVerdict: String, Codable, Sendable {
    case readable
    /// Two of the camera's files on the device were tried and both refused
    /// (one, when the camera has only one) — or the editor was refused while
    /// the camera was still `unknown`.
    case unreadable
    /// Every file of the camera is only in iCloud: nothing was tried, and
    /// nothing is marked. Unknown is never unsupported.
    case unknown
}

/// Where a verdict came from (FS-03.04b §5).
enum RAWVerdictSource: String, Codable, Sendable {
    /// The camera is on the decoder's published list.
    case list
    /// A file on the device was tried.
    case file
    /// The editor opened one of its files.
    case editor
}

/// A camera as the index names it: the normalized manufacturer and model
/// (BD-05). `key` is what the verdict table stores.
struct RAWCamera: Hashable, Sendable {
    let manufacturer: String?
    let model: String

    init?(manufacturer: String?, model: String?) {
        guard let model = model?.trimmingCharacters(in: .whitespaces), !model.isEmpty else { return nil }
        let make = manufacturer?.trimmingCharacters(in: .whitespaces)
        self.manufacturer = make?.isEmpty == false ? make : nil
        self.model = model
    }

    /// `manufacturer|model`, the verdict table's camera column — the same
    /// expression `RAWVerdictStore` builds in SQL from the index's columns.
    var key: String { "\(manufacturer ?? "")|\(model)" }

    /// "Sony ILCE-7M5": what the messages say.
    var displayName: String {
        guard let manufacturer else { return model }
        return "\(manufacturer) \(model)"
    }
}

/// Matches EXIF names against `CIRAWFilter.supportedCameraModels`, which
/// spells them its own way (measured 2026-10-02 on iOS 26.5, 930 entries):
/// "Nikon Z 6 2" for `NIKON Z 6_2`, "Sony Alpha ILCE-7M4" for `SONY`
/// `ILCE-7M4`, "Fujifilm X-T4" for `FUJIFILM` `X-T4`. A match only ever says
/// "readable"; a miss sends the camera on to a file on the device, so a loose
/// miss costs one probe and never a wrong mark.
struct RAWCameraMatcher: Sendable {
    private let keys: Set<String>

    init(supportedModels: [String]) {
        var keys = Set<String>()
        for entry in supportedModels {
            let words = entry.split(separator: " ").map(String.init)
            guard !words.isEmpty else { continue }
            keys.insert(Self.key(words))
            // Without its manufacturer: "X-T4", "Alpha ILCE-7M4".
            if words.count > 1 { keys.insert(Self.key(Array(words.dropFirst()))) }
            // Sony's lists put "Alpha" before the model EXIF carries alone.
            let noAlpha = words.filter { $0.lowercased() != "alpha" }
            if noAlpha.count != words.count {
                keys.insert(Self.key(noAlpha))
                if noAlpha.count > 1 { keys.insert(Self.key(Array(noAlpha.dropFirst()))) }
            }
        }
        self.keys = keys.subtracting([""])
    }

    /// `make` and `model` are as EXIF has them or as the index normalized
    /// them; either works.
    func isListed(make: String?, model: String?) -> Bool {
        guard let model, !model.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let normalizedMake = CameraNormalizer.normalizeManufacturer(make)
        let bareModel = CameraNormalizer.normalizeModel(model, manufacturer: make) ?? model
        var candidates: Set<String> = [Self.key([model]), Self.key([bareModel])]
        if let normalizedMake {
            candidates.insert(Self.key([normalizedMake, bareModel]))
        }
        return !candidates.isDisjoint(with: keys)
    }

    private static func key(_ words: [String]) -> String {
        CameraNormalizer.lookupKey(words.joined(separator: " "))
    }
}

/// The three steps of FS-03.04b §2, stopping at the first that answers.
enum RAWVerdictRules {
    /// How many of a camera's files on the device are tried before it is
    /// called unreadable: one odd file must not mark a whole camera (Q5).
    static let filesTried = 2

    /// - Parameters:
    ///   - listed: the camera is on the decoder's list.
    ///   - nextLocalFileDecodes: tries the camera's next file that is on the
    ///     device — `true` decoded, `false` refused — or `nil` when there is
    ///     none left. Never downloads.
    static func judge(
        listed: Bool,
        nextLocalFileDecodes: () async -> Bool?
    ) async -> (verdict: RAWDecoderVerdict, source: RAWVerdictSource?) {
        if listed { return (.readable, .list) }
        var refused = 0
        while refused < filesTried, let decodes = await nextLocalFileDecodes() {
            if decodes { return (.readable, .file) }
            refused += 1
        }
        return refused == 0 ? (.unknown, nil) : (.unreadable, .file)
    }

    /// What the editor's own attempt does to a stored verdict: it settles an
    /// unknown camera either way; a readable camera stays readable when one
    /// odd file fails (only that file reports it), and an unreadable one
    /// that opened is readable after all.
    static func afterEditor(_ stored: RAWDecoderVerdict?, decoded: Bool) -> RAWDecoderVerdict? {
        switch (stored, decoded) {
        case (.unknown, false), (nil, false): .unreadable
        case (.unknown, true), (nil, true), (.unreadable, true): .readable
        case (.readable, _), (.unreadable, false): nil
        }
    }
}
