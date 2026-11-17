import Foundation
import UniformTypeIdentifiers

enum SharedLinkReader {
    static func read(items: [NSExtensionItem]) async -> String {
        for item in items {
            for provider in item.attachments ?? [] {
                // Typed loading handles the secure URL representation used by iOS.
                if provider.canLoadObject(ofClass: NSURL.self) {
                    let text: String = await withCheckedContinuation { continuation in
                        provider.loadObject(ofClass: NSURL.self) { value, _ in
                            continuation.resume(returning: (value as? NSURL)?.absoluteString ?? "")
                        }
                    }
                    if YouTubeLink.videoID(in: text) != nil { return text }
                }
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
