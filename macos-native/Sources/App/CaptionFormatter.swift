import Foundation

public struct CaptionCue: Sendable {
    public let startMs: Int
    public let endMs: Int
    public let text: String

    public init(startMs: Int, endMs: Int, text: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
    }
}

public enum CaptionFormatter {
    public static let pauseMs = 2000
    public static let softParagraphChars = 600
    public static let hardParagraphChars = 1200
    private static let sentenceEndRegex = try! NSRegularExpression(pattern: #"[.!?…]["')\]]*$"#)
    private static let whitespaceRegex = try! NSRegularExpression(pattern: #"\s+"#)

    public static func cuesToParagraphs(_ cues: [CaptionCue]) -> String {
        var paragraphs: [String] = []
        var current: [String] = []
        var currentLength = 0
        var prevEnd: Int? = nil

        func flush() {
            if !current.isEmpty {
                paragraphs.append(current.joined(separator: " "))
                current.removeAll()
                currentLength = 0
            }
        }

        for cue in cues {
            let range = NSRange(location: 0, length: cue.text.utf16.count)
            let cleaned = whitespaceRegex.stringByReplacingMatches(in: cue.text, options: [], range: range, withTemplate: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if cleaned.isEmpty { continue }

            if !current.isEmpty {
                let isPaused = (prevEnd != nil) && (cue.startMs - prevEnd! >= pauseMs)
                let lastText = current.last ?? ""
                let lastRange = NSRange(location: 0, length: lastText.utf16.count)
                let isSentenceEnd = sentenceEndRegex.firstMatch(in: lastText, options: [], range: lastRange) != nil
                let softLimitReached = (currentLength >= softParagraphChars) && isSentenceEnd
                let hardLimitReached = currentLength >= hardParagraphChars

                if isPaused || softLimitReached || hardLimitReached {
                    flush()
                }
            }

            current.append(cleaned)
            currentLength += cleaned.count + 1
            prevEnd = prevEnd == nil ? cue.endMs : max(prevEnd!, cue.endMs)
        }

        flush()
        return paragraphs.joined(separator: "\n\n")
    }
}
