// FS-03.12 AC-3: `Tools/accent-check shot.png [more.png …]` — counts pixels within ±8
// of the dark accent (235,149,38) in the editor command band (top 60pt) and the
// phone panel (below 610pt), skipping the Save button (bottom-right 80×90pt).
// Width is read as 402pt (iPhone 17). `KEEP_SAVE=1` counts Save too, as a sanity check.
import CoreGraphics
import Foundation
import ImageIO

let keepsSave = ProcessInfo.processInfo.environment["KEEP_SAVE"] != nil

func accentPixels(in path: String) -> Int? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let width = image.width, height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    let scale = Double(width) / 402
    let screenHeight = Double(height) / scale
    var hits = 0
    for y in 0..<height {
        let yPoints = Double(y) / scale
        guard yPoints < 60 || yPoints > 610 else { continue }
        let inSaveRows = !keepsSave && yPoints > screenHeight - 90
        for x in 0..<width {
            if inSaveRows && Double(x) / scale > 402 - 80 { continue }
            let i = (y * width + x) * 4
            if abs(Int(data[i]) - 235) <= 8, abs(Int(data[i + 1]) - 149) <= 8, abs(Int(data[i + 2]) - 38) <= 8 {
                hits += 1
            }
        }
    }
    return hits
}

var failures = 0
for path in CommandLine.arguments.dropFirst() {
    let name = path.split(separator: "/").last.map(String.init) ?? path
    guard let hits = accentPixels(in: path) else {
        print("\(name): unreadable")
        failures += 1
        continue
    }
    print("\(name): \(hits) accent px")
    if hits > 0 { failures += 1 }
}
exit(failures == 0 ? 0 : 1)
