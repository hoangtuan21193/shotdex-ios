// FS-07 fixtures: plain-colour JPEGs (no people, no faces — nothing but a
// flat fill) carrying exactly the EXIF an acceptance criterion describes, so a
// simulator's library can be filled with the AC's numbers and Statistics read
// back. Compiled and run by Tools/stats-fixtures.
//
//   stats-fixtures <scenario> <out-dir>
//
// Scenarios mirror docs/02-functional-spec/FS-07-statistics/03-acceptance-criteria.md.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Shot {
    var make: String?
    var model: String?
    var lens: String?
    var focal: Double?
    var focal35: Int?
    var exposure: Double?
    var date: DateComponents
}

/// `count` shots spread over the given months (day 2…27 at noon, so no time
/// zone moves one into a neighbouring month).
func spread(_ count: Int, months: [(year: Int, month: Int)], _ make: (DateComponents) -> Shot) -> [Shot] {
    (0..<count).map { index in
        let slot = months[index % months.count]
        let day = 2 + (index / months.count) % 26
        return make(DateComponents(year: slot.year, month: slot.month, day: day, hour: 12, minute: index % 60))
    }
}

func months(_ count: Int, from year: Int, _ month: Int) -> [(year: Int, month: Int)] {
    (0..<count).map { offset in
        let zeroBased = month - 1 + offset
        return (year + zeroBased / 12, zeroBased % 12 + 1)
    }
}

let iPhone13Main = "iPhone 13 Pro back triple camera 5.7mm f/1.5"
let iPhone13Tele = "iPhone 13 Pro back triple camera 9mm f/2.8"

func scenario(_ name: String) -> (shots: [Shot], plain: Int)? {
    let year = months(10, from: 2025, 12)
    switch name {
    case "ac2":
        // 49 photos with a camera name + 200 EXIF-less PNG "screenshots".
        let shots = spread(49, months: year) {
            Shot(make: "Canon", model: "Canon EOS R6", lens: "RF50mm F1.2 L USM", focal: 50, focal35: 50, exposure: 1.0 / 250, date: $0)
        }
        return (shots, 200)
    case "ac3":
        let main = spread(850, months: year) {
            Shot(make: "Apple", model: "iPhone 13 Pro", lens: iPhone13Main, focal: 5.7, focal35: 26, exposure: 1.0 / 120, date: $0)
        }
        let tele = spread(150, months: year) {
            Shot(make: "Apple", model: "iPhone 13 Pro", lens: iPhone13Tele, focal: 9, focal35: 77, exposure: 1.0 / 120, date: $0)
        }
        return (main + tele, 0)
    case "ac10":
        // 200 with a real focal length, 180 of them from a camera the sensor
        // database does not know (no FocalLenIn35mmFilm to fall back on).
        let unknown = spread(180, months: year) {
            Shot(make: "Mystery", model: "Mystery X1", lens: nil, focal: 23, focal35: nil, exposure: 1.0 / 250, date: $0)
        }
        let known = spread(20, months: year) {
            Shot(make: "Canon", model: "Canon EOS R6", lens: "RF50mm F1.2 L USM", focal: 50, focal35: 50, exposure: 1.0 / 250, date: $0)
        }
        return (unknown + known, 0)
    case "ac12":
        let rf50Slow = spread(150, months: year) {
            Shot(make: "Canon", model: "Canon EOS R6", lens: "RF50mm F1.2 L USM", focal: 50, focal35: 50, exposure: 1.0 / 15, date: $0)
        }
        let rf50 = spread(450, months: year) {
            Shot(make: "Canon", model: "Canon EOS R6", lens: "RF50mm F1.2 L USM", focal: 50, focal35: 50, exposure: 1.0 / 250, date: $0)
        }
        let rf85 = spread(400, months: year) {
            Shot(make: "Canon", model: "Canon EOS R6", lens: "RF85mm F1.2 L USM", focal: 85, focal35: 85, exposure: 1.0 / 250, date: $0)
        }
        return (rf50Slow + rf50 + rf85, 0)
    case "ac17":
        // No lens, no focal length: only the busiest-month sentence can fire.
        var shots: [Shot] = []
        for (month, count) in [(6, 300), (7, 280), (8, 1240), (9, 320)] {
            shots += spread(count, months: [(2026, month)]) {
                Shot(make: "Canon", model: "Canon EOS R6", lens: nil, focal: nil, focal35: nil, exposure: 1.0 / 250, date: $0)
            }
        }
        return (shots, 0)
    default:
        return nil
    }
}

let colours: [(CGFloat, CGFloat, CGFloat)] = [
    (0.85, 0.35, 0.30), (0.30, 0.55, 0.85), (0.35, 0.75, 0.45), (0.90, 0.75, 0.30), (0.55, 0.45, 0.80),
]

func image(colour: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: 48, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    let (r, g, b) = colours[colour % colours.count]
    context.setFillColor(red: r, green: g, blue: b, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
    return context.makeImage()!
}

func write(_ shot: Shot, index: Int, to url: URL) {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    let date = Calendar(identifier: .gregorian).date(from: shot.date)!

    var exif: [CFString: Any] = [
        kCGImagePropertyExifDateTimeOriginal: formatter.string(from: date),
        kCGImagePropertyExifDateTimeDigitized: formatter.string(from: date),
    ]
    if let lens = shot.lens { exif[kCGImagePropertyExifLensModel] = lens }
    if let focal = shot.focal { exif[kCGImagePropertyExifFocalLength] = focal }
    if let focal35 = shot.focal35 { exif[kCGImagePropertyExifFocalLenIn35mmFilm] = focal35 }
    if let exposure = shot.exposure { exif[kCGImagePropertyExifExposureTime] = exposure }
    var tiff: [CFString: Any] = [:]
    if let make = shot.make { tiff[kCGImagePropertyTIFFMake] = make }
    if let model = shot.model { tiff[kCGImagePropertyTIFFModel] = model }

    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: exif,
        kCGImagePropertyTIFFDictionary: tiff,
        kCGImageDestinationLossyCompressionQuality: 0.8,
    ]
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image(colour: index), properties as CFDictionary)
    precondition(CGImageDestinationFinalize(destination), "could not write \(url.path)")
}

func writePlain(index: Int, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image(colour: index), nil)
    precondition(CGImageDestinationFinalize(destination), "could not write \(url.path)")
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let (shots, plain) = scenario(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: stats-fixtures <ac2|ac3|ac10|ac12|ac17> <out-dir>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (index, shot) in shots.enumerated() {
    write(shot, index: index, to: out.appendingPathComponent(String(format: "fs07-%05d.jpg", index)))
}
for index in 0..<plain {
    writePlain(index: index, to: out.appendingPathComponent(String(format: "fs07-plain-%05d.png", index)))
}
print("\(shots.count) JPEG + \(plain) PNG in \(out.path)")
