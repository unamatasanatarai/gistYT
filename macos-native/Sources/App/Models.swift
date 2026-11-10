import Foundation

public struct VideoMetadata: Sendable {
    public let videoID: String
    public let title: String?
    public let channel: String?
    public let duration: Int? // seconds

    public init(videoID: String, title: String?, channel: String?, duration: Int?) {
        self.videoID = videoID
        self.title = title
        self.channel = channel
        self.duration = duration
    }
}

public struct CaptionTrackInfo: Sendable {
    public let languageCode: String
    public let vssId: String?
    public let name: String?
    public let kind: String // "manual" or "auto"
    public let baseUrl: String

    public init(languageCode: String, vssId: String?, name: String?, kind: String, baseUrl: String) {
        self.languageCode = languageCode
        self.vssId = vssId
        self.name = name
        self.kind = kind
        self.baseUrl = baseUrl
    }

    public var label: String {
        return "\(languageCode) (\(kind))"
    }
}

public struct TranscriptResult: Sendable {
    public let videoID: String
    public let title: String?
    public let channel: String?
    public let duration: Int?
    public let captions: String
    public let text: String

    public init(videoID: String, title: String?, channel: String?, duration: Int?, captions: String, text: String) {
        self.videoID = videoID
        self.title = title
        self.channel = channel
        self.duration = duration
        self.captions = captions
        self.text = text
    }
}

public struct VideoSummary: Codable, Sendable {
    public let tldr: String
    public let summary: String
    public let keyPoints: [String]
    public let notableQuotes: [String]
    public let topics: [String]

    public init(tldr: String, summary: String, keyPoints: [String], notableQuotes: [String], topics: [String]) {
        self.tldr = tldr
        self.summary = summary
        self.keyPoints = keyPoints
        self.notableQuotes = notableQuotes
        self.topics = topics
    }

    enum CodingKeys: String, CodingKey {
        case tldr
        case summary
        case keyPoints = "key_points"
        case notableQuotes = "notable_quotes"
        case topics
    }
}

public struct SavedSummaryItem: Identifiable, Sendable {
    public var id: String { slug }
    public let slug: String
    public var title: String
    public var channel: String?
    public let date: Date
    public let summaryPath: URL?
    public let transcriptPath: URL?
    public var isLoading: Bool
    public var videoID: String?

    public init(slug: String, title: String, channel: String?, date: Date, summaryPath: URL?, transcriptPath: URL?, isLoading: Bool = false, videoID: String? = nil) {
        self.slug = slug
        self.title = title
        self.channel = channel
        self.date = date
        self.summaryPath = summaryPath
        self.transcriptPath = transcriptPath
        self.isLoading = isLoading
        self.videoID = videoID
    }
}

/// True when `error` means the surrounding task was cancelled. URLSession reports
/// cancellation as URLError(.cancelled) rather than CancellationError.
func isCancellationError(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return Task.isCancelled
}
