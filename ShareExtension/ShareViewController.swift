import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var loaded = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !loaded else { return }
        loaded = true
        Task { @MainActor in
            let text = await readSharedLink()
            let host = UIHostingController(rootView: DownloadView(link: text, isShare: true) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            host.didMove(toParent: self)
        }
    }

    private func readSharedLink() async -> String {
        for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            for provider in item.attachments ?? [] {
                for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                    let text: String = await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                            if let url = value as? URL { continuation.resume(returning: url.absoluteString) }
                            else if let string = value as? String { continuation.resume(returning: string) }
                            else if let data = value as? Data, let string = String(data: data, encoding: .utf8) {
                                continuation.resume(returning: string)
                            } else { continuation.resume(returning: "") }
                        }
                    }
                    if YouTubeLink.videoID(in: text) != nil { return text }
                }
            }
            if let text = item.attributedContentText?.string, YouTubeLink.videoID(in: text) != nil { return text }
        }
        return ""
    }
}
