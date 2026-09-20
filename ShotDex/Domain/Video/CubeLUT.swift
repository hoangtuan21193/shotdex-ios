import Foundation

/// A parsed Adobe `.cube` lookup table, in the shape Core Image wants.
///
/// `.cube` is what every grading tool exports and what every LUT pack on
/// sale ships: plain text, a declared size, then `size³` RGB triplets with
/// **red varying fastest** — the same ordering
/// `CIColorCubeWithColorSpace` reads, which is why the table can go
/// straight from the file to the GPU without being transposed.
struct CubeLUT: Equatable, Sendable {
    /// Edge length of the cube. 33 is the usual export; 17, 25, 64 happen.
    let dimension: Int
    /// Float RGBA, red fastest, `dimension³ × 4` values — ready for
    /// `inputCubeData`.
    let table: [Float]
    /// `TITLE` from the file, when it carries one.
    let title: String?

    var data: Data {
        table.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

/// Reads `.cube` text into a `CubeLUT`.
///
/// Deliberately strict about the things that would silently ruin a grade —
/// a size that does not match the number of rows, values outside the
/// declared domain — and deliberately relaxed about the things that vary
/// between exporters: comments, blank lines, tabs, `\r\n`, keywords in any
/// case, and a domain other than 0…1.
enum CubeLUTParser {
    enum Failure: Error, Equatable {
        case noSize
        case unsupportedSize(Int)
        case wrongRowCount(expected: Int, found: Int)
        case malformedRow(line: Int)
    }

    /// Core Image will not take a cube bigger than this, and a 64³ table is
    /// already 4 MB of floats.
    static let maximumDimension = 64
    static let minimumDimension = 2

    static func parse(_ text: String) throws -> CubeLUT {
        var title: String?
        var size3D: Int?
        var size1D: Int?
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        var rows: [SIMD3<Float>] = []

        for (offset, rawLine) in text.split(
            whereSeparator: \.isNewline
        ).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            let keyword = fields[0].uppercased()

            switch keyword {
            case "TITLE":
                title = line
                    .dropFirst(fields[0].count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE":
                size3D = fields.count > 1 ? Int(fields[1]) : nil
            case "LUT_1D_SIZE":
                size1D = fields.count > 1 ? Int(fields[1]) : nil
            case "DOMAIN_MIN":
                domainMin = vector(fields.dropFirst()) ?? domainMin
            case "DOMAIN_MAX":
                domainMax = vector(fields.dropFirst()) ?? domainMax
            case "LUT_3D_INPUT_RANGE", "LUT_1D_INPUT_RANGE":
                if let range = vector(fields.dropFirst()), range.x < range.y {
                    domainMin = SIMD3(repeating: range.x)
                    domainMax = SIMD3(repeating: range.y)
                }
            default:
                guard let row = vector(fields[...]) else {
                    throw Failure.malformedRow(line: offset + 1)
                }
                rows.append(row)
            }
        }

        let span = domainMax - domainMin
        let normalize: (SIMD3<Float>) -> SIMD3<Float> = { value in
            var out = SIMD3<Float>(repeating: 0)
            for index in 0..<3 {
                let width = span[index]
                out[index] = width > 0 ? (value[index] - domainMin[index]) / width : value[index]
            }
            return out
        }

        if let size = size3D {
            guard size >= minimumDimension, size <= maximumDimension else {
                throw Failure.unsupportedSize(size)
            }
            let expected = size * size * size
            guard rows.count == expected else {
                throw Failure.wrongRowCount(expected: expected, found: rows.count)
            }
            return CubeLUT(
                dimension: size,
                table: packed(rows.map(normalize)),
                title: title
            )
        }

        if let size = size1D {
            guard size >= minimumDimension, size <= maximumDimension else {
                throw Failure.unsupportedSize(size)
            }
            guard rows.count == size else {
                throw Failure.wrongRowCount(expected: size, found: rows.count)
            }
            return CubeLUT(
                dimension: size,
                table: packed(expand(curve: rows.map(normalize), size: size)),
                title: title
            )
        }

        throw Failure.noSize
    }

    /// A 1D LUT is three independent curves, so the cube it becomes is the
    /// outer product: each axis looks itself up. Expanding rather than
    /// refusing, because a 1D file is a legitimate export — it just says
    /// nothing about cross-channel behaviour.
    private static func expand(curve: [SIMD3<Float>], size: Int) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(size * size * size)
        for blue in 0..<size {
            for green in 0..<size {
                for red in 0..<size {
                    out.append(SIMD3(curve[red].x, curve[green].y, curve[blue].z))
                }
            }
        }
        return out
    }

    private static func packed(_ rows: [SIMD3<Float>]) -> [Float] {
        var table = [Float](repeating: 0, count: rows.count * 4)
        for (index, row) in rows.enumerated() {
            let base = index * 4
            table[base] = row.x
            table[base + 1] = row.y
            table[base + 2] = row.z
            table[base + 3] = 1
        }
        return table
    }

    private static func vector(_ fields: ArraySlice<Substring>) -> SIMD3<Float>? {
        let numbers = fields.compactMap { Float($0) }
        guard numbers.count >= 3 else { return nil }
        return SIMD3(numbers[0], numbers[1], numbers[2])
    }
}
