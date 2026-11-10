import Foundation
import AppKit

public enum AppTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        // AppConfig tests
        testRunner("AppConfig returns valid non-empty application name") {
            assert(!AppConfig.appName.isEmpty, "App name should not be empty")
        }

        testRunner("AppConfig returns valid bundle identifier") {
            assert(!AppConfig.bundleIdentifier.isEmpty, "Bundle identifier should not be empty")
            assert(AppConfig.bundleIdentifier.contains("."), "Bundle identifier should be reverse-DNS style")
        }

        testRunner("AppConfig provides version string") {
            assert(!AppConfig.version.isEmpty, "Version should not be empty")
        }

        testRunner("AppConfig provides build number") {
            assert(!AppConfig.buildNumber.isEmpty, "Build number should not be empty")
        }

        // VideoIDParser tests
        testRunner("VideoIDParser parses bare 11-char ID") {
            let id = "dQw4w9WgXcQ"
            assert(VideoIDParser.parseVideoID(from: id) == id)
        }

        testRunner("VideoIDParser parses watch URL with tracking params") {
            let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=12345&t=42s"
            assert(VideoIDParser.parseVideoID(from: url) == "dQw4w9WgXcQ")
        }

        testRunner("VideoIDParser parses youtu.be short URL") {
            let url = "https://youtu.be/dQw4w9WgXcQ?si=abc"
            assert(VideoIDParser.parseVideoID(from: url) == "dQw4w9WgXcQ")
        }

        testRunner("VideoIDParser parses shorts and embed URLs") {
            assert(VideoIDParser.parseVideoID(from: "https://youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
            assert(VideoIDParser.parseVideoID(from: "https://www.youtube.com/embed/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        }

        testRunner("VideoIDParser rejects invalid inputs") {
            assert(VideoIDParser.parseVideoID(from: "") == nil)
            assert(VideoIDParser.parseVideoID(from: "https://vimeo.com/1234567") == nil)
            assert(VideoIDParser.parseVideoID(from: "not_a_video_id") == nil)
        }

        // SlugGenerator tests
        testRunner("SlugGenerator produces lowercase ASCII slug") {
            let slug = SlugGenerator.makeSlug(title: "What is WebMCP?", videoID: "NERX01dOiEY")
            assert(slug == "what-is-webmcp", "Expected what-is-webmcp, got \(slug)")
        }

        testRunner("SlugGenerator falls back to videoID on empty title") {
            let slug = SlugGenerator.makeSlug(title: "   ", videoID: "dQw4w9WgXcQ")
            assert(slug == "dQw4w9WgXcQ")
        }

        testRunner("SlugGenerator caps slug at 80 chars on word boundary") {
            let longTitle = "This is a very long title designed specifically to exceed eighty characters in length so that we can verify word boundary truncation works properly"
            let slug = SlugGenerator.makeSlug(title: longTitle, videoID: "dQw4w9WgXcQ")
            assert(slug.count <= 80, "Slug exceeded 80 chars: \(slug.count)")
            assert(!slug.hasSuffix("-"), "Slug should not end with hyphen")
        }

        // CaptionFormatter tests
        testRunner("CaptionFormatter groups cues by pause threshold") {
            let cues = [
                CaptionCue(startMs: 0, endMs: 1000, text: "First sentence here."),
                CaptionCue(startMs: 3500, endMs: 4500, text: "Second sentence after pause.")
            ]
            let paragraphs = CaptionFormatter.cuesToParagraphs(cues)
            let parts = paragraphs.components(separatedBy: "\n\n")
            assert(parts.count == 2, "Expected 2 paragraphs due to 2500ms pause, got \(parts.count)")
        }

        // DurationFormatter tests
        testRunner("DurationFormatter formats seconds correctly") {
            assert(DurationFormatter.format(seconds: 45) == "0:45")
            assert(DurationFormatter.format(seconds: 213) == "3:33")
            assert(DurationFormatter.format(seconds: 3665) == "1:01:05")
            assert(DurationFormatter.format(seconds: nil) == nil)
        }

        // MarkdownRenderer tests
        testRunner("MarkdownRenderer produces correct structured markdown") {
            let summary = VideoSummary(
                tldr: "Rick Astley promises full commitment.",
                summary: "This is a detailed summary paragraph explaining the song.",
                keyPoints: ["Point 1", "Point 2"],
                notableQuotes: ["Never gonna give you up"],
                topics: ["Music", "Pop"]
            )
            let md = MarkdownRenderer.renderMarkdown(
                summary: summary,
                title: "Never Gonna Give You Up",
                channel: "Rick Astley",
                duration: "3:33",
                url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                model: "gemini-3.8-flash",
                sourceFilename: "transcriptions/test.txt"
            )
            assert(md.contains("# Never Gonna Give You Up"))
            assert(md.contains("Rick Astley · 3:33 · https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
            assert(md.contains("> **TL;DR** Rick Astley promises full commitment."))
            assert(md.contains("## Notable quotes"))
            assert(md.contains("> \"Never gonna give you up\""))
            assert(md.contains("## Summary"))
            assert(md.contains("## Key points"))
            assert(md.contains("## Topics"))

            // Verify Notable quotes appears before Summary
            let quotesRange = md.range(of: "## Notable quotes")!
            let summaryRange = md.range(of: "## Summary")!
            assert(quotesRange.lowerBound < summaryRange.lowerBound, "Notable quotes should be placed before Summary")

            // Verify bottom attribution and repeated TL;DR are removed
            assert(!md.contains("Generated by"), "Attribution note at bottom should be removed")
            let tldrCount = md.components(separatedBy: "> **TL;DR**").count - 1
            assert(tldrCount == 1, "TL;DR should appear only once at the top, found \(tldrCount) times")
        }

        // StorageService deletion tests
        testRunner("StorageService deleteSummaryItem moves files to Trash") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("gistyt_test_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let sumDir = tempDir.appendingPathComponent("summaries")
            let transDir = tempDir.appendingPathComponent("transcriptions")
            try FileManager.default.createDirectory(at: sumDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: transDir, withIntermediateDirectories: true)

            let testSum = sumDir.appendingPathComponent("test-del.md")
            let testTrans = transDir.appendingPathComponent("test-del.txt")
            try "# Test Brief".write(to: testSum, atomically: true, encoding: .utf8)
            try "Test Transcript Content".write(to: testTrans, atomically: true, encoding: .utf8)

            assert(FileManager.default.fileExists(atPath: testSum.path))
            assert(FileManager.default.fileExists(atPath: testTrans.path))

            let item = SavedSummaryItem(
                slug: "test-del",
                title: "Test Brief",
                channel: "Test Channel",
                date: Date(),
                summaryPath: testSum,
                transcriptPath: testTrans
            )

            final class Box: @unchecked Sendable {
                var error: Error? = nil
            }
            let box = Box()
            let sem = DispatchSemaphore(value: 0)
            Task {
                do {
                    try await StorageService.shared.deleteSummaryItem(item)
                } catch {
                    box.error = error
                }
                sem.signal()
            }
            sem.wait()

            assert(box.error == nil, "Error during delete: \(String(describing: box.error))")
            assert(!FileManager.default.fileExists(atPath: testSum.path), "Summary file should be moved to trash")
            assert(!FileManager.default.fileExists(atPath: testTrans.path), "Transcript file should be moved to trash")

            try? FileManager.default.removeItem(at: tempDir)
        }

        // Hardening & Security regression tests
        testRunner("MarkdownRenderer.renderHTML safely encodes backticks, expressions, and closing scripts") {
            let malicious = "# Title `with backticks` and ${alert(1)}\n</script><script>alert('xss')</script>"
            let html = MarkdownRenderer.renderHTML(markdown: malicious)
            assert(!html.contains("`\(malicious)`"), "Must not use raw template literal interpolation")
            assert(!html.contains("</script><script>"), "Closing script tags must be escaped")
            assert(html.contains("with backticks"), "Content must be preserved")
        }

        testRunner("YouTubeService.stripTagsAndUnescape decodes apostrophe and numeric entities") {
            let input = "<p>don&apos;t you &#x27;know&#x27; &quot;it&#39;s&quot; &#8212; test</p>"
            let cleaned = YouTubeService.stripTagsAndUnescape(input)
            assert(cleaned == "don't you 'know' \"it's\" — test", "Expected properly decoded entities, got: \(cleaned)")
        }

        testRunner("VideoIDParser parses bare ID starting with hyphen") {
            let hyphenID = "-dQw4w9WgXc"
            assert(VideoIDParser.parseVideoID(from: hyphenID) == hyphenID)
        }

        // F3: '$' also matches before a trailing newline, and Foundation percent-decodes
        // query values and path components, so "%0A" used to smuggle "\n" into the ID.
        testRunner("VideoIDParser rejects IDs with a percent-encoded trailing newline") {
            for input in [
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ%0A",
                "https://youtu.be/dQw4w9WgXcQ%0A",
                "https://www.youtube.com/shorts/dQw4w9WgXcQ%0A"
            ] {
                let parsed = VideoIDParser.parseVideoID(from: input)
                assert(parsed == nil, "Expected nil for \(input.debugDescription), got \(parsed.debugDescription)")
            }
        }

        testRunner("VideoIDParser.watchURL never traps on unexpected characters") {
            let url = VideoIDParser.watchURL(for: "dQw4w9WgXcQ\n")
            assert(url.host == "www.youtube.com")
            assert(VideoIDParser.watchURL(for: "dQw4w9WgXcQ").absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        }

        // F7: "<!--<script>" inside the inline script switched the HTML parser into the
        // double-escaped state, so the real </script> never closed it and nothing rendered.
        testRunner("MarkdownRenderer.renderHTML keeps '<' out of the inline script data") {
            let html = MarkdownRenderer.renderHTML(markdown: "# <!--<script> title\n\nbody")
            assert(!html.contains("<!--"), "Raw '<!--' must not reach the script element")
            assert(!html.contains("<script> title"), "Raw '<script' must not reach the script element")
            assert(html.contains("\\u003c!--\\u003cscript> title"), "Content must be preserved as \\u003c escapes")
        }

        // F5: two different videos with the same title must not share files.
        testRunner("StorageService.uniqueSlug disambiguates titles shared by different videos") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("gistyt_slug_\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: base) }
            let trans = base.appendingPathComponent("transcriptions")
            let sums = base.appendingPathComponent("summaries")
            try FileManager.default.createDirectory(at: trans, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sums, withIntermediateDirectories: true)

            let svc = StorageService()
            let slug = runAsync { await svc.uniqueSlug("episode-1", videoID: "AAAAAAAAAAA", transcriptions: trans, summaries: sums) }
            assert(slug == "episode-1", "No existing file: keep slug, got \(slug)")

            try "# Episode 1\n\nChan · 1:00 · https://www.youtube.com/watch?v=AAAAAAAAAAA\n".write(
                to: sums.appendingPathComponent("episode-1.md"), atomically: true, encoding: .utf8)

            let same = runAsync { await svc.uniqueSlug("episode-1", videoID: "AAAAAAAAAAA", transcriptions: trans, summaries: sums) }
            assert(same == "episode-1", "Same video should reuse its slug, got \(same)")

            let other = runAsync { await svc.uniqueSlug("episode-1", videoID: "BBBBBBBBBBB", transcriptions: trans, summaries: sums) }
            assert(other == "episode-1-BBBBBBBBBBB", "Different video must get its own slug, got \(other)")
        }

        // Parallel jobs: two same-titled videos finishing together, before either file exists.
        testRunner("StorageService.uniqueSlug separates concurrent same-title jobs") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("gistyt_slug_\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: base) }
            let trans = base.appendingPathComponent("transcriptions")
            let sums = base.appendingPathComponent("summaries")

            let svc = StorageService()
            let first = runAsync { await svc.uniqueSlug("trailer", videoID: "AAAAAAAAAAA", transcriptions: trans, summaries: sums) }
            let second = runAsync { await svc.uniqueSlug("trailer", videoID: "BBBBBBBBBBB", transcriptions: trans, summaries: sums) }
            let firstAgain = runAsync { await svc.uniqueSlug("trailer", videoID: "AAAAAAAAAAA", transcriptions: trans, summaries: sums) }
            assert(first == "trailer", "got \(first)")
            assert(second == "trailer-BBBBBBBBBBB", "Second video must not share the unwritten slug, got \(second)")
            assert(firstAgain == "trailer", "Same video keeps its claim, got \(firstAgain)")
        }

        testRunner("StorageService.videoID extracts video ID from markdown headers") {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).md")
            defer { try? FileManager.default.removeItem(at: tmp) }
            let content = "# Title\n\nChannel · 10:00 · https://www.youtube.com/watch?v=dQw4w9WgXcQ\n\n> **TL;DR** Great video\n"
            try content.write(to: tmp, atomically: true, encoding: .utf8)

            let extracted = StorageService.videoID(inFileAt: tmp)
            assert(extracted == "dQw4w9WgXcQ", "Expected dQw4w9WgXcQ, got \(extracted.debugDescription)")
        }

        testRunner("AppDelegate implements double Cmd+Q to quit") {
            let delegate = AppDelegate()
            var noticePosted = false
            let observer = NotificationCenter.default.addObserver(forName: .confirmQuitRequested, object: nil, queue: nil) { _ in
                noticePosted = true
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            let firstAttempt = delegate.applicationShouldTerminate(NSApp)
            assert(firstAttempt == .terminateCancel, "First quit attempt should cancel and prompt")
            assert(noticePosted, "First quit attempt should post confirmQuitRequested notification")

            let secondAttempt = delegate.applicationShouldTerminate(NSApp)
            assert(secondAttempt == .terminateNow, "Second quit attempt within 2s should terminate")
        }

        // F4: the actionable yt-dlp error must survive a failing HTTP fallback.
        testRunner("YouTubeService surfaces yt-dlp bot-check error when the fallback also fails") {
            let stub = try makeStubYtDlp("""
            echo "ERROR: [youtube] dQw4w9WgXcQ: Sign in to confirm you're not a bot" >&2
            exit 1
            """)
            defer { try? FileManager.default.removeItem(at: stub.deletingLastPathComponent()) }
            FailingURLProtocol.reset()
            let svc = YouTubeService(session: FailingURLProtocol.session(), ytDlpURL: stub)
            let error = runAsyncError { _ = try await svc.fetchTranscript(videoID: "dQw4w9WgXcQ") }
            guard case .videoUnavailable(let msg)? = error as? YouTubeError else {
                preconditionFailure("Expected videoUnavailable, got \(String(describing: error))")
            }
            assert(msg.contains("not a bot"), "Bot hint lost: \(msg)")
        }

        testRunner("YouTubeService does not run the HTTP fallback when yt-dlp finds no captions") {
            let stub = try makeStubYtDlp("""
            echo '{"title":"T","subtitles":{},"automatic_captions":{}}'
            """)
            defer { try? FileManager.default.removeItem(at: stub.deletingLastPathComponent()) }
            FailingURLProtocol.reset()
            let svc = YouTubeService(session: FailingURLProtocol.session(), ytDlpURL: stub)
            let error = runAsyncError { _ = try await svc.fetchTranscript(videoID: "dQw4w9WgXcQ") }
            guard case .noCaptions? = error as? YouTubeError else {
                preconditionFailure("Expected noCaptions, got \(String(describing: error))")
            }
            assert(FailingURLProtocol.requestCount == 0, "Fallback made \(FailingURLProtocol.requestCount) requests")
        }

        // F2: a hung yt-dlp must be killable by cancellation and bounded by a timeout.
        testRunner("YouTubeService cancellation terminates a hung yt-dlp promptly") {
            let stub = try makeStubYtDlp("exec /bin/sleep 30")
            defer { try? FileManager.default.removeItem(at: stub.deletingLastPathComponent()) }
            FailingURLProtocol.reset()
            let svc = YouTubeService(session: FailingURLProtocol.session(), ytDlpURL: stub)
            let start = Date()
            let task = Task { try await svc.fetchTranscript(videoID: "dQw4w9WgXcQ") }
            Thread.sleep(forTimeInterval: 0.5)
            task.cancel()
            let error = runAsyncError { _ = try await task.value }
            let elapsed = Date().timeIntervalSince(start)
            assert(error is CancellationError, "Expected CancellationError, got \(String(describing: error))")
            assert(elapsed < 5, "Cancellation took \(elapsed)s")
            assert(FailingURLProtocol.requestCount == 0, "Cancelled fetch must not fall back to HTTP")
        }

        testRunner("YouTubeService times out a hung yt-dlp") {
            let stub = try makeStubYtDlp("exec /bin/sleep 30")
            defer { try? FileManager.default.removeItem(at: stub.deletingLastPathComponent()) }
            FailingURLProtocol.reset()
            let svc = YouTubeService(session: FailingURLProtocol.session(), ytDlpURL: stub, ytDlpTimeout: 1)
            let start = Date()
            _ = runAsyncError { _ = try await svc.fetchTranscript(videoID: "dQw4w9WgXcQ") }
            let elapsed = Date().timeIntervalSince(start)
            assert(elapsed < 5, "Timeout did not fire: \(elapsed)s")
            assert(FailingURLProtocol.requestCount > 0, "A timed-out yt-dlp should still fall back to HTTP")
        }

        testRunner("GeminiService stops rotating models when cancelled") {
            FailingURLProtocol.reset()
            let svc = GeminiService(session: FailingURLProtocol.session(delay: 2))
            let task = Task {
                try await svc.summarize(transcriptText: "x", apiKey: "k", models: ["m1", "m2", "m3", "m4"])
            }
            Thread.sleep(forTimeInterval: 0.3)
            task.cancel()
            let error = runAsyncError { _ = try await task.value }
            assert(error is CancellationError, "Expected CancellationError, got \(String(describing: error))")
            assert(FailingURLProtocol.requestCount <= 1, "Rotation continued after cancel: \(FailingURLProtocol.requestCount) requests")
        }
    }
}

// MARK: - Test helpers

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

/// Runs async work from the synchronous test runner (which is on the main thread).
func runAsync<T>(_ body: @escaping @Sendable () async -> T) -> T {
    let box = ResultBox<T>()
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        box.value = await body()
        sem.signal()
    }
    sem.wait()
    return box.value!
}

/// Runs throwing async work and returns the error it threw (nil on success).
func runAsyncError(_ body: @escaping @Sendable () async throws -> Void) -> Error? {
    runAsync {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }
}

/// Writes an executable /bin/sh script standing in for yt-dlp; returns its URL.
func makeStubYtDlp(_ script: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gistyt_stub_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("yt-dlp")
    try "#!/bin/sh\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

/// URLProtocol that fails every request (optionally after a delay) and counts them,
/// so tests never touch the network.
final class FailingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _count = 0
    private static var delay: TimeInterval = 0

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }

    static func reset() {
        lock.lock(); _count = 0; lock.unlock()
    }

    static func session(delay: TimeInterval = 0) -> URLSession {
        self.delay = delay
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var cancelled = false

    override func startLoading() {
        Self.lock.lock(); Self._count += 1; Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [weak self] in
            guard let self = self, !self.cancelled else { return }
            self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }

    override func stopLoading() {
        cancelled = true
    }
}
