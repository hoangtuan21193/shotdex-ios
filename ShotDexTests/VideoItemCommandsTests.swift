import Testing
@testable import ShotDex

/// A selected item's command row (FS-12.04b §3).
struct VideoItemCommandsTests {
    /// FS-12.04b AC-1: a video clip's row in the spec's order, Delete last
    /// and red. Look (FS-12.06c) is hidden until its plan lands, like Beats
    /// and Ducking — the rest keep their order.
    @Test func videoClipRowIsTheSpecOrder() {
        let row = VideoItemCommand.commands(for: .videoClip)
        let spec: [VideoItemCommand] = [.split, .trim, .speed, .volume, .replace, .freeze, .duplicate, .look, .delete]
        #expect(row == spec.filter { !VideoItemCommand.notYetBuilt.contains($0) })
        #expect(row.last == .delete)
        #expect(row.last?.isDestructive == true)
        #expect(row.filter(\.isDestructive) == [.delete])
        // Single-video mode: Rotate right before Delete (FS-12.04b §3, Q-9).
        let single = VideoItemCommand.commands(for: .videoClip, singleVideo: true)
        #expect(Array(single.suffix(2)) == [.rotate, .delete])
        // No Mute cell: mute is the speaker at the head of the Volume row.
        #expect(!row.map(\.rawValue).contains("mute"))
    }

    /// Every kind's row is the spec's, Delete last, no command twice.
    @Test func everyKindsRowEndsWithDelete() {
        for kind in VideoItemKind.allCases {
            let row = VideoItemCommand.commands(for: kind)
            #expect(row.last == .delete, "\(kind)")
            #expect(Set(row).count == row.count, "\(kind)")
        }
        #expect(VideoItemCommand.commands(for: .text) == [.edit, .font, .color, .style, .align, .animate, .duplicate, .delete])
        #expect(VideoItemCommand.commands(for: .sticker) == [.animate, .duplicate, .delete])
        #expect(VideoItemCommand.commands(for: .music) == [.replace, .addTrack, .duplicate, .delete])
    }

    @Test func sectionsAndActions() {
        for command in [VideoItemCommand.trim, .speed, .volume, .edit, .animate] { #expect(command.isSection) }
        for command in [VideoItemCommand.split, .replace, .freeze, .duplicate, .addTrack, .delete] { #expect(!command.isSection) }
    }
}
