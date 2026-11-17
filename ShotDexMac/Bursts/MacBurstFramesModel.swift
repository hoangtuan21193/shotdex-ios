import AppKit
import GRDB
import Photos
import SwiftUI

/// What opens Choose Frames on the Mac: a PhotoKit burst (or a run of
/// frames), the frame to show first, and what a scoring pass said about
/// each. The Mac's copy of iOS's `BurstFramesRequest`, which is iOS-only.
/// Fetched assets carried out of a detached fetch; immutable once fetched.
struct MacBurstAssetBox: @unchecked Sendable {
    let asset: PHAsset?
}

struct MacBurstAssetsBox: @unchecked Sendable {
    let assets: [PHAsset]
}

struct MacBurstRequest: Equatable {
    enum Source: Equatable {
        case burst(String)
        case frames([String])
    }

    let source: Source
    var startFrameId: String?
    var initiallyKept: Set<String> = []
    var weakFrameIds: Set<String> = []
    var chips: [String: [String]] = [:]
    var faceRects: [String: CGRect] = [:]
    var title: String?

    init(burstId: String, startFrameId: String? = nil) {
        source = .burst(burstId)
        self.startFrameId = startFrameId
    }

    var burstId: String? {
        if case .burst(let id) = source { return id }
        return nil
    }
}

