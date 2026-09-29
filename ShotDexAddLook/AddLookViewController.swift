import UIKit
import UniformTypeIdentifiers

/// "Add to ShotDex" in the share sheet, for `.shotdexlook` files only
/// (FS-03.14c §4). It checks sizes and copies bytes into the App Group's
/// waiting room — no parsing, no rendering, so it stays far under an
/// extension's memory ceiling — and the app imports them when it next opens.
final class AddLookViewController: UIViewController {
    private let message = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        message.numberOfLines = 0
        message.textAlignment = .center
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.translatesAutoresizingMaskIntoConstraints = false
        let done = UIButton(type: .system, primaryAction: UIAction(title: String(localized: "Done")) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        let stack = UIStackView(arrangedSubviews: [message, done])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        Task { await run() }
    }

    private func run() async {
        guard let directory = LookInboxLocation.pendingDirectory() else {
            show(String(localized: "ShotDex couldn't be reached. Open the file from Files instead."))
            return
        }
        var deposit = LookInboxLocation.Deposit()
        for provider in providers() {
            let one = await withCheckedContinuation { (continuation: CheckedContinuation<LookInboxLocation.Deposit, Never>) in
                // The URL only lives inside this callback: copy before returning.
                _ = provider.loadFileRepresentation(forTypeIdentifier: "com.hoangtuan.shotdex.look") { url, _ in
                    continuation.resume(returning: url.map { LookInboxLocation.deposit([$0], into: directory) } ?? .init())
                }
            }
            deposit.added += one.added
            deposit.refused += one.refused
        }
        var lines: [String] = []
        if deposit.added > 0 { lines.append(String(localized: "Added. Open ShotDex to use it.")) }
        lines += deposit.refused.map(\.message)
        show(lines.joined(separator: "\n"))
    }

    private func providers() -> [NSItemProvider] {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        return items.flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier("com.hoangtuan.shotdex.look") }
    }

    @MainActor
    private func show(_ text: String) {
        message.text = text
    }
}
