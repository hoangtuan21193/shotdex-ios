import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// The drag payload's contract. The UIKit wiring above it is a few delegate
/// methods; what has to be right is what travels.
struct PhotoDragItemTests {

    /// The identifier type has to be private to this app. A local identifier
    /// means nothing on another device, so offering it to other apps would be
    /// offering them something broken.
    @Test func identifierTypeIsNotAPublicType() {
        #expect(!PhotoDragItem.assetIdentifierType.hasPrefix("public."))
        #expect(PhotoDragItem.assetIdentifierType.hasPrefix("com.hoangtuan.shotdex"))
    }

    /// `UTType(exportedAs:)` only resolves to a real registered type when the
    /// app declares it, which is why it is in Info.plist.
    @Test func exportedTypeResolves() {
        #expect(UTType.shotDexAssetIdentifier.identifier == PhotoDragItem.assetIdentifierType)
        #expect(UTType.shotDexAssetIdentifier.conforms(to: .data))
    }

    /// The identifier survives the trip as bytes.
    ///
    /// Exercised through `NSItemProvider`, the object SwiftUI's drop machinery
    /// actually builds from a `Transferable` — the typed `exported(as:)` and
    /// `init(importing:contentType:)` shortcuts need iOS 18.2 and this app
    /// ships to 17.
    @Test func payloadRoundTripsThroughItsRepresentation() async throws {
        let payload = PhotoDropPayload(assetIdentifier: "ABC-123/L0/001")
        let provider = NSItemProvider(object: PhotoDropPayloadBox(payload))
        #expect(
            provider.hasItemConformingToTypeIdentifier(PhotoDragItem.assetIdentifierType)
        )

        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(
                forTypeIdentifier: PhotoDragItem.assetIdentifierType
            ) { data, _ in
                continuation.resume(returning: data)
            }
        }
        let decoded = try #require(data)
        #expect(String(decoding: decoded, as: UTF8.self) == payload.assetIdentifier)
    }
}

/// Carries a payload through `NSItemProvider`, which predates `Transferable`
/// and wants an `NSItemProviderWriting`.
private final class PhotoDropPayloadBox: NSObject, NSItemProviderWriting {
    let payload: PhotoDropPayload

    init(_ payload: PhotoDropPayload) {
        self.payload = payload
    }

    static var writableTypeIdentifiersForItemProvider: [String] {
        [PhotoDragItem.assetIdentifierType]
    }

    func loadData(
        withTypeIdentifier typeIdentifier: String,
        forItemProviderCompletionHandler completion: @escaping (Data?, (any Error)?) -> Void
    ) -> Progress? {
        completion(Data(payload.assetIdentifier.utf8), nil)
        return nil
    }
}
