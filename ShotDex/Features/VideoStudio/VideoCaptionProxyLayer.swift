import SwiftUI

/// The caption at the playhead, live over the player (FS-12.14 §6): the
/// preview does not bake captions — like text overlays — so an edit repaints
/// here at once, with no composition rebuilt. It draws the very image the
/// export burns in (`VideoCaptionRenderer`), typeset against the export
/// frame and scaled into the preview's frame rect, so the two cannot drift.
///
/// Tapping the caption selects its cue; the selected one wears a dashed
/// outline on the iPad and the Duo's inner display (§3).
struct VideoCaptionProxyLayer: View {
    @Bindable var model: VideoStudioModel
    /// The project frame's rect in the preview.
    let contentRect: CGRect
    /// The export frame the caption is measured against.
    let frame: CGSize
    var showsSelectionOutline = false

    @State private var cache = CaptionImageCache()

    var body: some View {
        if let lane = model.recipe.captions, frame.width > 0,
           let cue = CaptionLayout.cue(at: model.currentTime, in: cues(lane)) {
            let words = lane.style == .wordByWord ? CaptionLayout.visibleWordCount(cue, at: model.currentTime) : Int.max
            let typeset = VideoCaptionRenderer.typeset(cue.text, lane: lane, frame: frame)
            let scale = contentRect.width / frame.width
            let plate = CGRect(
                x: contentRect.minX + typeset.plate.minX * scale,
                y: contentRect.minY + typeset.plate.minY * scale,
                width: typeset.plate.width * scale,
                height: typeset.plate.height * scale
            )
            let isSelected = model.selectedCaptionID == cue.id
            Group {
                if let image = cache.image(cue: cue, words: words, lane: lane, typeset: typeset, scale: scale * displayScale) {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .frame(width: plate.width, height: plate.height)
                }
            }
            .overlay {
                if isSelected, showsSelectionOutline {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .padding(-4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selectCaption(cue.id) }
            .position(x: plate.midX, y: plate.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: cue.text))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("captionOnFrame")
        }
    }

    @Environment(\.displayScale) private var displayScale

    private func cues(_ lane: VideoCaptionLane) -> [CaptionLayout.Cue] {
        cache.cues(lane: lane, recipe: model.recipe)
    }
}

/// The proxy's drawings and the lane's cues in timeline seconds, kept
/// while nothing they depend on changes: the playhead moves thirty times a
/// second, the caption under it rarely.
@MainActor
final class CaptionImageCache {
    private var images: [String: CGImage] = [:]
    private var cuesKey: VideoProjectRecipe?
    private var cachedCues: [CaptionLayout.Cue] = []

    func cues(lane: VideoCaptionLane, recipe: VideoProjectRecipe) -> [CaptionLayout.Cue] {
        if cuesKey == recipe { return cachedCues }
        cuesKey = recipe
        cachedCues = CaptionLayout.cues(lane, in: recipe)
        return cachedCues
    }

    func image(cue: CaptionLayout.Cue, words: Int, lane: VideoCaptionLane, typeset: VideoCaptionRenderer.Typeset, scale: CGFloat) -> CGImage? {
        let key = "\(cue.id)|\(cue.text)|\(words)|\(lane.style.rawValue)|\(lane.sizePercent)|\(lane.position.rawValue)|\(Int(scale * 1000))|\(Int(typeset.plate.width))"
        if let image = images[key] { return image }
        guard let image = VideoCaptionRenderer.image(cue.text, visibleWords: words, lane: lane, typeset: typeset, scale: scale) else { return nil }
        if images.count > 32 { images.removeAll() }
        images[key] = image
        return image
    }
}
