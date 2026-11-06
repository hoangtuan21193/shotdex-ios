import XCTest

/// Drives the Mac app from a JSON script — the macOS twin of
/// `ShotDexUITests/UIDriverTests`, so a loop with nothing but `Bash` can click
/// a button and then check what the click did.
///
/// ```
/// Tools/mac-ui-drive ShotDexMacUITests/scripts/<script>.json [out-dir]
/// ```
///
/// Steps (every field optional except `action`):
/// - `launch` `arguments` — always adds `-ApplePersistenceIgnoreState YES`.
/// - `click` / `rightClick` / `doubleClick` / `hover` — `label` (label, title or
///   identifier), optional `type` and `index`; or `x`/`y` normalized to the
///   front window.
/// - `menu` `text` — a menu bar path, `"File>New Album…"`.
/// - `typeText` `text` (into `label` when given), `key` `text` + modifiers in
///   `modifiers` (`cmd,shift,option,ctrl`).
/// - `scroll` `label` + `distance` (lines, negative scrolls up).
/// - `wait` `seconds`; `waitFor` / `assertExists` / `assertMissing` `label`
///   (+ `type`, `seconds`) — the assertion that makes a click a test.
/// - `assertValue` `label` + `text` — the element's value (toggle, field).
/// - `screenshot` `name` — the front window only, never the whole screen.
/// - `dump` `name` — every element of the app with label, identifier, value,
///   frame in window points, enabled and selected.
final class MacUIDriverTests: XCTestCase {
    private var app: XCUIApplication!
    private var results: [[String: String]] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testRunScript() throws {
        let steps = try loadSteps()
        for (index, step) in steps.enumerated() {
            do {
                let detail = try perform(step)
                results.append(["index": "\(index)", "action": step.action, "detail": detail])
                print("step \(index) \(step.action) ok \(detail)")
            } catch {
                results.append(["index": "\(index)", "action": step.action, "detail": describe(step), "failure": "\(error)"])
                print("step \(index) \(step.action) FAILED \(describe(step)): \(error)")
                screenshot(named: "stuck")
                dump(named: "stuck")
                writeReport()
                XCTFail("step \(index) (\(step.action) \(describe(step))) failed: \(error)")
                return
            }
        }
        writeReport()
    }

    // MARK: Script

    private struct Step: Decodable {
        let action: String
        var label: String?
        var type: String?
        var index: Int?
        var x: Double?
        var y: Double?
        var text: String?
        var modifiers: String?
        var distance: Double?
        var seconds: Double?
        var name: String?
        var arguments: [String]?
    }

    private struct Script: Decodable { let steps: [Step] }

    private enum DriverError: Error, CustomStringConvertible {
        case missing(String)
        case notFound(String)
        case assertion(String)
        var description: String {
            switch self {
            case .missing(let field): "missing \(field)"
            case .notFound(let what): "not found: \(what)"
            case .assertion(let what): "assertion failed: \(what)"
            }
        }
    }

    private func loadSteps() throws -> [Step] {
        // `Tools/mac-ui-drive` copies the script into the bundle before the
        // build, the same channel the iOS driver uses.
        guard let url = Bundle(for: Self.self).url(forResource: "driver-script", withExtension: "json") else {
            throw DriverError.missing("driver-script.json in the test bundle")
        }
        return try JSONDecoder().decode(Script.self, from: Data(contentsOf: url)).steps
    }

    private func describe(_ step: Step) -> String {
        [step.label.map { "label=\($0)" }, step.type.map { "type=\($0)" }, step.index.map { "index=\($0)" },
         step.text.map { "text=\($0)" }, step.name.map { "name=\($0)" }]
            .compactMap { $0 }.joined(separator: " ")
    }

    // MARK: Actions

