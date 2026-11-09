import Foundation

public enum VideoIDParser {
    private static let idRegex = try! NSRegularExpression(pattern: "^[0-9A-Za-z_-]{11}$")
    private static let validHosts: Set<String> = [
        "youtube.com", "m.youtube.com", "music.youtube.com",
        "youtube-nocookie.com", "youtubekids.com", "m.youtubekids.com"
    ]
    private static let pathPrefixes = ["shorts", "embed", "live", "v", "e"]

    public static func parseVideoID(from rawInput: String) -> String? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if is11CharID(trimmed) { return trimmed }

        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }

        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        if host == "youtu.be", let first = segments.first, is11CharID(first) {
            return first
        }

        guard validHosts.contains(host) else { return nil }

        if segments.first == "watch" {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            if let v = queryItems?.first(where: { $0.name == "v" })?.value, is11CharID(v) {
                return v
            }
        }

        if segments.count >= 2, pathPrefixes.contains(segments[0]), is11CharID(segments[1]) {
            return segments[1]
        }

        return nil
    }

    private static func is11CharID(_ string: String) -> Bool {
        let range = NSRange(location: 0, length: string.utf16.count)
        return idRegex.firstMatch(in: string, options: [], range: range) != nil
    }

    public static func watchURL(for videoID: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }
}
