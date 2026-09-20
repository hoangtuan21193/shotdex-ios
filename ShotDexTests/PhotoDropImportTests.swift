import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// The pure half of a cross-app drag import: what a drop may carry
/// (`canImport`) and what to tell the user afterwards (`addedMessage` /
/// `failureMessage`). `importAssets` itself needs PhotoKit and is left to the
/// UI driver.
@Suite struct PhotoDropImportTests {
    private func provider(registering type: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
            completion(Data(), nil)
            return nil
        }
        return provider
    }

    @Test func canImportIsFalseForNoProviders() {
        #expect(!PhotoDropImport.canImport([]))
    }

    @Test func canImportIsFalseWhenNoProviderMatchesAnAcceptedType() {
        let providers = [provider(registering: UTType.plainText.identifier)]
        #expect(!PhotoDropImport.canImport(providers))
    }

    @Test func canImportIsTrueForAnImage() {
        #expect(PhotoDropImport.canImport([provider(registering: UTType.image.identifier)]))
    }

    @Test func canImportIsTrueForAMovie() {
        #expect(PhotoDropImport.canImport([provider(registering: UTType.movie.identifier)]))
    }

    @Test func canImportIsTrueWhenOnlyOneOfSeveralProvidersMatches() {
        let providers = [
            provider(registering: UTType.plainText.identifier),
            provider(registering: UTType.movie.identifier),
        ]
        #expect(PhotoDropImport.canImport(providers))
    }

    // These pinned the raw markup as "documented current behaviour" when the
    // suite was written: `String(localized: "^[…](inflect: true)")` came back
    // with the markup still in it. Seen on screen too — the On This Day card
    // read "^[1 photo](inflect: true) from previous years".
    //
    // The cause was that no `en.lproj` shipped: English is the development
    // language, and with every catalogue value equal to its key Xcode emitted
    // no English table, so the lookup fell back to the key and grammar
    // agreement — which is applied to a value *from* a table — never ran. The
    // catalogue carries real English plural variations now, so these assert
    // the sentences a reader gets.

    @Test func addedMessageIsPluralisedByCount() {
        #expect(PhotoDropImport.addedMessage(count: 1, destination: .library)
            == "1 photo added to your library")
        #expect(PhotoDropImport.addedMessage(count: 2, destination: .library)
            == "2 photos added to your library")
        // Zero takes the "other" form in English, which is the right reading:
        // "0 photos added" rather than "0 photo added".
        #expect(PhotoDropImport.addedMessage(count: 0, destination: .library)
            == "0 photos added to your library")
    }

    @Test func addedMessageDestinationChangesTheCopy() {
        let library = PhotoDropImport.addedMessage(count: 3, destination: .library)
        let timeline = PhotoDropImport.addedMessage(count: 3, destination: .libraryAndTimeline)
        #expect(library != timeline)
        #expect(timeline.contains("timeline"))
        #expect(!library.contains("timeline"))
    }

    @Test func failureMessageIsPluralisedByCount() {
        #expect(PhotoDropImport.failureMessage(count: 1) == "1 item couldn't be imported.")
        #expect(PhotoDropImport.failureMessage(count: 2) == "2 items couldn't be imported.")
    }

    /// The bug this whole group exists for: no message a reader sees may
    /// still be carrying the inflection markup.
    @Test func noMessageLeaksItsMarkup() {
        for count in 0...3 {
            #expect(!PhotoDropImport.addedMessage(count: count, destination: .library).contains("inflect:"))
            #expect(!PhotoDropImport.addedMessage(count: count, destination: .libraryAndTimeline).contains("inflect:"))
            #expect(!PhotoDropImport.failureMessage(count: count).contains("inflect:"))
        }
    }
}
