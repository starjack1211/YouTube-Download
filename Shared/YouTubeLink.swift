import Foundation

enum YouTubeLink {
    static func videoID(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let ns = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = match.url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host?.lowercased(), let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            let parts = url.path.split(separator: "/").map(String.init)
            let id: String?
            if host == "youtu.be" { id = parts.first }
            else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
                if parts.first == "watch" { id = c.queryItems?.first(where: { $0.name == "v" })?.value }
                else if ["shorts", "live", "embed"].contains(parts.first ?? ""), parts.count > 1 { id = parts[1] }
                else { id = nil }
            } else { id = nil }
            if let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil { return id }
        }
        return nil
    }
}
