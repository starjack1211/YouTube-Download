import UIKit
import SwiftUI

final class ShareViewController: UIViewController {
    private var loaded = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !loaded else { return }
        loaded = true
        Task { @MainActor in
            let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
            let text = await SharedLinkReader.read(items: items)
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
}
