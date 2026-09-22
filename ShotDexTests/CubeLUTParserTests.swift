import Testing
@testable import ShotDex
import ShotDexKit

/// Reading `.cube` files, which is the format every look pack on sale ships.
///
/// The cases that matter are the ones that would silently ruin a grade —
/// a size that does not match the rows, a domain other than 0…1, a 1D file
/// where a 3D one was expected — plus the exporter noise that must **not**
/// stop a legitimate file from loading.
struct CubeLUTParserTests {
    /// The smallest legal 3D cube: 2³ = 8 rows, identity.
    private let identity2 = """
    # Written by a test
    TITLE "Neutral"
    LUT_3D_SIZE 2

    0.0 0.0 0.0
    1.0 0.0 0.0
    0.0 1.0 0.0
    1.0 1.0 0.0
    0.0 0.0 1.0
    1.0 0.0 1.0
    0.0 1.0 1.0
    1.0 1.0 1.0
    """

    @Test func readsSizeTitleAndTable() throws {
        let lut = try CubeLUTParser.parse(identity2)
        #expect(lut.dimension == 2)
        #expect(lut.title == "Neutral")
        #expect(lut.table.count == 8 * 4)
        // Red varies fastest, and every alpha is 1 — the order and shape
        // `CIColorCubeWithColorSpace` reads.
        #expect(lut.table[0...3] == [0, 0, 0, 1])
        #expect(lut.table[4...7] == [1, 0, 0, 1])
        #expect(stride(from: 3, to: lut.table.count, by: 4).allSatisfy { lut.table[$0] == 1 })
    }

    @Test func theDataIsFloatsNotText() throws {
        let lut = try CubeLUTParser.parse(identity2)
        #expect(lut.data.count == 8 * 4 * MemoryLayout<Float>.size)
    }

    /// Tabs, CRLF, comments anywhere, keywords in any case, blank lines.
    /// Every one of these has come out of a real exporter.
    @Test func exporterNoiseDoesNotStopTheRead() throws {
        let noisy = "#c\r\nlut_3d_size\t2\r\n\r\n" + (0..<8).map { _ in "0.5\t0.5\t0.5" }
            .joined(separator: "\r\n")
        let lut = try CubeLUTParser.parse(noisy)
        #expect(lut.dimension == 2)
        #expect(lut.table[0] == 0.5)
    }

    /// A file that declares 0…255 has to be normalized or every value
    /// clips to white.
    @Test func aNonUnitDomainIsNormalized() throws {
        let text = """
        LUT_3D_SIZE 2
        DOMAIN_MIN 0 0 0
        DOMAIN_MAX 255 255 255
        """ + "\n" + (0..<8).map { _ in "128 64 255" }.joined(separator: "\n")
        let lut = try CubeLUTParser.parse(text)
        #expect(abs(lut.table[0] - 128.0 / 255) < 0.0001)
        #expect(abs(lut.table[1] - 64.0 / 255) < 0.0001)
        #expect(lut.table[2] == 1)
    }

    /// A 1D file is three curves. Expanding it into a cube is the honest
    /// reading — refusing it would reject a legitimate export.
    @Test func aOneDimensionalFileBecomesACube() throws {
        let text = """
        LUT_1D_SIZE 2
        0.0 0.0 0.0
        1.0 0.5 0.25
        """
        let lut = try CubeLUTParser.parse(text)
        #expect(lut.dimension == 2)
        #expect(lut.table.count == 8 * 4)
        // Index 1 is red = 1, green = 0, blue = 0 on the cube grid, so the
        // curves are read per axis rather than per row.
        #expect(lut.table[4...6] == [1, 0, 0])
        // The far corner is every curve at its top.
        #expect(lut.table[28...30] == [1, 0.5, 0.25])
    }

    // MARK: Refusals

    @Test func aFileWithNoSizeIsRefused() {
        #expect(throws: CubeLUTParser.Failure.noSize) {
            try CubeLUTParser.parse("0.0 0.0 0.0\n1.0 1.0 1.0")
        }
    }

    /// The failure that would otherwise be invisible: the right number of
    /// numbers, the wrong number of rows, and a grade that is quietly wrong.
    @Test func aTruncatedTableIsRefused() {
        let text = "LUT_3D_SIZE 2\n" + (0..<7).map { _ in "0 0 0" }.joined(separator: "\n")
        #expect(throws: CubeLUTParser.Failure.wrongRowCount(expected: 8, found: 7)) {
            try CubeLUTParser.parse(text)
        }
    }

    @Test func anOversizedCubeIsRefused() {
        #expect(throws: CubeLUTParser.Failure.unsupportedSize(128)) {
            try CubeLUTParser.parse("LUT_3D_SIZE 128\n0 0 0")
        }
    }

    @Test func aRowThatIsNotNumbersIsRefused() {
        #expect(throws: CubeLUTParser.Failure.malformedRow(line: 2)) {
            try CubeLUTParser.parse("LUT_3D_SIZE 2\nnot a colour")
        }
    }
}