/// Choose Frames on the Mac (board `MAC_BurstFrames`, FS-02.05, FS-06.06 §8):
/// one burst's frames, which are kept, and one system deletion of the rest.
/// A Mac copy of the iOS `BurstFramesModel` (Features is not in the Mac
/// target): the banner becomes `note`, pictures are `CGImage`s, and the
/// page's own state (Single/Survey, zoom, the synced focus) lives here.
@MainActor
@Observable
final class MacBurstFramesModel: Identifiable {
    enum Phase: Equatable { case loading, ready, empty }
    enum Layout: String, CaseIterable, Identifiable {
        case single, survey
        var id: String { rawValue }
        var title: String {
            switch self {
            case .single: String(localized: "Single", comment: "Mac Choose Frames: one big frame")
            case .survey: String(localized: "Survey", comment: "Mac Choose Frames: four frames side by side")
            }
        }
    }
    /// Fit: the whole frame. Fill: the frame fills its box, and a drag moves
    /// every frame together. 2×: twice that. (Not "100%": the frames are read
    /// at screen size, not at their own pixels — the board's 100%.)
    enum Zoom: String, CaseIterable, Identifiable {
        case fit, fill, double
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fit: String(localized: "Fit", comment: "Mac Choose Frames zoom: the whole frame")
            // Not "Fill": Window › Fill has that name, and a menu item of the same name is ambiguous.
            case .fill: String(localized: "Fill Frame", comment: "Mac Choose Frames zoom: the frame fills its box")
            case .double: "2×"
            }
        }
        /// Times the fill scale; nil is Fit.
        var factor: CGFloat? {
            switch self {
            case .fit: nil
            case .fill: 1
            case .double: 2
            }
        }
    }

    let id = UUID()
    private(set) var selection = BurstSelection(frames: [])
    private(set) var phase: Phase = .loading
    private(set) var isDeleting = false
    var layout: Layout = .survey
    var zoom: Zoom = .fill
    /// Where every frame looks when zoomed, in each frame's own unit square
    /// (one drag moves them all: "Zoom synced").
    var focus = CGPoint(x: 0.5, y: 0.5)
    /// What the last delete did, or why it did not; shown in the strip's corner.
    private(set) var note: String?
    let isLimited: Bool
    let request: MacBurstRequest
    /// "Burst · 24 frames · Sep 28, 2026 · within 18 seconds · Photos Library".
    private(set) var subtitle = ""
    /// Pictures by frame id: big (the stage) and small (the strip).
    private(set) var pictures: [String: CGImage] = [:]
    private(set) var thumbnails: [String: CGImage] = [:]
    /// Each frame's file name, shutter and time from the first frame.
    private(set) var details: [String: (name: String, shutter: String?, offset: TimeInterval?)] = [:]

    private let library: any BurstLibrary
    private let photoLibrary: PhotoLibraryService
    private let database: AppDatabase
    /// Deletes what it can of the ids: the ids it deleted, and why the rest
    /// stayed (a server that didn't answer), if any did.
    private let deleteAssets: ([String]) async throws -> (deleted: [String], keptWhy: String?)
    private var loading: Set<String> = []

    init(request: MacBurstRequest, library: any BurstLibrary, photoLibrary: PhotoLibraryService, database: AppDatabase,
         isLimited: Bool, deleteAssets: @escaping ([String]) async throws -> (deleted: [String], keptWhy: String?)) {
        self.request = request
        self.library = library
        self.photoLibrary = photoLibrary
        self.database = database
        self.isLimited = isLimited
        self.deleteAssets = deleteAssets
    }

    func load() async {
        let frames: [BurstFrame]
        switch request.source {
        case .burst(let id): frames = await library.frames(ofBurst: id)
        case .frames(let ids): frames = ids.map { BurstFrame(id: $0, isSuggested: false, isPickedInPhotos: false) }
        }
        selection = BurstSelection(frames: frames)
        selection.keep(request.initiallyKept)
        if let start = request.startFrameId { selection.show(id: start) }
        phase = frames.count >= 2 ? .ready : .empty
        await readDetails(frames.map(\.id))
    }

    /// Names, shutters and capture times, off the main actor, for the captions and the subtitle.
    private func readDetails(_ ids: [String]) async {
        let database = database
        let rows = await Task.detached(priority: .userInitiated) { () -> [(String, String?, String?, Int?)] in
            (try? database.reader.read { db in
                try Row.fetchAll(db, sql: "SELECT assetId, originalFilename, shutterSpeedDisplay, creationDate FROM photo_metadata WHERE assetId IN (\(ids.map { _ in "?" }.joined(separator: ",")))",
                                 arguments: StatementArguments(ids))
                .map { ($0["assetId"], $0["originalFilename"], $0["shutterSpeedDisplay"], $0["creationDate"]) }
            }) ?? []
        }.value
        let byId = Dictionary(rows.map { ($0.0, $0) }, uniquingKeysWith: { first, _ in first })
        let start = ids.compactMap { byId[$0]?.3 }.min()
        var details: [String: (name: String, shutter: String?, offset: TimeInterval?)] = [:]
        for id in ids {
            let row = byId[id]
            details[id] = (row?.1 ?? id, row?.2, row?.3.flatMap { date in start.map { TimeInterval(date - $0) } })
        }
        self.details = details
        let dates = ids.compactMap { byId[$0]?.3 }
        let span = TimeInterval((dates.max() ?? 0) - (dates.min() ?? 0))
        var parts = [request.title ?? MacInflect.string("Burst · ^[\(ids.count) frame](inflect: true)", comment: "Mac Choose Frames subtitle: the burst's size")]
        if let first = dates.min() {
            parts.append(Date(timeIntervalSince1970: TimeInterval(first)).formatted(date: .abbreviated, time: .omitted))
        }
        if dates.count > 1 {
            parts.append(String(localized: "within \(Self.duration(span))", comment: "Mac Choose Frames subtitle: how long the burst took"))
        }
        parts.append(String(localized: "Photos Library", comment: "Mac Choose Frames subtitle: where the frames are"))
        subtitle = parts.joined(separator: " · ")
    }

    /// "18 seconds", "4 minutes".
    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds < 60 ? [.second] : (seconds < 3600 ? [.minute] : [.hour, .minute])
        formatter.maximumUnitCount = 1
        return formatter.string(from: max(seconds, 1)) ?? ""
    }

    // MARK: Pictures

    /// A frame's picture: big for the stage, small for the strip; decoded off the main actor.
    func loadPicture(_ id: String, big: Bool) {
        let key = (big ? "b:" : "s:") + id
        guard (big ? pictures[id] : thumbnails[id]) == nil, !loading.contains(key) else { return }
        loading.insert(key)
        #if DEBUG
        if MacDemoLibrary.isOn {
            if let picture = MacDemoLibrary.picture(for: id) { if big { pictures[id] = picture } else { thumbnails[id] = picture } }
            return
        }
        #endif
        let side: CGFloat = big ? 2400 : 120
        Task { [weak self] in
            // The asset fetch reads the library: off the main actor.
            let found = await Task.detached(priority: .userInitiated) {
                MacBurstAssetBox(asset: PhotoLibraryService.fetchAssets(ids: [id]).first)
            }.value
            guard let self else { return }
            guard let asset = found.asset else { self.loading.remove(key); return }
            self.request(asset, id: id, key: key, big: big, side: side)
        }
    }

    private func request(_ asset: PHAsset, id: String, key: String, big: Bool, side: CGFloat) {
        _ = photoLibrary.requestDetailImage(for: asset, targetSize: CGSize(width: side, height: side), allowNetwork: big,
                                            progress: { _ in }) { [weak self] image, degraded in
            guard let self else { return }
            guard let image else { if !degraded { self.loading.remove(key) }; return }
            let box = MacCollageNSImageBox(image: image.copy() as? NSImage ?? image)
            Task { [weak self] in
                let converted = await Task.detached(priority: .userInitiated) {
                    MacCollageImageBox(image: box.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
                }.value
                guard let self else { return }
                guard let cgImage = converted.image else { self.loading.remove(key); return }
                if big {
                    if degraded && self.pictures[id] != nil { return }
                    self.pictures[id] = cgImage
                } else {
                    self.thumbnails[id] = cgImage
                }
                if !degraded { self.loading.remove(key) }
            }
        }
    }

    // MARK: Choosing

    func isWeak(_ id: String) -> Bool { request.weakFrameIds.contains(id) }
    func chips(for id: String) -> [String] { request.chips[id] ?? [] }
    func faceRect(for id: String) -> CGRect? { request.faceRects[id] }
    var keptIds: [String] { selection.frames.map(\.id).filter(selection.isKept) }

    func show(_ index: Int) { selection.show(index); trimPictures() }
    func next() { show(selection.currentIndex + 1) }
    func previous() { show(selection.currentIndex - 1) }
    /// While the system dialog is up the keeps are frozen: the delete was
    /// asked for exactly what showed then.
    func toggleKeepCurrent() { guard !isDeleting else { return }; note = nil; selection.toggleKeepCurrent() }
    func keepOnlySuggested() { guard !isDeleting else { return }; note = nil; selection.keepOnlySuggested() }

    /// Picks made here and not acted on: leaving would lose them (Esc, Done ask).
    var hasUnusedPicks: Bool { !didDelete && Set(keptIds) != request.initiallyKept }
    private(set) var didDelete = false

    /// Big pictures only near the frame on screen (Survey's four, ±2): 24
    /// frames at 2400 px would hold 400 MB.
    private func trimPictures() {
        let near = Set((selection.currentIndex - 2...selection.currentIndex + 5).compactMap { index in
            selection.frames.indices.contains(index) ? selection.frames[index].id : nil
        })
        for id in pictures.keys where !near.contains(id) {
            pictures[id] = nil
            loading.remove("b:" + id)
        }
    }

    /// Keep on a frame other than the current one (Survey's checkboxes).
    func toggleKeep(_ id: String) {
        guard !isDeleting else { return }
        note = nil
        let current = selection.currentIndex
        selection.show(id: id)
        selection.toggleKeepCurrent()
        selection.show(current)
    }

    /// The frames Survey shows: the current one and the three after it (fewer at the end).
    var surveyIndices: [Int] {
        let start = selection.currentIndex
        return Array(start..<min(start + 4, selection.count))
    }

    /// Zoom to face: the current frame's largest face, at 2×.
    func zoomToFace() {
        guard let id = selection.current?.id, let face = faceRect(for: id) else { return }
        focus = CGPoint(x: face.midX, y: face.midY)
        zoom = .double
    }

    var weakCount: Int { selection.frames.filter { isWeak($0.id) }.count }

    var limitedNote: String? {
        guard isLimited, request.burstId != nil else { return nil }
        return String(localized: "ShotDex can see \(selection.count) frames of this burst. Frames you haven't shared stay as they are.",
                      comment: "Burst frame picker under limited photo access")
    }

    /// Keep N, remove M (§6): every frame not kept in one system deletion,
    /// whose own dialog is the confirmation. Cancel or a failure keeps every tick.
    func deleteUnkept() async {
        let ids = selection.deleteIds
        guard selection.canDelete, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        note = nil
        let result: (deleted: [String], keptWhy: String?)
        do {
            result = try await deleteAssets(ids)
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return
        } catch {
            note = Self.deleteFailed
            return
        }
        guard !result.deleted.isEmpty else { note = result.keptWhy ?? Self.deleteFailed; return }
        // Only what went leaves the strip: a frame a server kept is still in Photos.
        selection.remove(Set(result.deleted))
        didDelete = true
        // No Undo: the app cannot read Recently Deleted.
        note = MacInflect.string("^[\(result.deleted.count) frame](inflect: true) moved to Recently Deleted. Recover them in Photos within 30 days.",
                                 comment: "Mac Choose Frames: after deleting the frames not kept")
            + (result.keptWhy.map { " " + $0 } ?? "")
    }

    static var deleteFailed: String {
        String(localized: "Couldn't delete the frames. Nothing was deleted.", comment: "Mac Choose Frames: the system deletion failed")
    }
}

