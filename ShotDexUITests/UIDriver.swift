import Foundation

/// One instruction in a driver script.
///
/// The script is JSON so an agent can write it from a shell without a Swift
/// toolchain in the loop; every field is optional because each action reads
/// only the two or three it needs.
struct UIDriverStep: Decodable {
    /// `launch`, `activate`, `tap`, `tapIndex`, `longPress`, `typeText`,
    /// `swipe`, `scrollTo`, `wait`, `screenshot`, `dump`, `back`, `home`.
    let action: String
    /// Accessibility label or identifier of the element to act on.
    let label: String?
    /// Restricts a label match to one element type (`button`, `image`,
    /// `cell`, `staticText`, …). Omit to search every type.
    let type: String?
    /// Which match to take when a label hits several elements. Default 0.
    let index: Int?
    /// Normalized screen coordinates (0…1), used when there is no label.
    let x: Double?
    let y: Double?
    /// `up`, `down`, `left`, `right` for `swipe`.
    let direction: String?
    /// `swipe` with `x`/`y` only: how far to drag, as a fraction of the
    /// screen. Default 0.25. A coordinate swipe exists because
    /// `XCUIElement.swipeUp()` drags from the element's centre — on a panel
    /// whose centre is a colour wheel, that grades the project instead of
    /// scrolling it.
    let distance: Double?
    /// Text for `typeText`.
    let text: String?
    /// Seconds for `wait`, and the timeout an element wait may take.
    let seconds: Double?
    /// File name (no extension) for `screenshot` and `dump`.
    let name: String?
    /// Launch arguments for `launch`.
    let arguments: [String]?
    /// `dump` only: also report whether each element is hittable. Off by
    /// default — it hit-tests every element, and on a busy screen that is the
    /// difference between a dump and a timeout.
    let hittable: Bool?
}

struct UIDriverScript: Decodable {
    let steps: [UIDriverStep]
}

/// What one element looked like when the tree was dumped.
///
/// `label` empty on a button is the finding this whole file exists to make
/// cheap to see: a control nobody can name, at a frame you can measure.
struct UIDriverElement: Encodable {
    let type: String
    let label: String
    let identifier: String
    let value: String?
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let enabled: Bool
    let selected: Bool
    /// Only filled when the step asked for it: reading it hit-tests every
    /// element, which is what made a dump of the Video Studio never return.
    let hittable: Bool?
}

struct UIDriverStepResult: Encodable {
    let index: Int
    let action: String
    let detail: String
    let failure: String?
}

struct UIDriverReport: Encodable {
    let screen: [Double]
    let steps: [UIDriverStepResult]
    let artifacts: [String]
    /// Which of the driver's own environment variables reached the runner.
    /// Worth reporting: a script that silently did not arrive looks exactly
    /// like a script that ran and found nothing.
    let environment: [String: String]
}
