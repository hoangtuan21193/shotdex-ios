import Foundation
import SwiftUI

/// Drives the opt-in people-and-pets scan from Settings: starts it, reports
/// how far it got, and cancels it.
///
/// The scan is a user action rather than part of indexing, because it is the
/// one pass in the app that decodes whole images. Indexing reads EXIF headers
/// and nothing else, and folding Vision into it would turn a cheap header read
/// into a full decode of every photo in the library.
@MainActor
@Observable
final class SubjectScanModel {
    private let pipeline: SubjectScanPipeline
    private let store: MetadataStore
    private let allowNetwork: @Sendable () -> Bool

    private(set) var progress: SubjectScanProgress?
    private(set) var scannedCount = 0
    private(set) var totalCount = 0
    private var task: Task<Void, Never>?

    var isScanning: Bool { task != nil }
    /// Nothing left to look at, and something was looked at.
    var isComplete: Bool { totalCount > 0 && scannedCount >= totalCount }

    init(
        pipeline: SubjectScanPipeline,
        store: MetadataStore,
        allowNetwork: @escaping @Sendable () -> Bool
    ) {
        self.pipeline = pipeline
        self.store = store
        self.allowNetwork = allowNetwork
    }

    func refreshCoverage() {
        guard let coverage = try? store.subjectScanCoverage() else { return }
        scannedCount = coverage.scanned
        totalCount = coverage.total
    }

    func start() {
        guard task == nil else { return }
        // Set before the task runs so the row disables on the same frame as
        // the tap, the way the index controls do.
        progress = SubjectScanProgress(processed: 0, total: 0)
        let pipeline = pipeline
        let allowNetwork = allowNetwork()
        task = Task { [weak self] in
            _ = await pipeline.run(allowNetwork: allowNetwork) { update in
                Task { @MainActor [weak self] in self?.progress = update }
            }
            await MainActor.run {
                guard let self else { return }
                self.task = nil
                self.progress = nil
                self.refreshCoverage()
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Throws away every result, so the next scan starts from nothing. What
    /// "turn this off" has to mean: the counts are derived data the user asked
    /// the app to compute, and they should be able to un-ask.
    func clear() {
        guard task == nil else { return }
        try? store.clearSubjectObservations()
        refreshCoverage()
    }
}
