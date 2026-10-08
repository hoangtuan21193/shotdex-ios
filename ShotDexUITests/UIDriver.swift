import Foundation

/// One instruction in a driver script.
///
/// The script is JSON so an agent can write it from a shell without a Swift
/// toolchain in the loop; every field is optional because each action reads
/// only the two or three it needs.
struct UIDriverStep: Decodable {
    /// `launch`, `activate`, `tap`, `tapIndex`, `longPress`, `typeText`,
    /// `key`, `swipe`, `drag`, `pinch`, `scrollTo`, `wait`, `screenshot`, `dump`,
    /// `back`, `home`.
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
    /// `drag` only: where a one-finger drag from `x`/`y` ends, normalized.
    /// Any angle — `swipe` only goes along an axis, and a ruler drawn along
    /// an axis levels nothing.
    let toX: Double?
    let toY: Double?
    /// Text for `typeText`; for `key`, the one key to press — a character,
    /// or `left` / `right` / `escape` — with `cmd`, `shift`, `option` in
    /// `direction` (comma-separated) as modifiers.
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
    /// `drag` only: how long the finger rests before it moves. Default 0.1;
    /// 0.35 lifts a Media cell, whose hold is 0.3 s (FS-12.09 §5); 0.6 on
    /// a clip's edge handle opens frame trim (FS-12.17 §3) and on a clip's
    /// body moves it (FS-12.11 §4). `hold` is the same field, and wins.
    var pressSeconds: Double?
    var hold: Double?
    /// `drag` and `pinch`: `slow`, `default` or `fast`. A drag defaults to
    /// `slow` (no fling, the content lands under the finger), a pinch to
    /// `default`.
    var velocity: String?
    /// `pinch` only: the scale to pinch to — above 1 spreads the fingers
    /// (zoom in), below 1 closes them. The element is `label` (label or
    /// identifier), else the first of `type`, else the app.
    var scale: Double?
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
