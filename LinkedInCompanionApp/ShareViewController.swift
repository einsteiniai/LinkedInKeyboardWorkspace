import UIKit
import Social
import MobileCoreServices

final class ShareViewController: SLComposeServiceViewController {
    // MARK: - Validation
    override func isContentValid() -> Bool {
        // You can add validation logic if needed; return true to allow posting
        return true
    }

    // MARK: - Handle Post Action
    override func didSelectPost() {
        // Called when the user taps Post in the share sheet
        processFirstURLAndSave { [weak self] in
            self?.complete()
        }
    }

    // MARK: - Configuration (optional)
    override func configurationItems() -> [Any]! {
        // No additional configuration items
        return []
    }

    // MARK: - Core processing
    private func processFirstURLAndSave(completion: @escaping () -> Void) {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments, !attachments.isEmpty else {
            completion()
            return
        }

        // Find first URL provider
        if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(kUTTypeURL as String) }) {
            provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { item, error in
                if let url = item as? URL {
                    self.save(url: url)
                }
                // Always complete regardless of success or failure
                completion()
            }
        } else {
            completion()
        }
    }

    private func save(url: URL) {
        let suiteName = "group.com.einstein.common"
        guard let sharedDefaults = UserDefaults(suiteName: suiteName) else { return }

        // Save last processed link
        let link = url.absoluteString
        sharedDefaults.set(link, forKey: "LastProcessedLink")

        // Append to shared links list
        var links = sharedDefaults.stringArray(forKey: "SharedLinks") ?? []
        links.append(link)
        sharedDefaults.set(links, forKey: "SharedLinks")

        sharedDefaults.synchronize()
    }

    // MARK: - Dismiss helper
    private func complete() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
