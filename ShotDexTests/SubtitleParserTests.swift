import Foundation
import Testing
@testable import ShotDex

/// FS-23.03 §3: SRT, WebVTT and ASS into cues — italic, bold and line breaks
/// kept, everything else dropped, top lines kept at the top.
@Suite struct SubtitleParserTests {
    @Test func srt() {
        let text = """
        1
        00:01:05,000 --> 00:01:07,500
        <i>Where are you going?</i>
        <b>Home</b>, she said.

        2
        00:01:08,250 --> 00:01:09,000
        {\\an8}<font color="#ffff00">Kitchen — 9:41 PM</font>

        3
        broken timing line

        4
        01:02:03,4 --> 01:02:05,04
        Short fractions
        """
        let cues = SubtitleParser.parse(text, format: .srt).cues
        #expect(cues.count == 3)
        #expect(cues[0].startMs == 65_000)
        #expect(cues[0].endMs == 67_500)
        #expect(cues[0].lines == [
            [SubtitleRun(text: "Where are you going?", isItalic: true)],
            [SubtitleRun(text: "Home", isBold: true), SubtitleRun(text: ", she said.")],
        ])
        #expect(cues[1].placement == .top)
        #expect(cues[1].plainText == "Kitchen — 9:41 PM")
        #expect(cues[2].startMs == 3_723_400)
        #expect(cues[2].endMs == 3_725_040)
    }

    @Test func vtt() {
        let text = """
        WEBVTT
        Kind: captions

        NOTE written by hand

        intro
        00:05.000 --> 00:07.000 line:0 position:50%
        <v Anna>Up here</v>

        00:00:08.000 --> 00:00:09.500 align:center
        <c.yellow>Down</c> <i>here</i>
        """
        let cues = SubtitleParser.parse(text, format: .vtt).cues
        #expect(cues.map(\.plainText) == ["Up here", "Down here"])
        #expect(cues.map(\.placement) == [.top, .bottom])
        #expect(cues[0].startMs == 5_000)
        #expect(cues[1].lines[0].last == SubtitleRun(text: "here", isItalic: true))
    }

    /// AC-22: `{\i1}` kept, `{\pos(…)}` dropped, an `{\an8}` line at the top.
    @Test func assKeepsItalicAndTop() {
        let text = """
        [Script Info]
        ScriptType: v4.00+

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,20,1
        Style: Sign,Arial,40,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,2,0,8,10,10,20,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:01:05.00,0:01:07.50,Default,,0,0,0,,{\\pos(640,360)}{\\i1}Xin chào{\\i0}, anh khỏe không?
        Dialogue: 0,0:01:08.00,0:01:09.00,Default,,0,0,0,,{\\an8}Phía trên\\Ndòng hai, có, dấu phẩy
        Dialogue: 0,0:01:10.00,0:01:11.00,Sign,,0,0,0,,CỬA HÀNG
        Dialogue: 0,0:01:12.00,0:01:13.00,Default,,0,0,0,,{\\p1}m 0 0 l 100 0 100 100 0 100{\\p0}
        """
        let cues = SubtitleParser.parse(text, format: .ass).cues
        #expect(cues.count == 3)
        #expect(cues[0].lines == [[SubtitleRun(text: "Xin chào", isItalic: true), SubtitleRun(text: ", anh khỏe không?")]])
        #expect(cues[0].placement == .bottom)
        #expect(cues[1].placement == .top)
        #expect(cues[1].plainText == "Phía trên\ndòng hai, có, dấu phẩy")
        #expect(cues[2].placement == .top)
        #expect(cues[2].lines == [[SubtitleRun(text: "CỬA HÀNG", isBold: true)]])
        #expect(cues[0].startMs == 65_000)
        #expect(cues[0].endMs == 67_500)
    }

    /// The S2 spike's extracted ASS shape: header from CodecPrivate + lines.
    @Test func overlappingCuesKeepFileOrderAtSameStart() {
        let text = """
        1
        00:00:01,000 --> 00:00:04,000
        first

        2
        00:00:01,000 --> 00:00:03,000
        second
        """
        #expect(SubtitleParser.parse(text, format: .srt).cues.map(\.plainText) == ["first", "second"])
    }

    @Test func detectsFormat() {
        #expect(SubtitleParser.detectFormat("WEBVTT\n\n00:01.000 --> 00:02.000\nhi") == .vtt)
        #expect(SubtitleParser.detectFormat("[Script Info]\nTitle: x") == .ass)
        #expect(SubtitleParser.detectFormat("1\n00:00:01,000 --> 00:00:02,000\nhi") == .srt)
        #expect(SubtitleParser.detectFormat("", fileExtension: "ssa") == .ass)
    }
}

