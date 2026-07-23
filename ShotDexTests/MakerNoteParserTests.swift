import Foundation
import Testing
@testable import ShotDex

/// Exercises the MakerNote shutter-count parser with hand-built, deterministic
/// TIFF/Exif byte buffers (no bundled binaries): a minimal little-endian TIFF
/// header → IFD0 (Make/Model + Exif pointer) → Exif IFD (MakerNote) → a
/// vendor-specific note carrying the count.
struct MakerNoteParserTests {

    // MARK: Byte helpers

    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private func le32(_ v: Int) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
    private func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

    /// A 12-byte IFD entry with an inline or pointer value field (caller passes
    /// the raw 4-byte value field).
    private func entry(tag: Int, type: Int, count: Int, valueField: [UInt8]) -> [UInt8] {
        le16(tag) + le16(type) + le32(count) + valueField
    }

    /// Sony enciphers each byte as `(b³ % 249)` (identity ≥ 249). Fixtures store
    /// the enciphered form so the parser's decode table round-trips it.
    private func sonyEncipher(_ plain: UInt8) -> UInt8 {
        let p = Int(plain)
        return p < 249 ? UInt8((p * p * p) % 249) : plain
    }

    // MARK: Nikon (plaintext 0x00A7)

    @Test func nikonEmbeddedTIFFShutterCount() {
        let shutter = 123_456
        // Nikon type-2 note: "Nikon\0" + version + pad, then an embedded TIFF.
        var maker: [UInt8] = ascii("Nikon") + [0x00, 0x02, 0x10, 0x00, 0x00]
        // Embedded TIFF (base = start of this header): II, 42, IFD at +8.
        maker += ascii("II") + le16(42) + le32(8)
        maker += le16(1)                                             // 1 entry
        maker += entry(tag: 0x00A7, type: 4, count: 1, valueField: le32(shutter))
        maker += le32(0)                                             // no next IFD

        let data = buildTIFF(make: "NIKON CORPORATION", model: "NIKON Z 6", makerNote: maker)
        #expect(MakerNoteParser.shutterCount(from: data, make: "NIKON CORPORATION", model: "NIKON Z 6") == shutter)
    }

    // MARK: Sony (enciphered 0x9050)

    @Test func sonyDecipheredShutterCount() {
        let shutter = 45_678
        let offset = 0x3A                                            // ILCE-7M3 offset
        var block = [UInt8](repeating: sonyEncipher(0), count: 100)  // enciphered zeros
        for (i, byte) in le32(shutter).enumerated() {
            block[offset + i] = sonyEncipher(byte)
        }
        // Headerless Sony note: an IFD holding tag 0x9050 pointing at the block.
        // Value fields that are pointers are patched by buildTIFF via a heap.
        let maker = SonyNote(block: block)

        let data = buildSonyTIFF(model: "ILCE-7M3", note: maker)
        #expect(MakerNoteParser.shutterCount(from: data, make: "SONY", model: "ILCE-7M3") == shutter)
    }

    @Test func sonyUnknownModelReturnsNil() {
        var block = [UInt8](repeating: sonyEncipher(0), count: 100)
        for (i, byte) in le32(999).enumerated() { block[0x3A + i] = sonyEncipher(byte) }
        let data = buildSonyTIFF(model: "ILCE-9999", note: SonyNote(block: block))
        #expect(MakerNoteParser.shutterCount(from: data, make: "SONY", model: "ILCE-9999") == nil)
    }

    // MARK: Fujifilm (plaintext 0x1438)

    @Test func fujiImageCount() {
        let shutter = 8_421
        var maker: [UInt8] = ascii("FUJIFILM") + le32(12)            // IFD at note offset 12
        maker += le16(1)
        maker += entry(tag: 0x1438, type: 4, count: 1, valueField: le32(shutter))
        maker += le32(0)
        let data = buildTIFF(make: "FUJIFILM", model: "X-T5", makerNote: maker)
        #expect(MakerNoteParser.shutterCount(from: data, make: "FUJIFILM", model: "X-T5") == shutter)
    }

    // MARK: Unsupported / robustness

