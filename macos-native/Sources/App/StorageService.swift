import Foundation

public actor StorageService {
    public static let shared = StorageService()

    public static var defaultBaseDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let newDir = docs.appendingPathComponent("gistYT", isDirectory: true)
        let oldDir = docs.appendingPathComponent("GistYT", isDirectory: true)
        if FileManager.default.fileExists(atPath: oldDir.path) && !FileManager.default.fileExists(atPath: newDir.path) {
            return oldDir
        }
        return newDir
    }

    public func ensureDirectories(base: URL) throws -> (transcriptions: URL, summaries: URL) {
        let transcriptions = base.appendingPathComponent("transcriptions", isDirectory: true)
        let summaries = base.appendingPathComponent("summaries", isDirectory: true)

        try FileManager.default.createDirectory(at: transcriptions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: summaries, withIntermediateDirectories: true)

        return (transcriptions, summaries)
    }

    /// Slugs come from titles, so two different videos can share one ("Episode 1").
    /// Returns `slug` when it is free or already belongs to `videoID`; otherwise
    /// `slug-<videoID>`, which is unique per video. A file whose owner can't be
    /// read is treated as someone else's, so it is never overwritten.
    ///
    /// Each returned slug is also claimed for `videoID`, so concurrent jobs for two
    /// same-titled videos can't both pick the same free slug before either has written
    /// its files. The check and the claim are atomic because this is an actor method
    /// with no suspension points.
    public func uniqueSlug(_ slug: String, videoID: String, transcriptions: URL, summaries: URL) -> String {
        let chosen = isSlugAvailable(slug, for: videoID, transcriptions: transcriptions, summaries: summaries)
            ? slug
            : "\(slug)-\(videoID)"
        claimedSlugs[chosen.lowercased()] = videoID
        return chosen
    }

    /// Slug (lowercased: the default macOS volume is case-insensitive) -> video that claimed it.
    private var claimedSlugs: [String: String] = [:]

    private func isSlugAvailable(_ slug: String, for videoID: String, transcriptions: URL, summaries: URL) -> Bool {
        if let owner = claimedSlugs[slug.lowercased()], owner != videoID {
            return false
        }
        let existing = [
            summaries.appendingPathComponent("\(slug).md"),
            transcriptions.appendingPathComponent("\(slug).txt")
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
        return existing.allSatisfy { Self.videoID(inFileAt: $0) == videoID }
    }

    /// The video ID from the first watch URL in a saved file's header.
    public static func videoID(inFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let data = handle.readData(ofLength: 4096)
        try? handle.close()
        guard let header = String(data: data, encoding: .utf8) else { return nil }
        if let marker = header.range(of: "youtube.com/watch?v=") {
            let id = header[marker.upperBound...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
            if id.count == 11 { return String(id) }
        }
        for line in header.components(separatedBy: .newlines).prefix(15) {
            for word in line.components(separatedBy: .whitespaces) {
                if (word.contains("youtube.com") || word.contains("youtu.be")),
                   let parsed = VideoIDParser.parseVideoID(from: word) {
                    return parsed
                }
            }
        }
        return nil
    }

    public func saveTranscript(
        result: TranscriptResult,
        slug: String,
        directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(slug).txt")

        var headerLines: [String] = []
        headerLines.append("Title: \(result.title ?? "(unknown)")")
        if let ch = result.channel, !ch.isEmpty {
            headerLines.append("Channel: \(ch)")
        }
        headerLines.append("URL: \(VideoIDParser.watchURL(for: result.videoID).absoluteString)")
        if let dur = DurationFormatter.format(seconds: result.duration) {
            headerLines.append("Duration: \(dur)")
        }
        headerLines.append("Captions: \(result.captions)")

        let fullContent = headerLines.joined(separator: "\n") + "\n\n" + result.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try fullContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    public func saveSummary(
        markdown: String,
        slug: String,
        directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(slug).md")
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    public func deleteSummaryItem(_ item: SavedSummaryItem) throws {
        var pathsToTrash: [URL] = []
        if let sumPath = item.summaryPath, FileManager.default.fileExists(atPath: sumPath.path) {
            pathsToTrash.append(sumPath)
        }
        if let transPath = item.transcriptPath, FileManager.default.fileExists(atPath: transPath.path) {
            pathsToTrash.append(transPath)
        } else if let sumPath = item.summaryPath {
            let fallbackTrans = sumPath.deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("transcriptions")
                .appendingPathComponent("\(item.slug).txt")
            if FileManager.default.fileExists(atPath: fallbackTrans.path) {
                pathsToTrash.append(fallbackTrans)
            }
        }

        for path in pathsToTrash {
            try FileManager.default.trashItem(at: path, resultingItemURL: nil)
        }
    }

    public func clearAllHistory(base: URL) throws {
        let (transDir, sumDir) = try ensureDirectories(base: base)
        if let sumFiles = try? FileManager.default.contentsOfDirectory(at: sumDir, includingPropertiesForKeys: nil) {
            for f in sumFiles where f.pathExtension == "md" {
                try? FileManager.default.trashItem(at: f, resultingItemURL: nil)
            }
        }
        if let transFiles = try? FileManager.default.contentsOfDirectory(at: transDir, includingPropertiesForKeys: nil) {
            for f in transFiles where f.pathExtension == "txt" {
                try? FileManager.default.trashItem(at: f, resultingItemURL: nil)
            }
        }
    }

    public func loadRecentSummaries(directory: URL) -> [SavedSummaryItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [SavedSummaryItem] = []

        for url in files where url.pathExtension == "md" {
            let slug = url.deletingPathExtension().lastPathComponent
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

            var title = slug
            var channel: String? = nil

            if let handle = try? FileHandle(forReadingFrom: url) {
                let headerData = handle.readData(ofLength: 2048)
                try? handle.close()
                if let content = String(data: headerData, encoding: .utf8) {
                    let lines = content.components(separatedBy: .newlines)
                    if let first = lines.first(where: { $0.hasPrefix("# ") }) {
                        title = String(first.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if let meta = lines.first(where: { $0.contains(" · ") && $0.contains("https://") }) {
                        channel = meta.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            let transcriptURL = directory.deletingLastPathComponent()
                .appendingPathComponent("transcriptions")
                .appendingPathComponent("\(slug).txt")
            let hasTranscript = FileManager.default.fileExists(atPath: transcriptURL.path)
            let videoID = Self.videoID(inFileAt: url) ?? (hasTranscript ? Self.videoID(inFileAt: transcriptURL) : nil)

            items.append(SavedSummaryItem(
                slug: slug,
                title: title,
                channel: channel,
                date: modDate,
                summaryPath: url,
                transcriptPath: hasTranscript ? transcriptURL : nil,
                videoID: videoID
            ))
        }

        return items.sorted(by: { $0.date > $1.date })
    }
}
