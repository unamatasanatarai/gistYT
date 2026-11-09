import Foundation

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
            assert(!html.contains("</script><script>"), "Closing script tags must be escaped as <\\/")
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
    }
}