    private func perform(_ step: Step) throws -> String {
        switch step.action {
        case "launch":
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"] + (step.arguments ?? [])
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 30)
            _ = app.windows.firstMatch.waitForExistence(timeout: 15)
        case "activate":
            app.activate()
        case "click":
            if let point = try windowPoint(step) { point.click() } else { try element(step).click() }
        case "rightClick":
            if let point = try windowPoint(step) { point.rightClick() } else { try element(step).rightClick() }
        case "doubleClick":
            if let point = try windowPoint(step) { point.doubleClick() } else { try element(step).doubleClick() }
        case "hover":
            if let point = try windowPoint(step) { point.hover() } else { try element(step).hover() }
            Thread.sleep(forTimeInterval: step.seconds ?? 0.5)
        case "menu":
            guard let path = step.text else { throw DriverError.missing("text") }
            let parts = path.split(separator: ">").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard let top = parts.first else { throw DriverError.missing("text") }
            let bar = app.menuBars.menuBarItems[top]
            guard bar.waitForExistence(timeout: 5) else { throw DriverError.notFound("menu \(top)") }
            bar.click()
            for part in parts.dropFirst() {
                let item = app.menuBars.menuItems[part]
                guard item.waitForExistence(timeout: 5) else { throw DriverError.notFound("menu item \(part)") }
                item.click()
            }
        case "typeText":
            guard let text = step.text else { throw DriverError.missing("text") }
            if step.label != nil {
                let field = try element(step)
                field.click()
                field.typeText(text)
            } else {
                app.typeText(text)
            }
        case "key":
            guard let text = step.text else { throw DriverError.missing("text") }
            app.typeKey(Self.keyName(text), modifierFlags: Self.modifiers(step.modifiers))
        case "scroll":
            try element(step).scroll(byDeltaX: 0, deltaY: CGFloat(-(step.distance ?? 5) * 10))
        case "wait":
            Thread.sleep(forTimeInterval: step.seconds ?? 1)
        case "waitFor", "assertExists":
            _ = try element(step, timeout: step.seconds ?? 5)
        case "assertMissing":
            let query = self.query(step)
            let deadline = Date().addingTimeInterval(step.seconds ?? 2)
            while query.firstMatch.exists, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            if query.firstMatch.exists { throw DriverError.assertion("\(step.label ?? "?") still on screen") }
        case "assertValue":
            let found = try element(step)
            let value = "\(found.value ?? "")"
            guard value == step.text else { throw DriverError.assertion("value \(value) ≠ \(step.text ?? "nil")") }
            return "value=\(value)"
        case "assertEnabled", "assertDisabled":
            let found = try element(step)
            if found.isEnabled != (step.action == "assertEnabled") {
                throw DriverError.assertion("\(step.label ?? "?") enabled=\(found.isEnabled)")
            }
        case "screenshot":
            screenshot(named: step.name ?? "shot-\(results.count)")
        case "dump":
            dump(named: step.name ?? "dump-\(results.count)")
        case "quit":
            app.terminate()
        default:
            throw DriverError.missing("known action (got \(step.action))")
        }
        return describe(step)
    }

    private func query(_ step: Step) -> XCUIElementQuery {
        let type = Self.elementType(step.type)
        let predicate = NSPredicate(format: "label == %@ OR title == %@ OR identifier == %@",
                                    step.label ?? "", step.label ?? "", step.label ?? "")
        return app.descendants(matching: type).matching(predicate)
    }

    private func element(_ step: Step, timeout: Double = 5) throws -> XCUIElement {
        guard step.label != nil else { throw DriverError.missing("label") }
        let match = query(step).element(boundBy: step.index ?? 0)
        guard match.waitForExistence(timeout: timeout) else {
            throw DriverError.notFound("\(step.type ?? "any") \(step.label ?? "")")
        }
        return match
    }

    private func windowPoint(_ step: Step) throws -> XCUICoordinate? {
        guard step.label == nil, let x = step.x, let y = step.y else { return nil }
        return app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    // MARK: Artifacts

    private func screenshot(named name: String) {
        // The window, never the screen: the desktop behind it can show the
        // user's real library in the iOS app.
        let window = app.windows.firstMatch
        guard window.exists else { return }
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dump(named name: String) {
        guard let root = try? app.snapshot() else { return }
        let origin = app.windows.firstMatch.exists ? app.windows.firstMatch.frame.origin : .zero
        var rows: [[String: Any]] = []
        func walk(_ node: XCUIElementSnapshot) {
            let frame = node.frame
            if !(node.label.isEmpty && node.identifier.isEmpty && node.title.isEmpty && node.value == nil)
                || node.elementType == .button {
                rows.append([
                    "type": Self.typeName(node.elementType),
                    "label": node.label.isEmpty ? node.title : node.label,
                    "identifier": node.identifier,
                    "value": node.value.map { "\($0)" } ?? "",
                    "x": Double(frame.minX - origin.x), "y": Double(frame.minY - origin.y),
                    "width": Double(frame.width), "height": Double(frame.height),
                    "enabled": node.isEnabled, "selected": node.isSelected,
                ])
            }
            node.children.forEach(walk)
        }
        walk(root)
        attach(json: rows, named: "\(name).json")
    }

    private func writeReport() {
        attach(json: results, named: "report.json")
    }

    private func attach(json: Any, named name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Names

    private static let types: [String: XCUIElement.ElementType] = [
        "button": .button, "menuButton": .menuButton, "popUpButton": .popUpButton, "checkBox": .checkBox,
        "radioButton": .radioButton, "toggle": .toggle, "switch": .switch, "textField": .textField,
        "searchField": .searchField, "staticText": .staticText, "image": .image, "cell": .cell,
        "outlineRow": .outlineRow, "tableRow": .tableRow, "menuItem": .menuItem, "tab": .tab,
        "sheet": .sheet, "window": .window, "slider": .slider, "segmentedControl": .segmentedControl,
        "popover": .popover, "dialog": .dialog, "link": .link, "group": .group, "toolbar": .toolbar,
        "comboBox": .comboBox, "stepper": .stepper, "disclosureTriangle": .disclosureTriangle,
    ]

    private static func elementType(_ name: String?) -> XCUIElement.ElementType {
        name.flatMap { types[$0] } ?? .any
    }

    private static func typeName(_ type: XCUIElement.ElementType) -> String {
        types.first { $0.value == type }?.key ?? "\(type.rawValue)"
    }

    private static func keyName(_ text: String) -> String {
        switch text {
        case "escape": XCUIKeyboardKey.escape.rawValue
        case "return": XCUIKeyboardKey.return.rawValue
        case "delete": XCUIKeyboardKey.delete.rawValue
        case "tab": XCUIKeyboardKey.tab.rawValue
        case "space": XCUIKeyboardKey.space.rawValue
        case "left": XCUIKeyboardKey.leftArrow.rawValue
        case "right": XCUIKeyboardKey.rightArrow.rawValue
        case "up": XCUIKeyboardKey.upArrow.rawValue
        case "down": XCUIKeyboardKey.downArrow.rawValue
        default: text
        }
    }

    private static func modifiers(_ text: String?) -> XCUIElement.KeyModifierFlags {
        var flags: XCUIElement.KeyModifierFlags = []
        for part in (text ?? "").split(separator: ",") {
            switch part.trimmingCharacters(in: .whitespaces) {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "option": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: break
            }
        }
        return flags
    }
}
