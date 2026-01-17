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

        for item in items {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {

                    provider.loadItem(
                        forTypeIdentifier: UTType.url.identifier,
                        options: nil
                    ) { [weak self] item, _ in
                        guard let self = self, !self.didSave else { return }
                        self.didSave = true

                        if let url = item as? URL {
                            self.save(url.absoluteString)
                        } else if let str = item as? String {
                            self.save(str)
                        }

                        DispatchQueue.main.async {
                            self.statusLabel.text = "Link saved ✓"
                            self.doneButton.isEnabled = true
                        }
                    }
                    return
                }
            }
        }

        statusLabel.text = "No link found"
        doneButton.isEnabled = true
    }

    // MARK: - Persistence
    private func save(_ link: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        var links = defaults.stringArray(forKey: "SharedLinks") ?? []
        links.append(link)

        defaults.set(links, forKey: "SharedLinks")
        defaults.set(link, forKey: "LastProcessedLink")
    }

    // MARK: - Close
    @objc private func doneTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

