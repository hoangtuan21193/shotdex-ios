// Renders one Design-canvas artboard with WebKit and writes its PNG and its
// element frames. Compiled and called by Tools/design-board; not run alone.
//
//   design-board-render <board.html> <width> <height> <out.png> <out.json> <probe.js>
//
// WebKit, not a headless Chromium: it ships with macOS, so the tool works on
// any Mac that builds the app, and it does not fight a browser the user has
// open. The window is off-screen and 1x so one CSS px is one point.
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 7, let width = Double(args[2]), let height = Double(args[3]) else {
    FileHandle.standardError.write("usage: design-board-render <board.html> <w> <h> <out.png> <out.json> <probe.js>\n".data(using: .utf8)!)
    exit(64)
}
let board = URL(fileURLWithPath: args[1])
let pngURL = URL(fileURLWithPath: args[4])
let jsonURL = URL(fileURLWithPath: args[5])
let probe = (try? String(contentsOfFile: args[6], encoding: .utf8)) ?? "[]"

final class Renderer: NSObject, WKNavigationDelegate {
    let view: WKWebView
    let window: NSWindow
    var failed = false

    init(size: CGSize) {
        view = WKWebView(frame: CGRect(origin: .zero, size: size))
        window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.contentView = view
        window.orderBack(nil)
        view.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Fonts and SVG settle a frame after load.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.capture() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }

    func fail(_ error: Error) {
        FileHandle.standardError.write("load failed: \(error.localizedDescription)\n".data(using: .utf8)!)
        failed = true
        exit(1)
    }

    func capture() {
        view.evaluateJavaScript(probe) { result, error in
            if let json = result as? String {
                try? json.write(to: jsonURL, atomically: true, encoding: .utf8)
            } else if let error {
                FileHandle.standardError.write("probe failed: \(error)\n".data(using: .utf8)!)
            }
            let config = WKSnapshotConfiguration()
            config.rect = self.view.bounds
            config.snapshotWidth = NSNumber(value: Double(self.view.bounds.width))
            self.view.takeSnapshot(with: config) { image, error in
                guard let image, let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write("snapshot failed: \(String(describing: error))\n".data(using: .utf8)!)
                    exit(1)
                }
                try? png.write(to: pngURL)
                exit(0)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer(size: CGSize(width: width, height: height))
renderer.view.loadFileURL(board, allowingReadAccessTo: board.deletingLastPathComponent())
DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    FileHandle.standardError.write("timed out\n".data(using: .utf8)!)
    exit(2)
}
app.run()
