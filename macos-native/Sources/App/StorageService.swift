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

            items.append(SavedSummaryItem(
                slug: slug,
                title: title,
                channel: channel,
                date: modDate,
                summaryPath: url,
                transcriptPath: hasTranscript ? transcriptURL : nil
            ))
        }

        return items.sorted(by: { $0.date > $1.date })
    }
}