    @Test func canonReturnsNil() {
        // Even with a well-formed note, Canon isn't parsed (not in file).
        var maker: [UInt8] = ascii("Nikon") + [0x00, 0x02, 0x10, 0x00, 0x00]
        maker += ascii("II") + le16(42) + le32(8) + le16(1)
        maker += entry(tag: 0x00A7, type: 4, count: 1, valueField: le32(1000))
        maker += le32(0)
        let data = buildTIFF(make: "Canon", model: "Canon EOS R6", makerNote: maker)
        #expect(MakerNoteParser.shutterCount(from: data, make: "Canon", model: "Canon EOS R6") == nil)
    }

    @Test func garbageReturnsNil() {
        #expect(MakerNoteParser.shutterCount(from: Data([0x00, 0x01, 0x02, 0x03]), make: "NIKON", model: "Z6") == nil)
        #expect(MakerNoteParser.shutterCount(from: Data(), make: nil, model: nil) == nil)
    }

    // MARK: - Fixture builders

    /// Builds a little-endian TIFF with IFD0 (Make + Model ASCII strings + Exif
    /// IFD pointer) and an Exif IFD carrying one MakerNote (0x927C) whose data is
    /// `makerNote`. Layout is packed front-to-back with a heap after each IFD.
    private func buildTIFF(make: String, model: String, makerNote: [UInt8]) -> Data {
        let makeBytes = ascii(make) + [0]
        let modelBytes = ascii(model) + [0]

        // Reserve section offsets.
        let headerLen = 8
        let ifd0Start = headerLen
        let ifd0Len = 2 + 3 * 12 + 4               // count + 3 entries + next
        let makeStart = ifd0Start + ifd0Len
        let modelStart = makeStart + makeBytes.count
        let exifStart = modelStart + modelBytes.count
        let exifLen = 2 + 1 * 12 + 4               // count + 1 entry + next
        let makerStart = exifStart + exifLen

        var buf = [UInt8]()
        buf += ascii("II") + le16(42) + le32(ifd0Start)      // header

        // IFD0: Make, Model, Exif pointer.
        buf += le16(3)
        buf += entry(tag: 0x010F, type: 2, count: makeBytes.count, valueField: le32(makeStart))
        buf += entry(tag: 0x0110, type: 2, count: modelBytes.count, valueField: le32(modelStart))
        buf += entry(tag: 0x8769, type: 4, count: 1, valueField: le32(exifStart))
        buf += le32(0)

        buf += makeBytes
        buf += modelBytes

        // Exif IFD: MakerNote pointer.
        buf += le16(1)
        buf += entry(tag: 0x927C, type: 7, count: makerNote.count, valueField: le32(makerStart))
        buf += le32(0)

        buf += makerNote
        return Data(buf)
    }

    /// Sony variant: the MakerNote is a headerless IFD holding tag 0x9050, whose
    /// (large) enciphered block lives in the heap after the note's IFD.
    private func buildSonyTIFF(model: String, note: SonyNote) -> Data {
        let make = "SONY"
        let makeBytes = ascii(make) + [0]
        let modelBytes = ascii(model) + [0]

        let headerLen = 8
        let ifd0Start = headerLen
        let ifd0Len = 2 + 3 * 12 + 4
        let makeStart = ifd0Start + ifd0Len
        let modelStart = makeStart + makeBytes.count
        let exifStart = modelStart + modelBytes.count
        let exifLen = 2 + 1 * 12 + 4
        let noteStart = exifStart + exifLen        // Sony note IFD
        let noteIFDLen = 2 + 1 * 12 + 4
        let blockStart = noteStart + noteIFDLen    // 0x9050 data block

        var buf = [UInt8]()
        buf += ascii("II") + le16(42) + le32(ifd0Start)

        buf += le16(3)
        buf += entry(tag: 0x010F, type: 2, count: makeBytes.count, valueField: le32(makeStart))
        buf += entry(tag: 0x0110, type: 2, count: modelBytes.count, valueField: le32(modelStart))
        buf += entry(tag: 0x8769, type: 4, count: 1, valueField: le32(exifStart))
        buf += le32(0)

        buf += makeBytes
        buf += modelBytes

        // Exif IFD → MakerNote (the Sony note IFD).
        buf += le16(1)
        buf += entry(tag: 0x927C, type: 7, count: noteIFDLen, valueField: le32(noteStart))
        buf += le32(0)

        // Sony note: one entry (0x9050) pointing at the enciphered block.
        buf += le16(1)
        buf += entry(tag: 0x9050, type: 7, count: note.block.count, valueField: le32(blockStart))
        buf += le32(0)

        buf += note.block
        return Data(buf)
    }

    private struct SonyNote { let block: [UInt8] }
}
