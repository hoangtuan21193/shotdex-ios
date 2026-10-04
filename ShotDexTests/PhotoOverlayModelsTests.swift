import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct PhotoOverlayModelsTests {
    private func fullyConfiguredTextOverlay() -> PhotoOverlay {
        var overlay = PhotoOverlay.text()
        overlay.text = "Shot on {camera} · {focal}"
        overlay.fontPostScriptName = "SnellRoundhand-Black"
        overlay.fontFamilyName = "Snell Roundhand"
        overlay.isBold = true
        overlay.isItalic = true
        overlay.alignment = .trailing
        overlay.opacity = 0.8
        overlay.center = NormalizedPoint(x: 0.2, y: 0.7)
        overlay.rotationDegrees = -12
        overlay.size = 0.08
        overlay.lineSpacing = 0.4
        overlay.tracking = 0.05
        overlay.maximumWidth = 0.6
        overlay.fill = OverlayColor(red: 0.9, green: 0.2, blue: 0.1)
        overlay.outlineWidth = 0.03
        overlay.outlineColor = OverlayColor(white: 0.25)
        overlay.shadowRadius = 0.1
        overlay.shadowOffsetY = 0.05
        overlay.shadowOpacity = 0.6
        overlay.isVisible = false
        return overlay
    }

    @Test func recipeRoundTripsEveryOverlayField() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.overlays = [
            fullyConfiguredTextOverlay(),
            .image(id: UUID(), assetIdentifier: "asset/local-id"),
        ]

        let decoded = try JSONDecoder().decode(
            PhotoEditRecipe.self,
            from: JSONEncoder().encode(recipe)
        )
        #expect(decoded == recipe)
    }

    @Test func recipeWithoutOverlaysEmitsNoKey() throws {
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(PhotoEditRecipe.identity)
        ) as? [String: Any]
        #expect(object?.keys.contains("overlays") == false)
    }

    @Test func recipeSavedBeforeOverlaysExistedStillDecodes() throws {
        let json = Data(#"{"source":"raw","filter":"vivid"}"#.utf8)
        let recipe = try JSONDecoder().decode(PhotoEditRecipe.self, from: json)
        #expect(recipe.overlays.isEmpty)
    }

    @Test func overlaysMakeARecipeNonIdentity() {
        var recipe = PhotoEditRecipe.identity
        #expect(recipe.isIdentity)
        recipe.overlays = [.text()]
        #expect(!recipe.isIdentity)
    }

    /// A default layer has to stay cheap on the wire: the recipe shares a photo's
    /// adjustment data with every other edit.
    @Test func defaultOverlayEncodesOnlyIdentityAndKind() throws {
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(PhotoOverlay.text())
        ) as? [String: Any]
        #expect(object?.keys.sorted() == ["id", "kind"])
    }

    /// A layer written by a future build with fields this one lacks, and missing
    /// fields this one has, must still open rather than throwing away the edit.
    @Test func overlayDecodesFromAPartialPayload() throws {
        let json = Data(#"{"kind":"text","text":"Hi","unknownFutureField":42}"#.utf8)
        let overlay = try JSONDecoder().decode(PhotoOverlay.self, from: json)
        #expect(overlay.kind == .text)
        #expect(overlay.text == "Hi")
        #expect(overlay.size == PhotoOverlay.text().size)
        #expect(overlay.center == PhotoOverlay.text().center)
        #expect(overlay.fill == .white)
        #expect(overlay.isVisible)
    }

    /// Text and image layers start in different places at different sizes; an
    /// image layer decoded without a size must not inherit a caption's.
    @Test func overlayDefaultsFollowTheirKind() throws {
        let json = Data(#"{"kind":"image"}"#.utf8)
        let overlay = try JSONDecoder().decode(PhotoOverlay.self, from: json)
        #expect(overlay.size == PhotoOverlay(kind: .image).size)
        #expect(overlay.size != PhotoOverlay(kind: .text).size)
    }

    @Test func emptyOrTransparentOverlaysHaveNoVisibleEffect() {
        #expect(!PhotoOverlay.text().hasVisibleEffect)

        var blank = PhotoOverlay.text()
        blank.text = "   \n "
        #expect(!blank.hasVisibleEffect)

        var faded = PhotoOverlay.text()
        faded.text = "Credit"
        faded.opacity = 0
        #expect(!faded.hasVisibleEffect)

        var hidden = PhotoOverlay.text()
        hidden.text = "Credit"
        hidden.isVisible = false
        #expect(!hidden.hasVisibleEffect)

        var visible = PhotoOverlay.text()
        visible.text = "Credit"
        #expect(visible.hasVisibleEffect)

        #expect(!PhotoOverlay(kind: .image).hasVisibleEffect)
        #expect(PhotoOverlay.image(id: UUID(), assetIdentifier: nil).hasVisibleEffect)
    }

    @Test func signaturePresetRoundTrips() throws {
        let preset = SignaturePreset(
            name: "Instagram",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            layers: [fullyConfiguredTextOverlay(), .image(id: UUID(), assetIdentifier: nil)]
        )
        let decoded = try JSONDecoder().decode(
            SignaturePreset.self,
            from: JSONEncoder().encode(preset)
        )
        #expect(decoded == preset)
    }

    /// A preset keeps the shape of the photo it was saved on (FS-05.04 §3);
    /// one saved before that existed reads as 3:2.
    @Test func signaturePresetCarriesAspect() throws {
        let preset = SignaturePreset(
            name: "Credit", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            layers: [fullyConfiguredTextOverlay()], sourceAspect: 0.75
        )
        let decoded = try JSONDecoder().decode(SignaturePreset.self, from: JSONEncoder().encode(preset))
        #expect(decoded.sourceAspect == 0.75)
        #expect(WatermarkStamp(preset: decoded, placement: WatermarkPlacement()).sourceAspect == 0.75)

        let old = #"{"id":"\#(UUID().uuidString)","name":"Old","createdAt":0,"layers":[]}"#
        let legacy = try JSONDecoder().decode(SignaturePreset.self, from: Data(old.utf8))
        #expect(legacy.sourceAspect == nil)
        #expect(WatermarkStamp(preset: legacy, placement: WatermarkPlacement()).sourceAspect == 1.5)
    }

    /// One preset this build cannot read is dropped alone — never every
    /// signature with it.
    @MainActor
    @Test func oneBadPresetKeepsTheRest() throws {
        let suite = "PhotoOverlayModelsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let good = SignaturePreset(name: "Credit", createdAt: Date(), layers: [fullyConfiguredTextOverlay()])
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        let broken = #"{"id":"not-a-uuid","name":7,"layers":[{"kind":"hologram"}]}"#
        defaults.set(Data("[\(broken),\(goodJSON)]".utf8), forKey: SettingsKeys.overlaySignatures)

        let store = SignaturePresetStore(defaults: defaults, images: OverlayImageStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        ))
        #expect(store.presets.map(\.name) == ["Credit"])
    }
}
