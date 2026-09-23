import Foundation
import ImageIO
import ShotDexKit

/// What EXIF says about the lens and body, pulled out of the ImageIO
/// properties once.
struct LensQuery: Equatable, Sendable {
    var cameraMake: String?
    var cameraModel: String?
    var lensMake: String?
    var lensModel: String?
    /// Shortest and longest focal length, and the widest aperture at the
    /// short end — EXIF LensSpecification, or parsed from the lens name.
    var spec: LensSpec?
    var focal: Double?
    var focal35: Double?

    init(
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensMake: String? = nil,
        lensModel: String? = nil,
        spec: LensSpec? = nil,
        focal: Double? = nil,
        focal35: Double? = nil
    ) {
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensMake = lensMake
        self.lensModel = lensModel
        self.spec = spec ?? lensModel.flatMap(LensSpec.parse)
        self.focal = focal
        self.focal35 = focal35
    }

    init(properties: [CFString: Any]) {
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let aux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let lensModel = (exif[kCGImagePropertyExifLensModel] as? String)
            ?? (aux[kCGImagePropertyExifAuxLensModel] as? String)
        let numbers = (exif[kCGImagePropertyExifLensSpecification] as? [NSNumber])
            ?? (aux[kCGImagePropertyExifAuxLensInfo] as? [NSNumber])
        var spec: LensSpec?
        if let numbers, numbers.count >= 2, numbers[0].doubleValue > 0 {
            let aperture = numbers.count >= 3 ? numbers[2].doubleValue : 0
            spec = LensSpec(
                minFocal: numbers[0].doubleValue,
                maxFocal: numbers[1].doubleValue,
                aperture: aperture > 0 ? aperture : nil
            )
        }
        self.init(
            cameraMake: tiff[kCGImagePropertyTIFFMake] as? String,
            cameraModel: tiff[kCGImagePropertyTIFFModel] as? String,
            lensMake: exif[kCGImagePropertyExifLensMake] as? String,
            lensModel: lensModel,
            spec: spec,
            focal: (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue,
            focal35: (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.doubleValue
        )
    }
}

/// Focal range and widest aperture, the part of a lens name every maker
/// writes the same way ("16-35mm f/4", "16.0-35.0 mm f/4.0", "EF24-70mm f/2.8L").
struct LensSpec: Equatable, Sendable {
    var minFocal: Double
    var maxFocal: Double
    var aperture: Double?

    static func parse(_ name: String) -> LensSpec? {
        let text = name.lowercased()
        guard let focal = text.firstMatch(of: /(\d+(?:\.\d+)?)\s*(?:-\s*(\d+(?:\.\d+)?))?\s*mm/),
              let minFocal = Double(focal.1)
        else { return nil }
        let maxFocal = focal.2.flatMap { Double($0) } ?? minFocal
        var aperture: Double?
        // "f" on its own or right after "mm" ("XF35mmF1.4"), never inside a
        // word — "EF24-70mm" is a mount prefix, not f/24.
        if let match = text.firstMatch(of: /(?:^|[^a-z]|mm)f\s*\/?\s*(\d+(?:\.\d+)?)/) {
            aperture = Double(match.1)
        } else if let match = text.firstMatch(of: /1\s*:\s*(\d+(?:\.\d+)?)/) {
            aperture = Double(match.1)
        }
        return LensSpec(minFocal: minFocal, maxFocal: maxFocal, aperture: aperture)
    }

    func matches(_ other: LensSpec) -> Bool {
        guard abs(minFocal - other.minFocal) <= 0.6, abs(maxFocal - other.maxFocal) <= 0.6 else { return false }
        guard let aperture, let otherAperture = other.aperture else { return true }
        return abs(aperture - otherAperture) <= 0.15
    }
}

/// The lens profile ShotDex found for a photo.
struct LensProfileMatch: Equatable, Sendable {
    var lens: LensfunLens
    var cameraCropFactor: Double
    /// Other rows that fit as well — shown so a wrong guess is one tap away.
    var alternatives: Int
}

/// Matches EXIF to a row of the embedded Lensfun table.
///
/// The name is the weakest signal: Nikon writes "16.0-35.0 mm f/4.0" for every
/// 16-35 f/4 it has ever made, Canon writes "EF24-70mm f/2.8L II USM", Lensfun
/// writes "Nikon AF-S Nikkor 16-35mm f/4G ED VR". So the match narrows by what
/// is written the same everywhere — focal range and widest aperture — then by
/// the body's mount and the maker, and only then lets name tokens break a tie.
/// Nothing is corrected in the table itself: it stays Lensfun's (CC-BY-SA).
struct LensProfileMatcher {
    let library: LensProfileLibrary

    init(library: LensProfileLibrary = .shared) {
        self.library = library
    }

    func match(_ query: LensQuery) -> LensProfileMatch? {
        guard let spec = query.spec else { return nil }
        let camera = library.camera(make: query.cameraMake, model: query.cameraModel)
        var candidates = library.lenses.filter { lens in
            guard let lensSpec = LensSpec.parse(lens.model) else { return false }
            return lensSpec.matches(spec)
        }
        guard !candidates.isEmpty else { return nil }

        if let mount = camera?.mount {
            let onMount = candidates.filter { $0.mounts.contains(mount) }
            if !onMount.isEmpty { candidates = onMount }
        }
        if let brand = Self.brand(query.lensMake ?? query.cameraMake) {
            let sameBrand = candidates.filter { Self.brand($0.maker) == brand }
            if !sameBrand.isEmpty { candidates = sameBrand }
        }

        let queryTokens = Self.tokens(query.lensModel ?? "")
        let scored = candidates.map { lens in
            let best = lens.aliases.map { Self.overlap(queryTokens, Self.tokens($0)) }.max() ?? 0
            return (lens: lens, score: best)
        }
        guard let top = scored.max(by: { lhs, rhs in
            lhs.score != rhs.score ? lhs.score < rhs.score : lhs.lens.model > rhs.lens.model
        }) else { return nil }

        let cameraCrop = camera?.cropFactor
            ?? query.focal35.flatMap { f35 in query.focal.map { f35 / $0 } }
            ?? 1
        return LensProfileMatch(
            lens: top.lens,
            cameraCropFactor: cameraCrop,
            alternatives: scored.filter { $0.score == top.score }.count - 1
        )
    }

    /// The crop factor for a manual pick: the body's, if Lensfun knows it.
    func cameraCropFactor(_ query: LensQuery) -> Double {
        library.camera(make: query.cameraMake, model: query.cameraModel)?.cropFactor
            ?? query.focal35.flatMap { f35 in query.focal.map { f35 / $0 } }
            ?? 1
    }

    /// "NIKON CORPORATION" → "nikon", "OLYMPUS IMAGING CORP." → "olympus".
    static func brand(_ maker: String?) -> String? {
        guard let first = maker?.lowercased().split(whereSeparator: { !$0.isLetter }).first else { return nil }
        return String(first)
    }

    /// Letters and numbers as separate tokens, so "EF24-70mm" and
    /// "EF 24-70mm" read the same.
    static func tokens(_ name: String) -> Set<String> {
        Set(name.lowercased().matches(of: /[a-z]+|\d+(?:\.\d+)?/).map { String($0.output) })
    }

    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Int {
        a.intersection(b).count
    }
}
