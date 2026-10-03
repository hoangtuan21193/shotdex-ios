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

extension VideoItemCommandsTests {
    /// FS-12.04b AC-2: a photo clip — Split · Trim · Replace · Duplicate ·
    /// Look · Delete; no Speed, Volume or Freeze cell.
    @Test func photoRowHasNoSpeedVolumeFreeze() {
        let row = VideoItemCommand.commands(for: .photoClip)
        let spec: [VideoItemCommand] = [.split, .trim, .replace, .duplicate, .look, .delete]
        #expect(row == spec.filter { !VideoItemCommand.notYetBuilt.contains($0) })
        for absent in [VideoItemCommand.speed, .volume, .freeze] {
            #expect(!row.contains(absent))
        }
        #expect(VideoItemCommand.commands(for: .freezeClip) == [.split, .trim, .duplicate, .delete])
    }
}

extension VideoItemCommandsTests {
    /// FS-12.04b AC-3: every layout reads the same list for every kind of
    /// item — compared element by element against the phone's — and lays
    /// it out as one scrolling row.
    @Test func everyLayoutGetsTheSameCommands() {
        for kind in VideoItemKind.allCases {
            let phone = VideoItemCommand.commands(for: kind, in: .phone)
            for windowClass in VideoStudioWindowClass.allCases {
                #expect(VideoItemCommand.commands(for: kind, in: windowClass) == phone, "\(kind) on \(windowClass)")
                #expect(VideoItemCommand.rowShape(in: windowClass) == .scrollingRow)
            }
        }
    }
}

/// Section commands light and unlight (FS-12.04b §4).
@MainActor
struct VideoItemSectionTests {
    /// FS-12.04b AC-4: Trim lights its cell and puts its block on top.
    @Test func trimTogglesItsBlock() {
        let model = VideoStudioModelFixture.model()
        model.selectClip(model.recipe.clips[1].id)
        model.toggleItemSection(.trim)
        #expect(model.activeItemCommand == .trim)
        #expect(model.isItemCommandOn(.trim))
        #expect(!model.isItemCommandOn(.split))
        // A new selection starts with nothing lit.
        model.selectClip(model.recipe.clips[2].id)
        #expect(model.activeItemCommand == nil)
    }
}
