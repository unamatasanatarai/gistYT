import Foundation

public enum SlugGenerator {
    public static let maxSlugLength = 80

    public static func makeSlug(title: String?, videoID: String) -> String {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return videoID
        }

        // Transliterate to Latin / ASCII
        let mutable = NSMutableString(string: title) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        let ascii = (mutable as String).lowercased()

        // Replace non-alphanumeric characters with hyphens
        let pattern = try! NSRegularExpression(pattern: "[^a-z0-9]+")
        let hyphenated = pattern.stringByReplacingMatches(
            in: ascii,
            range: NSRange(location: 0, length: ascii.utf16.count),
            withTemplate: "-"
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if hyphenated.isEmpty {
            return videoID
        }

        if hyphenated.count <= maxSlugLength {
            return hyphenated
        }

        // Truncate at word boundary
        let prefix = String(hyphenated.prefix(maxSlugLength))
        if let lastHyphen = prefix.lastIndex(of: "-") {
            let truncated = String(prefix[..<lastHyphen]).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            return truncated.isEmpty ? videoID : truncated
        }

        return prefix
    }
}