/// FS-23.03 §3: subtitle bytes in whatever encoding they were written.
@Suite struct SubtitleDecoderTests {
    /// AC-21: a Vietnamese SRT saved as Windows-1258 reads correctly.
    @Test func vietnameseWindows1258() throws {
        let line = "Xin chào các bạn, tôi là Phương. Hôm nay trời đẹp quá!"
        let srt = "1\n00:00:01,000 --> 00:00:03,000\n\(line)\n"
        let bytes = try #require(Self.windows1258(srt))
        #expect(String(data: bytes, encoding: .utf8) == nil)

        let decoded = SubtitleDecoder.decode(bytes, languageHint: "vi")
        #expect(decoded.encoding == "windows-1258")
        #expect(decoded.text.contains(line))
        #expect(SubtitleParser.parse(decoded.text, format: .srt).cues.first?.plainText == line)
        #expect(!decoded.text.contains("\u{FFFD}"))
    }

    /// Windows-1258 the way Vietnamese files are written: â ê ô ơ ư ă đ
    /// precomposed, tone marks as combining characters (Foundation will not
    /// encode the fully precomposed letters).
    static func windows1258(_ text: String) -> Data? {
        let tones: Set<UInt32> = [0x300, 0x301, 0x303, 0x309, 0x323]
        var out = ""
        for character in text {
            let scalars = Array(String(character).decomposedStringWithCanonicalMapping.unicodeScalars)
            let base = scalars.filter { !tones.contains($0.value) }
            let marks = scalars.filter { tones.contains($0.value) }
            var unicode = String.UnicodeScalarView()
            unicode.append(contentsOf: base)
            out += String(unicode).precomposedStringWithCanonicalMapping
            out.unicodeScalars.append(contentsOf: marks)
        }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsVietnamese.rawValue)))
        return out.data(using: encoding)
    }

    @Test func utf8AndBOMs() throws {
        let text = "Xin chào — 你好"
        #expect(SubtitleDecoder.decode(Data(text.utf8)) == .init(text: text, encoding: "utf-8"))
        #expect(SubtitleDecoder.decode(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)) == .init(text: text, encoding: "utf-8"))
        let utf16 = try #require(text.data(using: .utf16))  // writes a BOM
        #expect(SubtitleDecoder.decode(utf16) == .init(text: text, encoding: "utf-16"))
    }

    @Test func legacyWithoutHint() throws {
        let french = "Où est la bibliothèque ? Déjà vu, garçon."
        let latin = try #require(french.data(using: .windowsCP1252))
        #expect(SubtitleDecoder.decode(latin).text == french)

        let russian = "Привет, как дела?"
        let cyrillic = try #require(russian.data(using: .windowsCP1251))
        #expect(SubtitleDecoder.decode(cyrillic, languageHint: "ru").text == russian)
    }

    /// ⋯ › Encoding: the user's pick re-reads the same bytes.
    @Test func manualPick() throws {
        let russian = "Привет"
        let bytes = try #require(russian.data(using: .windowsCP1251))
        #expect(SubtitleDecoder.decode(bytes, encoding: "windows-1251") == russian)
        #expect(SubtitleDecoder.decode(Data([0xFF, 0xFE, 0x41]), encoding: "utf-8") == nil)
        #expect(SubtitleDecoder.choices.contains("windows-1258"))
    }
}
