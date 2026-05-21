import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let appGroupID = "group.com.einstein.common"
    private var didSave = false

    // MARK: - UI
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Saving link…"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("OK", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        handleShare()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(statusLabel)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            doneButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.isEnabled = false
    }

    // MARK: - Share Handling
    private func handleShare() {
        guard
            let items = extensionContext?.inputItems as? [NSExtensionItem]
        else {
            statusLabel.text = "No data"
            doneButton.isEnabled = true
            return
        }

        if let link = linkFromItemText(items) {
            saveAndShowSuccess(link)
            return
        }

        var candidates: [(provider: NSItemProvider, typeIdentifier: String)] = []
        for item in items {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                for typeIdentifier in supportedTypeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                    candidates.append((provider, typeIdentifier))
                }
            }
        }

        loadFirstLink(from: candidates, index: 0)
    }

    // MARK: - Persistence
    private func save(_ link: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        var links = defaults.stringArray(forKey: "SharedLinks") ?? []
        links.append(link)

        defaults.set(links, forKey: "SharedLinks")
        defaults.set(link, forKey: "LastProcessedLink")
        defaults.synchronize()
    }

    private var supportedTypeIdentifiers: [String] {
        [
            UTType.url.identifier,
            UTType.plainText.identifier,
            UTType.text.identifier
        ]
    }

    private func loadFirstLink(from candidates: [(provider: NSItemProvider, typeIdentifier: String)], index: Int) {
        guard index < candidates.count else {
            DispatchQueue.main.async {
                self.statusLabel.text = "No link found"
                self.doneButton.isEnabled = true
            }
            return
        }

        let candidate = candidates[index]
        candidate.provider.loadItem(forTypeIdentifier: candidate.typeIdentifier, options: nil) { [weak self] item, _ in
            guard let self = self else { return }

            if let link = self.extractLink(from: item) {
                self.saveAndShowSuccess(link)
            } else {
                self.loadFirstLink(from: candidates, index: index + 1)
            }
        }
    }

    private func saveAndShowSuccess(_ link: String) {
        guard !didSave else { return }
        didSave = true

        save(link)

        DispatchQueue.main.async {
            self.statusLabel.text = "Link saved ✓"
            self.doneButton.isEnabled = true
        }
    }

    private func linkFromItemText(_ items: [NSExtensionItem]) -> String? {
        for item in items {
            if let link = extractFirstURL(in: item.attributedContentText?.string) {
                return link
            }

            if let link = extractFirstURL(in: item.attributedTitle?.string) {
                return link
            }
        }

        return nil
    }

    private func extractLink(from item: NSSecureCoding?) -> String? {
        if let url = item as? URL {
            return url.absoluteString
        }

        if let url = item as? NSURL {
            return url.absoluteString
        }

        if let string = item as? String {
            return extractFirstURL(in: string) ?? normalizedURLString(string)
        }

        if let string = item as? NSString {
            return extractFirstURL(in: string as String) ?? normalizedURLString(string as String)
        }

        if let attributedString = item as? NSAttributedString {
            return extractFirstURL(in: attributedString.string)
        }

        return nil
    }

    private func normalizedURLString(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }

        return url.absoluteString
    }

    private func extractFirstURL(in text: String?) -> String? {
        guard let text = text, !text.isEmpty else { return nil }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let urls = detector?.matches(in: text, options: [], range: range).compactMap { $0.url } ?? []

        let preferredURL = urls.first { url in
            url.host?.lowercased().contains("linkedin.com") == true
        } ?? urls.first

        return preferredURL?.absoluteString
    }

    // MARK: - Close
    @objc private func doneTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
