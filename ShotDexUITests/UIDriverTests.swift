import XCTest

/// Drives the app from a JSON script and writes screenshots and element
/// dumps to a folder, so a review agent with nothing but `Bash` can press a
/// button and then measure what it pressed.
///
/// It is not a regression test and it is deliberately not in the `ShotDex`
/// scheme: `xcodebuild test -scheme ShotDex` still runs the unit tests and
/// only the unit tests. Run it through its own scheme:
///
/// ```
/// Tools/ui-drive <udid> path/to/script.json /tmp/out
/// ```
///
/// With no `SHOTDEX_UI_SCRIPT` in the environment it launches the app, dumps
/// the first screen and stops — which is the useful default when all you want
/// is "show me what is on screen and how big it is".
final class UIDriverTests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!
    private var artifacts: [String] = []
    private var results: [UIDriverStepResult] = []
    private var hasWrittenReport = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        let path = ProcessInfo.processInfo.environment["SHOTDEX_UI_OUT"]
            ?? NSTemporaryDirectory().appending("shotdex-ui")
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // A step can fail in a way that never reaches the catch — a timeout
        // inside XCTest itself, for one — and a run with no report at all is
        // the one failure mode that tells the caller nothing.
        if !hasWrittenReport { writeReport() }
    }

    func testRunScript() throws {
        let steps = try loadSteps()
        for (index, step) in steps.enumerated() {
            do {
                let detail = try perform(step)
                results.append(UIDriverStepResult(index: index, action: step.action, detail: detail, failure: nil))
            } catch {
                results.append(
                    UIDriverStepResult(
                        index: index,
                        action: step.action,
                        detail: describe(step),
                        failure: "\(error)"
                    )
                )
                // Stop at the first failure but still write the report: the
                // dump of the screen the script got stuck on is the answer.
                write(name: "stuck", tree: tree())
                screenshot(named: "stuck")
                writeReport()
                XCTFail("step \(index) (\(step.action) \(describe(step))) failed: \(error)")
                return
            }
        }
        writeReport()
    }

    // MARK: Script

    private func loadSteps() throws -> [UIDriverStep] {
        // `xcodebuild`'s `TEST_RUNNER_` environment does not reach a UI test
        // runner on this toolchain — measured, the runner's environment comes
        // through empty — so `Tools/ui-drive` copies the script into the test
        // bundle's resources before it builds, and that is the real channel.
        if let url = Bundle(for: Self.self).url(forResource: "driver-script", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            return try JSONDecoder().decode(UIDriverScript.self, from: data).steps
        }
        guard let path = ProcessInfo.processInfo.environment["SHOTDEX_UI_SCRIPT"], !path.isEmpty else {
            return [
                UIDriverStep(action: "launch", label: nil, type: nil, index: nil, x: nil, y: nil,
                             direction: nil, distance: nil, text: nil, seconds: nil, name: nil, arguments: nil, hittable: nil),
                UIDriverStep(action: "screenshot", label: nil, type: nil, index: nil, x: nil, y: nil,
                             direction: nil, distance: nil, text: nil, seconds: nil, name: "launch", arguments: nil, hittable: nil),
                UIDriverStep(action: "dump", label: nil, type: nil, index: nil, x: nil, y: nil,
                             direction: nil, distance: nil, text: nil, seconds: nil, name: "launch", arguments: nil, hittable: nil),
            ]
        }
        // The test runs inside the simulator, which cannot see a path on the
        // Mac, so `Tools/ui-drive` passes the script's *contents*. A path is
        // still accepted for a script that lives in the runner's own sandbox.
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = trimmed.hasPrefix("{")
            ? Data(trimmed.utf8)
            : try Data(contentsOf: URL(fileURLWithPath: trimmed))
        return try JSONDecoder().decode(UIDriverScript.self, from: data).steps
    }

    private func describe(_ step: UIDriverStep) -> String {
        var parts: [String] = []
        if let label = step.label { parts.append("label=\(label)") }
        if let type = step.type { parts.append("type=\(type)") }
        if let index = step.index { parts.append("index=\(index)") }
        if let x = step.x, let y = step.y { parts.append("at=(\(x), \(y))") }
        if let direction = step.direction { parts.append("direction=\(direction)") }
        if let name = step.name { parts.append("name=\(name)") }
        return parts.joined(separator: " ")
    }

    // MARK: Actions

    private func perform(_ step: UIDriverStep) throws -> String {
        switch step.action {
        case "launch":
            app.launchArguments = step.arguments ?? []
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 30)
        case "activate":
            app.activate()
        case "tap", "tapIndex":
            if let point = coordinate(for: step) {
                point.tap()
            } else {
                try element(for: step).tap()
            }
        case "longPress":
            if let point = coordinate(for: step) {
                point.press(forDuration: step.seconds ?? 1.0)
            } else {
                try element(for: step).press(forDuration: step.seconds ?? 1.0)
            }
        case "typeText":
            guard let text = step.text else { throw DriverError.missing("text") }
            if step.label != nil {
                let field = try element(for: step)
                field.tap()
                field.typeText(text)
            } else {
                app.typeText(text)
            }
        case "swipe":
            // A point drag when the step gives coordinates: the element
            // swipes start at the element's centre, and on a panel with a
            // control in the middle that is a gesture on the control, not a
            // scroll of the panel.
            if let start = coordinate(for: step) {
                let span = step.distance ?? 0.25
                let (dx, dy): (Double, Double) = switch step.direction ?? "up" {
                case "down": (0, span)
                case "left": (-span, 0)
                case "right": (span, 0)
                default: (0, -span)
                }
                let end = app.coordinate(
                    withNormalizedOffset: CGVector(
                        dx: (step.x ?? 0) + dx,
                        dy: (step.y ?? 0) + dy
                    )
                )
                start.press(forDuration: 0.05, thenDragTo: end)
                break
            }
            let target: XCUIElement = step.label == nil ? app : try element(for: step)
            switch step.direction ?? "up" {
            case "down": target.swipeDown()
            case "left": target.swipeLeft()
            case "right": target.swipeRight()
            default: target.swipeUp()
            }
        case "scrollTo":
            let target = try element(for: step)
            var attempts = 0
            while !target.isHittable && attempts < 12 {
                app.swipeUp()
                attempts += 1
            }
            guard target.isHittable else { throw DriverError.notHittable(step.label ?? "?") }
        case "systemTap":
            // A permission alert belongs to Springboard, not to the app: it is
            // absent from the app's element tree, and a coordinate tap at its
            // buttons goes to the app *underneath* it. So the photo-access
            // prompt — which every fresh install shows, because installing the
            // app resets its privacy grant — can only be answered through
            // Springboard's own query.
            guard let label = step.label else { throw DriverError.missing("label") }
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let button = springboard.buttons[label]
            guard button.waitForExistence(timeout: step.seconds ?? 15) else {
                throw DriverError.notFound("system button '\(label)'")
            }
            button.tap()
        case "wait":
            Thread.sleep(forTimeInterval: step.seconds ?? 1.0)
        case "screenshot":
            screenshot(named: step.name ?? "screen")
        case "dump":
            // `type` narrows the dump to one kind of element. Worth reaching
            // for: the accessibility snapshot of a screen whose content never
            // settles can time the whole query out (measured on the Video
            // Studio on the phone, where even `app.buttons` never returns).
            write(
                name: step.name ?? "tree",
                tree: tree(
                    everything: step.text == "all",
                    only: step.type,
                    hittable: step.hittable ?? false
                )
            )
        case "back":
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { throw DriverError.notFound("back button") }
            back.tap()
        case "home":
            XCUIDevice.shared.press(.home)
        case "orientation":
            // iPad is not orientation-locked, and a 16:9 editor looks like a
            // different screen rotated; a layout pass that only ever saw
            // portrait has only seen half the job.
            switch step.text ?? "portrait" {
            case "landscape", "landscapeLeft": XCUIDevice.shared.orientation = .landscapeLeft
            case "landscapeRight": XCUIDevice.shared.orientation = .landscapeRight
            case "portraitUpsideDown": XCUIDevice.shared.orientation = .portraitUpsideDown
            default: XCUIDevice.shared.orientation = .portrait
            }
            Thread.sleep(forTimeInterval: 1.5)
        default:
            throw DriverError.unknownAction(step.action)
        }
        return describe(step)
    }

    private enum DriverError: Error, CustomStringConvertible {
        case unknownAction(String)
        case missing(String)
        case notFound(String)
        case notHittable(String)
        case ambiguousCoordinates

        var description: String {
            switch self {
            case .unknownAction(let name): "unknown action '\(name)'"
            case .missing(let field): "step is missing '\(field)'"
            case .notFound(let what): "no element matching \(what)"
            case .notHittable(let what): "\(what) never became hittable"
            case .ambiguousCoordinates: "step needs either a label or x and y"
            }
        }
    }

    // MARK: Elements

    private func element(for step: UIDriverStep) throws -> XCUIElement {
        if let label = step.label {
            let query = queryForType(step.type)
            // An exact label or identifier wins over a prefix: "Photo, file type
            // JPG" names the one photo with no EXIF line, and as a prefix it
            // would match every JPEG in the grid.
            let exact = query.matching(NSPredicate(
                format: "label ==[c] %@ OR identifier ==[c] %@", label, label
            ))
            let matches = exact.firstMatch.exists
                ? exact
                : query.matching(NSPredicate(format: "label BEGINSWITH[c] %@", label))
            let first = matches.element(boundBy: step.index ?? 0)
            guard first.waitForExistence(timeout: step.seconds ?? 10) else {
                throw DriverError.notFound("'\(label)'\(step.type.map { " of type \($0)" } ?? "")")
            }
            // An explicit index is the script choosing; otherwise, of several
            // matches, take the one a finger can reach. A sheet's Cancel and
            // the commit bar's Cancel behind its dimming view share a label,
            // and the covered one can come first: tapping it lands on the dim
            // (Duo 27.1: nothing happens) or waits for hittability forever
            // (iPad 18.6). Capped, because every `isHittable` is a hit test.
            guard step.index == nil else { return first }
            let count = min(matches.count, 8)
            guard count > 1 else { return first }
            for index in 0..<count {
                let candidate = matches.element(boundBy: index)
                if candidate.isHittable { return candidate }
            }
            return first
        }
        throw DriverError.ambiguousCoordinates
    }

    /// Normalized (0…1), so one script runs on a phone and on a 13" iPad.
    /// Only used when a step gives no label — a label is always the better
    /// answer, because it survives a layout change and a coordinate does not.
    private func coordinate(for step: UIDriverStep) -> XCUICoordinate? {
        guard step.label == nil, let x = step.x, let y = step.y else { return nil }
        return app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func queryForType(_ type: String?) -> XCUIElementQuery {
        switch type {
        case "button": app.buttons
        case "cell": app.cells
        case "image": app.images
        case "staticText": app.staticTexts
        case "textField": app.textFields
        case "searchField": app.searchFields
        case "switch": app.switches
        case "slider": app.sliders
        case "tab": app.tabBars.buttons
        case "menuItem": app.menuItems
        case "other": app.otherElements
        default: app.descendants(matching: .any)
        }
    }

    // MARK: Output

    /// Cap for the whole-tree dump. Walking every descendant of a
    /// canvas-heavy screen is the slowest thing the driver does, and XCTest
    /// times the query out rather than returning a partial answer — measured
    /// on the Video Studio, where a `.any` walk never came back.
    private static let maxDumpedElements = 400

    /// The types a layout review actually measures. Asking for these by kind
    /// is bounded work; asking for `.any` is a walk of every SwiftUI
    /// container on the screen, which the Video Studio does not survive.
    private var dumpQueries: [XCUIElementQuery] {
        [
            app.buttons, app.staticTexts, app.images, app.cells, app.switches,
            app.sliders, app.textFields, app.searchFields, app.segmentedControls,
            app.navigationBars, app.tabBars, app.toolbars, app.sheets, app.alerts,
        ]
    }

    /// `text: "all"` on a dump step asks for the whole tree instead, capped.
    ///
    /// Every property read here is its own round trip into the app, and
    /// `isHittable` is by far the dearest of them — it does a hit test.
    /// Measured on the Video Studio on the phone: the dump never returned,
    /// while `sample` showed the app's main thread **idle** the whole time,
    /// so the cost was the driver asking, not the app thinking. `isHittable`
    /// is opt-in now (`hittable: true` on the step) and every dump is capped,
    /// so a screen with a lot on it returns a short answer instead of no
    /// answer.
    private func tree(
        everything: Bool = false,
        only type: String? = nil,
        hittable: Bool = false
    ) -> [UIDriverElement] {
        let elements: [XCUIElement]
        if let type {
            elements = queryForType(type).allElementsBoundByIndex
        } else if everything {
            elements = app.descendants(matching: .any).allElementsBoundByIndex
        } else {
            elements = dumpQueries.flatMap(\.allElementsBoundByIndex)
        }
        return elements.prefix(Self.maxDumpedElements).compactMap { element in
            guard element.exists else { return nil }
            let frame = element.frame
            guard frame.width > 0, frame.height > 0 else { return nil }
            return UIDriverElement(
                type: Self.name(of: element.elementType),
                label: element.label,
                identifier: element.identifier,
                value: element.value as? String,
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.width,
                height: frame.height,
                enabled: element.isEnabled,
                selected: element.isSelected,
                hittable: hittable ? element.isHittable : nil
            )
        }
    }

    /// `XCUIElement.ElementType` has no string form, and a dump full of raw
    /// enum numbers is a dump nobody reads.
    private static func name(of type: XCUIElement.ElementType) -> String {
        switch type {
        case .any: "any"
        case .other: "other"
        case .application: "application"
        case .group: "group"
        case .window: "window"
        case .sheet: "sheet"
        case .drawer: "drawer"
        case .alert: "alert"
        case .dialog: "dialog"
        case .button: "button"
        case .radioButton: "radioButton"
        case .checkBox: "checkBox"
        case .disclosureTriangle: "disclosureTriangle"
        case .popUpButton: "popUpButton"
        case .menuButton: "menuButton"
        case .toolbarButton: "toolbarButton"
        case .popover: "popover"
        case .keyboard: "keyboard"
        case .key: "key"
        case .navigationBar: "navigationBar"
        case .tabBar: "tabBar"
        case .tabGroup: "tabGroup"
        case .toolbar: "toolbar"
        case .statusBar: "statusBar"
        case .table: "table"
        case .tableRow: "tableRow"
        case .outline: "outline"
        case .browser: "browser"
        case .collectionView: "collectionView"
        case .slider: "slider"
        case .pageIndicator: "pageIndicator"
        case .progressIndicator: "progressIndicator"
        case .activityIndicator: "activityIndicator"
        case .segmentedControl: "segmentedControl"
        case .picker: "picker"
        case .pickerWheel: "pickerWheel"
        case .switch: "switch"
        case .toggle: "toggle"
        case .link: "link"
        case .image: "image"
        case .icon: "icon"
        case .searchField: "searchField"
        case .scrollView: "scrollView"
        case .scrollBar: "scrollBar"
        case .staticText: "staticText"
        case .textField: "textField"
        case .secureTextField: "secureTextField"
        case .textView: "textView"
        case .menu: "menu"
        case .menuItem: "menuItem"
        case .menuBar: "menuBar"
        case .menuBarItem: "menuBarItem"
        case .map: "map"
        case .webView: "webView"
        case .cell: "cell"
        case .stepper: "stepper"
        case .datePicker: "datePicker"
        case .layoutArea: "layoutArea"
        case .layoutItem: "layoutItem"
        case .handle: "handle"
        case .touchBar: "touchBar"
        case .statusItem: "statusItem"
        case .ratingIndicator: "ratingIndicator"
        case .valueIndicator: "valueIndicator"
        case .splitGroup: "splitGroup"
        case .splitter: "splitter"
        case .relevanceIndicator: "relevanceIndicator"
        case .colorWell: "colorWell"
        case .helpTag: "helpTag"
        case .matte: "matte"
        case .dockItem: "dockItem"
        case .ruler: "ruler"
        case .rulerMarker: "rulerMarker"
        case .grid: "grid"
        case .levelIndicator: "levelIndicator"
        case .timeline: "timeline"
        case .incrementArrow: "incrementArrow"
        case .decrementArrow: "decrementArrow"
        @unknown default: "type\(type.rawValue)"
        }
    }

    /// The app's own window, not `XCUIScreen.main`. On a dual-screen device
    /// `main` is whichever display the system calls main, which on the iPhone
    /// Duo is the one that is switched off — every screenshot came back
    /// black. The app's screenshot also follows the interface orientation,
    /// so a landscape capture is landscape rather than a rotated portrait
    /// frame.
    private func screenshot(named name: String) {
        let shot = app.exists ? app.screenshot() : XCUIScreen.main.screenshot()
        emit(name: "\(name).png", data: shot.pngRepresentation, uniformTypeIdentifier: "public.png")
    }

    private func write(name: String, tree: [UIDriverElement]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(tree) else { return }
        emit(name: "\(name).json", data: data, uniformTypeIdentifier: "public.json")
    }

    /// The test runs *in the simulator*, so a path on the Mac is not a path
    /// this process can write to. Everything leaves as an XCTest attachment
    /// and `Tools/ui-drive` exports the result bundle; the write to
    /// `SHOTDEX_UI_OUT` is kept for the case where the sandbox does allow it.
    private func emit(name: String, data: Data, uniformTypeIdentifier: String) {
        let attachment = XCTAttachment(uniformTypeIdentifier: uniformTypeIdentifier, name: name, payload: data)
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outputDirectory.appendingPathComponent(name))
        artifacts.append(name)
    }

    private func writeReport() {
        hasWrittenReport = true
        let screen = XCUIApplication().frame
        let ours = ProcessInfo.processInfo.environment.filter { $0.key.contains("SHOTDEX") }
            .mapValues { $0.count > 120 ? "\($0.prefix(120))… (\($0.count) chars)" : $0 }
        let report = UIDriverReport(
            screen: [screen.width, screen.height],
            steps: results,
            artifacts: artifacts,
            environment: ours
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        let attachment = XCTAttachment(uniformTypeIdentifier: "public.json", name: "report.json", payload: data)
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outputDirectory.appendingPathComponent("report.json"))
    }
}
