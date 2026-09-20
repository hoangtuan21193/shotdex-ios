import SwiftUI
import ShotDexKit

/// The quick-adjust strip under the frame.
///
/// Resolve for iPad states the reason for its own viewer tool strip plainly:
/// the common tweak should happen *"without ever having to open the
/// inspector"*. ShotDex had the opposite — every change to a clip's speed, a
/// photo's duration or the master level opened the 264pt contextual panel,
/// which covers the timeline the user is judging the change against.
///
/// So this row carries the two or three values that get changed constantly,
/// and each one expands **in place** into a slider. It never covers the
/// timeline, and it is not a second home for the panel's full set: anything
/// that needs more than one number still belongs in the inspector.
struct VideoViewerToolStrip: View {
    @Bindable var model: VideoStudioModel

    /// Which control is expanded, if any. One at a time — the row is 44pt
    /// tall and two sliders in it would be two sliders nobody can hit.
    @State private var expanded: Tool?

    enum Tool: String, Identifiable {
        case speed, duration, volume
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let expanded, let tool = live.first(where: { $0.tool == expanded }) {
                slider(for: tool)
            } else {
                ForEach(live, id: \.tool) { item in
                    chip(item)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: VideoStudioMetrics.viewerToolStripHeight)
        .frame(maxWidth: .infinity)
        .background(EditorTheme.background)
        .animation(EditorTheme.animation, value: expanded)
        .onChange(of: model.inspectorTarget) { expanded = nil }
    }

    // MARK: Items

    /// One quick control: what it reads, what it writes, and the range.
    private struct Item {
        let tool: Tool
        let title: String
        let systemImage: String
        let value: Double
        let range: ClosedRange<Double>
        let readout: String
        let set: (Double) -> Void
        let reset: () -> Void
    }

    /// Only what applies to what is selected right now. A speed chip on a
    /// photo, or a duration chip on a video, is a control that lies.
    private var live: [Item] {
        var items: [Item] = []
        if let clip = model.selectedClip {
            switch clip.kind {
            case .video:
                items.append(Item(
                    tool: .speed,
                    title: String(localized: "Speed", comment: "Video Studio quick strip: playback rate of the selected clip"),
                    systemImage: "speedometer",
                    value: clip.speed,
                    range: VideoClip.speedRange,
                    readout: String(format: "%.2g×", clip.speed),
                    set: { model.setSpeed($0, for: clip.id) },
                    reset: { model.pushUndo(); model.setSpeed(1, for: clip.id) }
                ))
            case .photo, .freeze:
                items.append(Item(
                    tool: .duration,
                    title: String(localized: "Duration", comment: "Video Studio quick strip: how long the selected still stays on screen"),
                    systemImage: "timer",
                    value: clip.photoDuration,
                    range: VideoClip.photoDurationRange,
                    readout: String(format: "%.1fs", clip.photoDuration),
                    set: { model.setPhotoDuration($0, for: clip.id) },
                    reset: { model.pushUndo(); model.setPhotoDuration(VideoClip.defaultPhotoDuration, for: clip.id) }
                ))
            }
        }
        items.append(Item(
            tool: .volume,
            title: String(localized: "Master", comment: "Video Studio quick strip: the whole mix's level"),
            systemImage: "speaker.wave.2",
            value: model.recipe.masterVolume,
            range: 0...1,
            readout: "\(Int(model.recipe.masterVolume * 100))",
            set: { model.setMasterVolume($0) },
            reset: { model.pushUndo(); model.setMasterVolume(1) }
        ))
        return items
    }

    // MARK: Pieces

    private func chip(_ item: Item) -> some View {
        Button {
            expanded = item.tool
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                Text(item.readout)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(EditorTheme.accent)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: VideoStudioMetrics.trackRadius, style: .continuous)
                    .fill(EditorTheme.trackChip)
            )
            .videoHitTarget(drawnHeight: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.readout)
        .accessibilityHint(Text("Opens a slider here, without covering the timeline", comment: "Video Studio quick strip: what tapping a chip does"))
    }

    private func slider(for item: Item) -> some View {
        HStack(spacing: 8) {
            Button { expanded = nil } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .videoHitTarget(drawnHeight: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Done", comment: "Video Studio quick strip: closes the slider and shows the chips again"))

            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EditorTheme.secondaryText)
                .fixedSize()

            Slider(
                value: Binding(get: { item.value }, set: { item.set($0) }),
                in: item.range,
                onEditingChanged: { editing in if editing { model.pushUndo() } }
            )
            .tint(EditorTheme.accent)

            Text(item.readout)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .fixedSize()

            Button(action: item.reset) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .videoHitTarget(drawnHeight: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Reset \(item.title)", comment: "Video Studio quick strip: puts one value back to its default"))
        }
        .accessibilityElement(children: .contain)
    }
}
