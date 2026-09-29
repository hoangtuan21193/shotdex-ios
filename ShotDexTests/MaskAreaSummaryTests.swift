import Testing
@testable import ShotDexKit
@testable import ShotDex

struct MaskAreaSummaryTests {
    /// FS-03.13c §2. Every area in order, each after its sign: "Sky − Brush";
    /// People reads who and which part; Background reads "Background".
    @Test func subtitleListsEveryArea() {
        var sky = PhotoMaskComponent(kind: .sky)
        sky.operation = .add
        var brush = PhotoMaskComponent(kind: .brush)
        brush.operation = .subtract
        var radial = PhotoMaskComponent(kind: .radialGradient)
        radial.operation = .intersect
        var mask = PhotoMask(name: "Mask 1", component: sky)
        mask.components.append(brush)
        #expect(MaskAreaSummary.subtitle(for: mask) == "Sky − Brush")
        mask.components.append(radial)
        #expect(MaskAreaSummary.subtitle(for: mask) == "Sky − Brush ∩ Radial")

        var person = PhotoMaskComponent(kind: .people)
        person.personIndex = 2
        person.personPart = .faceSkin
        #expect(MaskAreaSummary.subtitle(for: PhotoMask(name: "Mask 2", component: person)) == "Person 2 \(PhotoPersonPart.faceSkin.displayName)")

        var background = PhotoMask(name: "Mask 3", component: PhotoMaskComponent(kind: .subject))
        background.isInverted = true
        #expect(MaskAreaSummary.subtitle(for: background) == "Background")
    }
}
