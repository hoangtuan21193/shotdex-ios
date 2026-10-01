import CoreGraphics
import Foundation

/// The originals of a collage's cells, prepared at cell size before anything
/// is drawn (FS-02.06 §4, §5): each photo only in iCloud comes down one at a
/// time — nine 48 MP originals never coexist in memory — with its progress
/// in the export screen's own line, and a cell that does not arrive at
/// enough pixels stops the export: no collage is ever saved with an empty or
/// soft cell.
@MainActor
@Observable
final class CollageExportPreparation {
    struct Cell: Sendable {
        let index: Int
        let item: OriginalItem
        /// The long edge the cell needs, in pixels.
        let side: Int
    }

    enum Outcome {
        case ready([Int: CGImage])
        /// Some cells did not come down; nothing may be saved.
        case failed
    }

    private(set) var state: OriginalPreparationState
    private(set) var isShown = false

    private let cells: [Cell]
    private let fetcher: any OriginalFetching
    private let gate: IndexInteractionGate?

    init(cells: [Cell], fetcher: any OriginalFetching, gate: IndexInteractionGate? = nil) {
        self.cells = cells
        self.fetcher = fetcher
        self.gate = gate
        self.state = OriginalPreparationState(batchCount: cells.count)
    }

    /// Loads every cell through `load`, which reports PhotoKit's own
    /// progress. A cell counts only when its image is at least 90% of the
    /// side asked for (§3).
    func run(
        load: @MainActor (Cell, @escaping @Sendable (Double) -> Void) async -> CGImage?
    ) async -> Outcome {
        gate?.beginInteraction()
        defer { gate?.endInteraction() }
        let show = Task { [weak self] in
            try? await Task.sleep(for: OriginalPreparationState.showDelay)
            guard !Task.isCancelled else { return }
            self?.isShown = true
        }
        defer {
            show.cancel()
            isShown = false
        }

        var inCloud: Set<Int> = []
        for cell in cells {
            if await fetcher.probe(cell.item) != .local { inCloud.insert(cell.index) }
        }
        state.downloads = cells.filter { inCloud.contains($0.index) }.map {
            .init(id: String($0.index), filename: $0.item.filename, byteCount: $0.item.byteCount)
        }
        state.phase = .downloading

        var images: [Int: CGImage] = [:]
        for cell in cells {
            let key = String(cell.index)
            let report: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor in self?.report(key, fraction) }
            }
            var image: CGImage?
            do {
                if inCloud.contains(cell.index) {
                    try await fetcher.scriptedTransfer(for: cell.item.id, progress: report)
                }
                image = await load(cell, report)
            } catch {
                image = nil
            }
            gate?.touch()
            let enough = image.map {
                OriginalCompleteness.isSufficient(
                    received: PixelSize(width: $0.width, height: $0.height),
                    requestedLongEdge: cell.side, photo: cell.item.photo
                )
            } ?? false
            if enough, let image {
                images[cell.index] = image
                mark(key, failed: false)
            } else {
                mark(key, failed: true, filename: cell.item.filename)
            }
        }

        guard state.failedNames.isEmpty else {
            state.phase = .failed
            return .failed
        }
        state.phase = .ready
        return .ready(images)
    }

    private func report(_ key: String, _ fraction: Double) {
        guard let index = state.downloads.firstIndex(where: { $0.id == key }),
              !state.downloads[index].isFinished else { return }
        state.downloads[index].fraction = fraction
    }

    private func mark(_ key: String, failed: Bool, filename: String = "") {
        if let index = state.downloads.firstIndex(where: { $0.id == key }) {
            if failed { state.downloads[index].hasFailed = true } else {
                state.downloads[index].isFinished = true
                state.downloads[index].fraction = 1
            }
        } else if failed {
            // A cell the probe called local that still did not load: it is
            // named all the same.
            state.downloads.append(.init(id: key, filename: filename, hasFailed: true))
        }
    }
}
