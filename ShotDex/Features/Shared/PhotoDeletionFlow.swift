import Photos
import SwiftUI

/// Deleting from Photos through `PhotoDeletionGate` (FS-19.07 §9), with the
/// alerts the gate can need: the server did not answer (Delete Anyway or
/// Cancel), the confirmation that names Recently Deleted for photos that
/// rely on a server, and afterwards which photos were kept because their
/// server copy is gone. A selection with nothing on a server goes straight
/// to `perform`, as before.
@MainActor
@Observable
final class PhotoDeletionFlow {
    struct Prompt: Identifiable {
        enum Kind {
            /// Photos on a server, all confirmed: say where they go.
            case confirm(count: Int, sourceName: String)
            case unreachable(sourceName: String)
            case notDeleted(count: Int, sourceName: String)
        }

        let id = UUID()
        let kind: Kind
        /// Runs on the destructive button.
        var action: (() -> Void)?
        /// Runs on Cancel.
        var cancel: (() -> Void)?
    }

    private(set) var isChecking = false
    var prompt: Prompt?

    /// - Parameters:
    ///   - confirms: false where the screen already asked, with the Recently
    ///     Deleted sentence (Free Up Space).
    ///   - perform: the PhotoKit delete; the system asks once more.
    ///   - finished: the ids deleted, or the error — `userCancelled` from
    ///     the system, `CancellationError` from Cancel here.
    func delete(_ ids: [String], gate: PhotoDeletionGate, confirms: Bool = true,
                perform: @escaping ([String]) async throws -> Void,
                finished: @escaping (Result<[String], Error>) -> Void) {
        guard !ids.isEmpty, !isChecking else { return }
        isChecking = true
        Task {
            let outcome = await gate.check(photoIds: ids)
            isChecking = false
            let run: ([String]) -> Void = { [weak self] targets in
                Task { await self?.run(targets, outcome: outcome, perform: perform, finished: finished) }
            }
            if let name = outcome.unreachable.keys.sorted().first {
                prompt = Prompt(kind: .unreachable(sourceName: name), action: {
                    run(outcome.deletable + outcome.unreachable.values.flatMap { $0 })
                }, cancel: { finished(.failure(CancellationError())) })
            } else if confirms, !outcome.verified.isEmpty {
                let name = Self.sourceName(outcome, gate: gate) ?? ""
                prompt = Prompt(kind: .confirm(count: outcome.deletable.count, sourceName: name), action: {
                    run(outcome.deletable)
                }, cancel: { finished(.failure(CancellationError())) })
            } else {
                run(outcome.deletable)
            }
        }
    }

    private func run(_ targets: [String], outcome: PhotoDeletionGate.Outcome,
                     perform: @escaping ([String]) async throws -> Void,
                     finished: @escaping (Result<[String], Error>) -> Void) async {
        do {
            if !targets.isEmpty { try await perform(targets) }
            finished(.success(targets))
        } catch {
            finished(.failure(error))
            return
        }
        if let name = outcome.notOnServer.keys.sorted().first {
            prompt = Prompt(kind: .notDeleted(count: outcome.notOnServer.values.reduce(0) { $0 + $1.count }, sourceName: name))
        }
    }

    private static func sourceName(_ outcome: PhotoDeletionGate.Outcome, gate: PhotoDeletionGate) -> String? {
        guard let photo = outcome.verified.first else { return nil }
        return (try? gate.relyingSources(photoIds: [photo]))?[photo]?.first?.name
    }
}

/// The words of the gate's alerts (FS-19.07 §9).
enum PhotoDeletionCopy {
    static func title(_ kind: PhotoDeletionFlow.Prompt.Kind) -> String {
        switch kind {
        case .confirm(let count, _):
            count == 1
                ? String(localized: "Delete 1 Photo from This Device?", comment: "Delete: confirm deleting a photo that is on a server")
                : String(localized: "Delete \(count) Photos from This Device?", comment: "Delete: confirm deleting photos that are on a server")
        case .unreachable(let name):
            String(localized: "Can't Reach \(name)", comment: "Delete: the server holding the copies did not answer")
        case .notDeleted(let count, _):
            count == 1
                ? String(localized: "1 Photo Wasn't Deleted", comment: "Delete: a photo kept because its server copy is gone or changed")
                : String(localized: "\(count) Photos Weren't Deleted", comment: "Delete: photos kept because their server copy is gone or changed")
        }
    }

    static func message(_ kind: PhotoDeletionFlow.Prompt.Kind) -> String {
        switch kind {
        case .confirm(let count, let name):
            count == 1
                ? String(localized: "It's on \(name). It moves to Recently Deleted. iCloud space is freed after Recently Deleted is emptied.",
                         comment: "Delete: where a photo on a server goes, and when iCloud space comes back")
                : String(localized: "They're on \(name). They move to Recently Deleted. iCloud space is freed after Recently Deleted is emptied.",
                         comment: "Delete: where photos on a server go, and when iCloud space comes back")
        case .unreachable(let name):
            String(localized: "ShotDex couldn't check that these are still on \(name).", comment: "Delete: the server could not be asked")
        case .notDeleted(let count, let name):
            count == 1
                ? String(localized: "It's no longer on \(name).", comment: "Delete: the server copy was deleted or changed since the last check")
                : String(localized: "They're no longer on \(name).", comment: "Delete: the server copies were deleted or changed since the last check")
        }
    }
}

extension View {
    /// The alerts of a `PhotoDeletionFlow`.
    func photoDeletionPrompts(_ flow: PhotoDeletionFlow) -> some View {
        alert(
            flow.prompt.map { PhotoDeletionCopy.title($0.kind) } ?? "",
            isPresented: Binding(get: { flow.prompt != nil }, set: { if !$0 { flow.prompt = nil } }),
            presenting: flow.prompt
        ) { prompt in
            switch prompt.kind {
            case .confirm:
                Button(String(localized: "Delete", comment: "Delete: confirm"), role: .destructive) { prompt.action?() }
                Button(String(localized: "Cancel", comment: "Delete: cancel"), role: .cancel) { prompt.cancel?() }
            case .unreachable:
                Button(String(localized: "Delete Anyway", comment: "Delete: delete without checking the server"), role: .destructive) {
                    prompt.action?()
                }
                Button(String(localized: "Cancel", comment: "Delete: cancel"), role: .cancel) { prompt.cancel?() }
            case .notDeleted:
                Button(String(localized: "OK", comment: "Delete: dismiss"), role: .cancel) {}
            }
        } message: { prompt in
            Text(PhotoDeletionCopy.message(prompt.kind))
        }
    }
}
