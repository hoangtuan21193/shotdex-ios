import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Photo A of FS-08.06 §7, generated rather than shipped: a noise image (so a
/// re-encode shows in the decoded pixels) carrying a GPS position, the camera,
/// the lens, the exposure, the capture date, the author and a Lightroom-style
/// XMP packet that repeats the coordinate and names the place. No face, no
/// real photo — every byte is made here.
enum MetadataFixture {
    static let latitude = 10.7769
    static let longitude = 106.7009
    static let make = "SONY"
    static let model = "ILCE-7M4"
    static let lens = "FE 24-70mm F2.8 GM II"
    static let iso = 400
    static let captureDate = "2026:09:20 17:05:00"
    static let artist = "Nguyen An"
    static let copyright = "© 2026 Nguyen An"
    static let city = "Ho Chi Minh City"
    static let rating = 4
    static let orientation = 6

    struct Options {
        var width = 256
        var height = 192
        /// Adds Apple's HDR gain map as an auxiliary image (HEIC only).
        var gainMap = false
        /// Adds a disparity map as an auxiliary image (HEIC only).
        var depth = false
        /// Adds the XMP packet: the coordinate again, City, State, Country,
        /// `Iptc4xmpCore:Location` and `xmp:Rating`.
        var xmp = true
    }

    /// Noise in Display P3, the same every run.
    static func image(width: Int, height: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        var seed: UInt32 = 0x9E37_79B9
        for index in 0..<(width * height * 4) {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            pixels[index] = UInt8(truncatingIfNeeded: seed)
        }
        return context.makeImage()!
    }

    /// The property dictionaries ImageIO writes natively (EXIF, TIFF, GPS,
    /// IPTC, MakerApple).
    static var properties: [CFString: Any] {
        [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: latitude,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: longitude,
                kCGImagePropertyGPSLongitudeRef: "E",
                kCGImagePropertyGPSAltitude: 12.0,
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: make,
                kCGImagePropertyTIFFModel: model,
                kCGImagePropertyTIFFArtist: artist,
                kCGImagePropertyTIFFCopyright: copyright,
                kCGImagePropertyTIFFDateTime: captureDate,
                kCGImagePropertyTIFFOrientation: orientation,
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifISOSpeedRatings: [iso],
                kCGImagePropertyExifDateTimeOriginal: captureDate,
                kCGImagePropertyExifDateTimeDigitized: captureDate,
                kCGImagePropertyExifLensModel: lens,
                kCGImagePropertyExifFNumber: 2.8,
                kCGImagePropertyExifSubjectLocation: [128, 96],
            ],
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCity: city,
                kCGImagePropertyIPTCProvinceState: "Ho Chi Minh",
                kCGImagePropertyIPTCCountryPrimaryLocationName: "Vietnam",
                kCGImagePropertyIPTCSubLocation: "District 1",
                kCGImagePropertyIPTCByline: [artist],
                kCGImagePropertyIPTCCopyrightNotice: copyright,
                kCGImagePropertyIPTCStarRating: rating,
            ],
            kCGImagePropertyMakerAppleDictionary: [
                "8": [0.1, -0.98, 0.05],
            ],
        ]
    }

    /// The tags a Lightroom export adds to XMP on top of EXIF/IPTC.
    static let xmpTags: [(path: String, value: String)] = [
        ("exif:GPSLatitude", "10,46.614N"),
        ("exif:GPSLongitude", "106,42.054E"),
        ("photoshop:City", city),
        ("photoshop:State", "Ho Chi Minh"),
        ("photoshop:Country", "Vietnam"),
        ("Iptc4xmpCore:Location", "District 1"),
        ("Iptc4xmpCore:CountryCode", "VN"),
        ("xmp:Rating", String(rating)),
    ]

    /// Writes photo A as `type` to a new file and returns its URL.
    static func write(_ type: UTType, options: Options = Options(), in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("A-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension(type.preferredFilenameExtension ?? "img")
        let plain = try encode(type, options: options)
        let data = options.xmp ? try addXMP(to: plain, type: type) : plain
        try data.write(to: url)
        return url
    }

    static func encode(_ type: UTType, options: Options) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { throw FixtureError.cannotEncode(type.identifier) }
        CGImageDestinationAddImage(destination, image(width: options.width, height: options.height), properties as CFDictionary)
        if options.gainMap { CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeHDRGainMap, gainMapInfo(options) as CFDictionary) }
        if options.depth { CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeDisparity, disparityInfo(options) as CFDictionary) }
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.cannotEncode(type.identifier) }
        return output as Data
    }

    /// Adds the XMP tags without touching the pixels: a lossless copy with the
    /// source's metadata merged with the extra tags.
    static func addXMP(to data: Data, type: UTType) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let metadata = CGImageMetadataCreateMutableCopy(existing)
        else { throw FixtureError.cannotEncode(type.identifier) }
        for tag in xmpTags {
            CGImageMetadataSetValueWithPath(metadata, nil, tag.path as CFString, tag.value as CFString)
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { throw FixtureError.cannotEncode(type.identifier) }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: true,
        ]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error)
        else { throw FixtureError.cannotEncode("\(type.identifier) XMP: \(String(describing: error?.takeRetainedValue()))") }
        return output as Data
    }

    private static func gainMapInfo(_ options: Options) -> [CFString: Any] {
        let width = options.width / 2, height = options.height / 2
        let metadata = CGImageMetadataCreateMutable()
        let namespace = "http://ns.apple.com/HDRGainMap/1.0/" as CFString
        CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, "HDRGainMap" as CFString, nil)
        CGImageMetadataSetValueWithPath(metadata, nil, "HDRGainMap:HDRGainMapVersion" as CFString, 65536 as CFNumber)
        return [
            kCGImageAuxiliaryDataInfoData: Data((0..<(width * height)).map { UInt8(truncatingIfNeeded: $0 &* 7) }),
            kCGImageAuxiliaryDataInfoDataDescription: [
                "Width": width, "Height": height, "BytesPerRow": width,
                "PixelFormat": kCVPixelFormatType_OneComponent8,
            ] as [String: Any],
            kCGImageAuxiliaryDataInfoMetadata: metadata,
        ]
    }

    private static func disparityInfo(_ options: Options) -> [CFString: Any] {
        let width = options.width / 4, height = options.height / 4
        return [
            kCGImageAuxiliaryDataInfoData: Data(count: width * height * 2),
            kCGImageAuxiliaryDataInfoDataDescription: [
                "Width": width, "Height": height, "BytesPerRow": width * 2,
                "PixelFormat": kCVPixelFormatType_DisparityFloat16,
            ] as [String: Any],
        ]
    }

    /// A JPEG the way Lightroom exports one: EXIF and IPTC written by
    /// ImageIO, plus an XMP packet of its own that repeats the coordinate,
    /// names the place (City, State, Country, Location, LocationCreated) and
    /// carries a 4-star rating. Spliced in as a raw APP1 segment, so ImageIO
    /// has no say in what the packet holds.
    static func lightroomJPEG(in folder: URL) throws -> URL {
        var options = Options()
        options.xmp = false
        let plain = try encode(.jpeg, options: options)
        let packet = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:exif="http://ns.adobe.com/exif/1.0/"
            xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
            xmlns:Iptc4xmpCore="http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/"
            xmlns:Iptc4xmpExt="http://iptc.org/std/Iptc4xmpExt/2008-02-29/"
            xmp:Rating="\(rating)"
            xmp:CreatorTool="Adobe Lightroom Classic 14.0"
            exif:GPSLatitude="10,46.614N"
            exif:GPSLongitude="106,42.054E"
            exif:GPSAltitude="12/1"
            photoshop:City="\(city)"
            photoshop:State="Ho Chi Minh"
            photoshop:Country="Vietnam"
            Iptc4xmpCore:Location="District 1"
            Iptc4xmpCore:CountryCode="VN">
           <Iptc4xmpExt:LocationCreated>
            <rdf:Bag>
             <rdf:li Iptc4xmpExt:City="\(city)" Iptc4xmpExt:CountryName="Vietnam"/>
            </rdf:Bag>
           </Iptc4xmpExt:LocationCreated>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        var segment = Data("http://ns.adobe.com/xap/1.0/".utf8) + Data([0])
        segment.append(Data(packet.utf8))
        let length = segment.count + 2
        var app1 = Data([0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xFF)])
        app1.append(segment)
        // ImageIO wrote an XMP packet of its own (it mirrors IPTC there);
        // a Lightroom file has one packet, so that one goes and ours takes
        // its place straight after SOI.
        var jpeg = Data(plain.prefix(2))
        jpeg.append(app1)
        jpeg.append(withoutXMPSegments(plain).dropFirst(2))
        let url = folder.appendingPathComponent("Lightroom-\(UUID().uuidString.prefix(8)).jpg")
        try jpeg.write(to: url)
        return url
    }

    /// The JPEG with every XMP APP1 segment taken out; everything else,
    /// from SOI to the end of the scan, byte for byte.
    static func withoutXMPSegments(_ jpeg: Data) -> Data {
        let bytes = [UInt8](jpeg)
        let header = [UInt8]("http://ns.adobe.com/xap/1.0/".utf8)
        var output = [UInt8](bytes.prefix(2))
        var index = 2
        while index + 4 <= bytes.count, bytes[index] == 0xFF {
            let marker = bytes[index + 1]
            if marker == 0xDA { break }  // start of scan: the rest is image data
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let end = index + 2 + length
            let payload = bytes[(index + 4)..<min(end, bytes.count)]
            let isXMP = marker == 0xE1 && payload.starts(with: header)
            if !isXMP { output += bytes[index..<end] }
            index = end
        }
        output += bytes[index...]
        return Data(output)
    }

    enum FixtureError: Error { case cannotEncode(String) }

    // MARK: Reading back

    static func properties(of url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func dictionary(_ key: CFString, of url: URL) -> [CFString: Any]? {
        properties(of: url)[key] as? [CFString: Any]
    }

    /// Every XMP tag path in the file (`prefix:name`, nested paths flattened).
    static func xmpPaths(of url: URL) -> Set<String> {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return [] }
        var paths = Set<String>()
        let options = [kCGImageMetadataEnumerateRecursively: true] as CFDictionary
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, options) { path, _ in
            paths.insert(path as String)
            return true
        }
        return paths
    }

    static func hasAuxiliary(_ type: CFString, in url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) != nil
    }

    static func hasColorProfile(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        return image.colorSpace?.name == CGColorSpace.displayP3
    }

    /// The decoded pixels, as stored (no orientation applied), in RGBA8.
    static func pixels(of url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.displayP3),
              let context = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                  bytesPerRow: image.width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        return Data(bytes: data, count: image.width * image.height * 4)
    }
}
