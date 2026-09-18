import ShotDexKit
import SwiftUI

/// The extension's whole interface: the photo, a strip of looks, and the four
/// tone controls.
///
/// Tier D by the app's own design language — this works directly on pixels, so
/// it sits on black — but it cannot import the app's `EditorTheme`, which lives
/// on the far side of the framework boundary. The handful of values it needs
/// are spelled out here rather than dragging the editor's UI into ShotDexKit.
struct EditExtensionView: View {
    @Bindable var model: EditExtensionModel

    private enum Theme {
        static let background = Color.black
        static let panel = Color(red: 15 / 255, green: 16 / 255, blue: 18 / 255)
        static let hairline = Color.white.opacity(0.09)
        static let secondaryText = Color.white.opacity(0.55)
        static let accent = Color(red: 1, green: 0.72, blue: 0.23)
    }

    var body: some View {
        VStack(spacing: 0) {
            stage
            panel
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var stage: some View {
        ZStack {
            Theme.background
            if let preview = model.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if model.isRendering {
                ProgressView()
                    .tint(.white)
                    .padding(12)
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 12) {
            lookStrip
            Divider().overlay(Theme.hairline)
            toneRows
        }
        .padding(.vertical, 12)
        .background(Theme.panel)
    }

    private var lookStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.looks) { look in
                    Button {
                        model.recipe.filter = look
                        if look != .original, model.recipe.filterIntensity == 0 {
                            model.recipe.filterIntensity = 1
                        }
                    } label: {
                        Text(look.tileName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(model.recipe.filter == look ? .black : .white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(
                                model.recipe.filter == look
                                    ? Theme.accent
                                    : Color.white.opacity(0.1),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var toneRows: some View {
        if model.recipe.filter != .original {
            slider("Strength", value: $model.recipe.filterIntensity, range: 0...1)
        }
        slider("Exposure", value: $model.recipe.adjustments.exposure, range: -2...2)
        slider("Contrast", value: $model.recipe.adjustments.contrast, range: -1...1)
        slider("Highlights", value: $model.recipe.adjustments.highlights, range: -1...1)
        slider("Shadows", value: $model.recipe.adjustments.shadows, range: -1...1)
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 78, alignment: .leading)
            Slider(value: value, in: range)
                .tint(Theme.accent)
            Text(String(format: "%+.2f", value.wrappedValue))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 16)
    }
}
