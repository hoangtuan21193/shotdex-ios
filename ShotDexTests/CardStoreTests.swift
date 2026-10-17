import Foundation
import Testing
@testable import ShotDex

/// FS-20 §4, AC-20: a card chosen once is known again without a picker.
@MainActor
@Suite struct CardStoreTests {
    @Test func recognisesSameCard() throws {
        let defaults = UserDefaults(suiteName: "cards-\(UUID().uuidString)")!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EOS_DIGITAL-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("DCIM"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CardStore(defaults: defaults)
        let card = try store.remember(folder)
        #expect(store.connectedCards == [card])
        // Picked again: one card, not two.
        try store.remember(folder)
        #expect(store.remembered.count == 1)
        // A new launch reads it back and finds it plugged in, no picker.
        let next = CardStore(defaults: defaults)
        next.refresh()
        #expect(next.connectedCards.map(\.id) == [card.id])
        // Unplugged: remembered, not connected.
        try FileManager.default.removeItem(at: folder)
        next.refresh()
        #expect(next.remembered.count == 1)
        #expect(next.connectedCards.isEmpty)
    }
}
