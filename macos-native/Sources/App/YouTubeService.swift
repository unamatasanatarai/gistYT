import Foundation

public enum YouTubeError: LocalizedError, Sendable {
    case invalidVideoID(String)
    case fetchFailed(String)
    case noCaptions
    case videoUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVideoID(let id):
            return "Not a valid YouTube video URL or ID: '\(id)'"
        case .fetchFailed(let msg):
            return "Failed to fetch YouTube data: \(msg)"
        case .noCaptions:
            return "This video has no captions (manual or auto-generated), so there is no transcript to summarize."
        case .videoUnavailable(let msg):
            return "Video is unavailable or private: \(msg)"
        }
    }
}

public actor YouTubeService {
    public static let shared = YouTubeService()

    private let session: URLSession
    private let ytDlpOverride: URL?
    private let ytDlpTimeout: TimeInterval

    /// - Parameters:
    ///   - ytDlpURL: explicit yt-dlp executable (tests); nil searches the bundle and PATH.
    ///   - ytDlpTimeout: wall-clock limit for each yt-dlp run before it is terminated.
    public init(session: URLSession = .shared, ytDlpURL: URL? = nil, ytDlpTimeout: TimeInterval = 120) {
        self.session = session
        self.ytDlpOverride = ytDlpURL
        self.ytDlpTimeout = ytDlpTimeout
    }

    public func fetchTranscript(
        videoID: String,
        preferredLangs: [String]? = nil,
        browserCookies: String? = nil
    ) async throws -> TranscriptResult {
        // Method 1: Try bundled yt-dlp first (handles bot confirmation, SABR, visionos/android rotation)
        var ytDlpError: Error?
        if let ytDlpURL = ytDlpExecutableURL {
            do {
                return try await fetchWithYtDlp(
                    executableURL: ytDlpURL,
                    videoID: videoID,
                    preferredLangs: preferredLangs,
                    browserCookies: browserCookies
                )
            } catch YouTubeError.noCaptions {
                // yt-dlp saw the full track list and none matched; the fallback would agree.
                throw YouTubeError.noCaptions
            } catch {
                if isCancellationError(error) { throw CancellationError() }
                NSLog("Bundled yt-dlp failed (\(error.localizedDescription)); attempting direct HTTP fallback...")
                ytDlpError = error
            }
        }

        // Method 2: Fallback to direct HTTP Innertube API
        do {
            return try await fetchDirectHTTP(videoID: videoID, preferredLangs: preferredLangs)
        } catch {
            if isCancellationError(error) { throw CancellationError() }
            // yt-dlp's "unavailable" errors carry the actionable reason (e.g. the bot check
            // and the cookie hint); the fallback's error would only hide it.
            if let ytErr = ytDlpError as? YouTubeError, case .videoUnavailable = ytErr {
                throw ytErr
            }
            throw error
        }
    }

    // MARK: - Bundled yt-dlp Implementation

    private var ytDlpExecutableURL: URL? {
        if let override = ytDlpOverride {
            return override
        }
        if let bundleURL = Bundle.main.url(forResource: "yt-dlp", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundleURL.path) {
            return bundleURL
        }
        let appResources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/yt-dlp")
        if FileManager.default.isExecutableFile(atPath: appResources.path) {
            return appResources
        }
        let devResource = URL(fileURLWithPath: "macos-native/Resources/yt-dlp")
        if FileManager.default.isExecutableFile(atPath: devResource.path) {
            return devResource
        }
        for path in ["/usr/local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func fetchWithYtDlp(
        executableURL: URL,
        videoID: String,
        preferredLangs: [String]?,
        browserCookies: String?
    ) async throws -> TranscriptResult {
        let watchURL = VideoIDParser.watchURL(for: videoID).absoluteString

        // Step 1: Run yt-dlp --dump-json to extract video metadata & all caption formats
        let tmpOut = FileManager.default.temporaryDirectory.appendingPathComponent("ytdlp_out_\(UUID().uuidString).json")
        let tmpErr = FileManager.default.temporaryDirectory.appendingPathComponent("ytdlp_err_\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: tmpOut.path, contents: nil)
        FileManager.default.createFile(atPath: tmpErr.path, contents: nil)

        defer {
            try? FileManager.default.removeItem(at: tmpOut)
            try? FileManager.default.removeItem(at: tmpErr)
        }

        guard let outHandle = FileHandle(forWritingAtPath: tmpOut.path),
              let errHandle = FileHandle(forWritingAtPath: tmpErr.path) else {
            throw YouTubeError.fetchFailed("Could not create temporary file handles for yt-dlp")
        }

        var args = [
            "--dump-json",
            "--skip-download",
            "--no-playlist",
            "--no-warnings",
            "--socket-timeout", "20"
        ]

        if let cookies = browserCookies, !cookies.isEmpty, cookies.lowercased() != "none" {
            args.append(contentsOf: ["--cookies-from-browser", cookies.lowercased()])
        }

        args.append(watchURL)

        defer {
            outHandle.closeFile()
            errHandle.closeFile()
        }
        try await runYtDlp(executableURL: executableURL, arguments: args, stdout: outHandle, stderr: errHandle)

        let outData = (try? Data(contentsOf: tmpOut)) ?? Data()
        let errStr = (try? String(contentsOf: tmpErr, encoding: .utf8)) ?? ""

        guard let json = (try? JSONSerialization.jsonObject(with: outData)) as? [String: Any] else {
            let cleanErr = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanErr.contains("Sign in to confirm you're not a bot") {
                throw YouTubeError.videoUnavailable("Sign in to confirm you're not a bot (Select your browser in Settings to use your cookies)")
            }
            throw YouTubeError.fetchFailed(cleanErr.isEmpty ? "yt-dlp produced no output" : cleanErr)
        }

        let title = json["title"] as? String
        let channel = (json["channel"] as? String) ?? (json["uploader"] as? String)
        let duration = json["duration"] as? Int

        let manualDict = (json["subtitles"] as? [String: [[String: Any]]]) ?? [:]
        let autoDict = (json["automatic_captions"] as? [String: [[String: Any]]]) ?? [:]

        // Step 2: Choose caption track
        guard let (trackLang, isManual, json3URL) = pickYtDlpTrack(
            manual: manualDict,
            auto: autoDict,
            preferredLangs: preferredLangs
        ) else {
            throw YouTubeError.noCaptions
        }

        let captionLabel = "\(trackLang) (\(isManual ? "manual" : "auto"), via bundled yt-dlp)"

        // Step 3: Fetch json3 cues (try direct URL, fallback to yt-dlp --write-sub)
        var cues: [CaptionCue] = []
        if let directURL = URL(string: json3URL) {
            var req = URLRequest(url: directURL)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            if let (cdata, _) = try? await session.data(for: req),
               let cjson = (try? JSONSerialization.jsonObject(with: cdata)) as? [String: Any] {
                cues = parseJson3Events(cjson)
            }
        }
        // `try?` above also swallows cancellation; don't start another yt-dlp run if so.
        try Task.checkCancellation()

        // If direct URL failed or empty, run yt-dlp --write-sub to write the file directly
        if cues.isEmpty {
            cues = try await downloadJson3ViaYtDlp(
                executableURL: executableURL,
                watchURL: watchURL,
                trackLang: trackLang,
                browserCookies: browserCookies
            )
        }

        if cues.isEmpty {
            // A track exists but its download failed: a fetch problem, not a missing transcript,
            // so let fetchTranscript try the HTTP fallback.
            throw YouTubeError.fetchFailed("Could not download the \(trackLang) caption track")
        }

        let text = CaptionFormatter.cuesToParagraphs(cues)
        return TranscriptResult(
            videoID: videoID,
            title: title,
            channel: channel,
            duration: duration,
            captions: captionLabel,
            text: text
        )
    }

    private func pickYtDlpTrack(
        manual: [String: [[String: Any]]],
        auto: [String: [[String: Any]]],
        preferredLangs: [String]?
    ) -> (lang: String, isManual: Bool, json3URL: String)? {
        func getJson3(_ list: [[String: Any]]?) -> String? {
            guard let list = list else { return nil }
            return list.first(where: { ($0["ext"] as? String) == "json3" })?["url"] as? String
        }

        // Custom preferred languages
        if let prefs = preferredLangs, !prefs.isEmpty {
            for pref in prefs {
                let code = pref.lowercased()
                if let key = manual.keys.first(where: { $0.lowercased() == code || $0.lowercased().starts(with: code + "-") }),
                   let url = getJson3(manual[key]) {
                    return (key, true, url)
                }
                if let key = auto.keys.first(where: { $0.lowercased() == code || $0.lowercased().starts(with: code + "-") }),
                   let url = getJson3(auto[key]) {
                    return (key, false, url)
                }
            }
            return nil
        }

        // Default Priority:
        // 1. Manual English
        if let key = manual.keys.first(where: { $0.lowercased() == "en" || $0.lowercased().starts(with: "en-") }),
           let url = getJson3(manual[key]) {
            return (key, true, url)
        }
        // 2. Auto English
        if let key = auto.keys.first(where: { $0.lowercased() == "en" || $0.lowercased().starts(with: "en-") }),
           let url = getJson3(auto[key]) {
            return (key, false, url)
        }
        // 3. Other manual track
        if let key = manual.keys.sorted().first, let url = getJson3(manual[key]) {
            return (key, true, url)
        }
        // 4. Any auto track
        if let key = auto.keys.sorted().first, let url = getJson3(auto[key]) {
            return (key, false, url)
        }

        return nil
    }

    private func downloadJson3ViaYtDlp(
        executableURL: URL,
        watchURL: String,
        trackLang: String,
        browserCookies: String?
    ) async throws -> [CaptionCue] {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("sub_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let outPattern = tmpDir.appendingPathComponent("caption").path

        var args = [
            "--skip-download",
            "--write-sub",
            "--write-auto-sub",
            "--sub-lang", trackLang,
            "--sub-format", "json3",
            "--no-playlist",
            "--no-warnings",
            "--socket-timeout", "20",
            "-o", outPattern
        ]

        if let cookies = browserCookies, !cookies.isEmpty, cookies.lowercased() != "none" {
            args.append(contentsOf: ["--cookies-from-browser", cookies.lowercased()])
        }

        args.append(watchURL)

        try await runYtDlp(
            executableURL: executableURL,
            arguments: args,
            stdout: FileHandle.nullDevice,
            stderr: FileHandle.nullDevice
        )

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path) else {
            return []
        }

        for file in files where file.hasSuffix(".json3") {
            let filePath = tmpDir.appendingPathComponent(file)
            if let data = try? Data(contentsOf: filePath),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                return parseJson3Events(json)
            }
        }

        return []
    }

    /// Runs yt-dlp to completion. Task cancellation terminates the process, and so does
    /// `ytDlpTimeout`; without both, a hung run (e.g. an unanswered Keychain prompt from
    /// --cookies-from-browser) would block the app until restart.
    private func runYtDlp(
        executableURL: URL,
        arguments: [String],
        stdout: FileHandle,
        stderr: FileHandle
    ) async throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        let controller = ProcessController(process)
        let timeout = ytDlpTimeout

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try controller.launch()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    controller.timeOut()
                }
            }
        } onCancel: {
            controller.cancel()
        }

        if controller.wasCancelled || Task.isCancelled {
            throw CancellationError()
        }
        if controller.didTimeOut {
            throw YouTubeError.fetchFailed("yt-dlp did not finish within \(Int(timeout)) seconds")
        }
    }

    private func parseJson3Events(_ data: [String: Any]) -> [CaptionCue] {
        guard let events = data["events"] as? [[String: Any]] else { return [] }
        var cues: [CaptionCue] = []
        for event in events {
            guard let segs = event["segs"] as? [[String: Any]] else { continue }
            let text = segs.compactMap { $0["utf8"] as? String }.joined()
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

            let startMs = (event["tStartMs"] as? Int) ?? 0
            let durMs = (event["dDurationMs"] as? Int) ?? 0
            cues.append(CaptionCue(startMs: startMs, endMs: startMs + durMs, text: text))
        }
        return cues
    }

    // MARK: - Direct HTTP Fallback Implementation

    private func fetchDirectHTTP(videoID: String, preferredLangs: [String]?) async throws -> TranscriptResult {
        let watchURL = VideoIDParser.watchURL(for: videoID)
        var watchReq = URLRequest(url: watchURL)
        watchReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        watchReq.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (watchData, _) = try await session.data(for: watchReq)
        guard let html = String(data: watchData, encoding: .utf8) else {
            throw YouTubeError.fetchFailed("Unable to read watch page response")
        }

        let apiKey = extractInnertubeKey(from: html) ?? "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"

        let innertubeURL = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(apiKey)")!
        var innertubeReq = URLRequest(url: innertubeURL)
        innertubeReq.httpMethod = "POST"
        innertubeReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        innertubeReq.setValue("com.google.android.youtube/20.10.38 (Linux; U; Android 14; US)", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "videoId": videoID,
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": "20.10.38"
                ]
            ]
        ]
        innertubeReq.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (apiData, _) = try await session.data(for: innertubeReq)
        guard let json = try? JSONSerialization.jsonObject(with: apiData) as? [String: Any] else {
            throw YouTubeError.fetchFailed("Could not parse YouTube API response")
        }

        if let playability = json["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String, status != "OK" {
            let reason = playability["reason"] as? String ?? status
            throw YouTubeError.videoUnavailable(reason)
        }

        let videoDetails = json["videoDetails"] as? [String: Any]
        let title = videoDetails?["title"] as? String
        let channel = videoDetails?["author"] as? String
        let lengthSecondsStr = videoDetails?["lengthSeconds"] as? String
        let duration = lengthSecondsStr.flatMap { Int($0) }

        guard let captionsObj = json["captions"] as? [String: Any],
              let tracklist = captionsObj["playerCaptionsTracklistRenderer"] as? [String: Any],
              let rawTracks = tracklist["captionTracks"] as? [[String: Any]], !rawTracks.isEmpty else {
            throw YouTubeError.noCaptions
        }

        var tracks: [CaptionTrackInfo] = []
        for raw in rawTracks {
            guard let lang = raw["languageCode"] as? String,
                  let baseUrl = raw["baseUrl"] as? String else { continue }
            let vssId = raw["vssId"] as? String
            let kind = (raw["kind"] as? String) == "asr" ? "auto" : "manual"
            let name = (raw["name"] as? [String: Any])?["simpleText"] as? String
            tracks.append(CaptionTrackInfo(languageCode: lang, vssId: vssId, name: name, kind: kind, baseUrl: baseUrl))
        }

        guard let chosenTrack = chooseTrack(from: tracks, preferredLangs: preferredLangs) else {
            throw YouTubeError.noCaptions
        }

        guard let trackURL = URL(string: chosenTrack.baseUrl) else {
            throw YouTubeError.fetchFailed("YouTube returned an invalid caption track URL")
        }
        var timedtextReq = URLRequest(url: trackURL)
        timedtextReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (timedtextData, _) = try await session.data(for: timedtextReq)
        guard let xmlString = String(data: timedtextData, encoding: .utf8), !xmlString.isEmpty else {
            throw YouTubeError.fetchFailed("Empty timedtext response")
        }

        let cues = parseTimedtextXML(xmlString)
        if cues.isEmpty {
            throw YouTubeError.noCaptions
        }

        let formattedText = CaptionFormatter.cuesToParagraphs(cues)
        return TranscriptResult(
            videoID: videoID,
            title: title,
            channel: channel,
            duration: duration,
            captions: chosenTrack.label,
            text: formattedText
        )
    }

    private func extractInnertubeKey(from html: String) -> String? {
        let pattern = #""INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: html.utf16.count)
        if let match = regex.firstMatch(in: html, options: [], range: range),
           match.numberOfRanges > 1,
           let keyRange = Range(match.range(at: 1), in: html) {
            return String(html[keyRange])
        }
        return nil
    }

    private func chooseTrack(from tracks: [CaptionTrackInfo], preferredLangs: [String]?) -> CaptionTrackInfo? {
        if let preferred = preferredLangs, !preferred.isEmpty {
            for pref in preferred {
                let code = pref.lowercased()
                if let manual = tracks.first(where: { $0.kind == "manual" && ($0.languageCode.lowercased() == code || $0.languageCode.lowercased().starts(with: code + "-")) }) {
                    return manual
                }
                if let auto = tracks.first(where: { $0.kind == "auto" && ($0.languageCode.lowercased() == code || $0.languageCode.lowercased().starts(with: code + "-")) }) {
                    return auto
                }
            }
            return nil
        }

        if let manualEn = tracks.first(where: { $0.kind == "manual" && ($0.languageCode.lowercased() == "en" || $0.languageCode.lowercased().starts(with: "en-")) }) {
            return manualEn
        }
        if let autoEn = tracks.first(where: { $0.kind == "auto" && ($0.languageCode.lowercased() == "en" || $0.languageCode.lowercased().starts(with: "en-")) }) {
            return autoEn
        }
        if let otherManual = tracks.first(where: { $0.kind == "manual" }) {
            return otherManual
        }
        return tracks.first
    }

    private func parseTimedtextXML(_ xml: String) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        let pRegex = try! NSRegularExpression(pattern: #"<p[^>]*t="(\d+)"[^>]*d="(\d+)"[^>]*>(.*?)</p>"#, options: [.dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: xml.utf16.count)
        let matches = pRegex.matches(in: xml, options: [], range: range)

        if !matches.isEmpty {
            for m in matches {
                guard m.numberOfRanges >= 4,
                      let tRange = Range(m.range(at: 1), in: xml),
                      let dRange = Range(m.range(at: 2), in: xml),
                      let textRange = Range(m.range(at: 3), in: xml) else { continue }
                let startMs = Int(xml[tRange]) ?? 0
                let durMs = Int(xml[dRange]) ?? 0
                let rawText = String(xml[textRange])
                let cleanText = Self.stripTagsAndUnescape(rawText)
                if !cleanText.isEmpty {
                    cues.append(CaptionCue(startMs: startMs, endMs: startMs + durMs, text: cleanText))
                }
            }
            return cues
        }

        let textRegex = try! NSRegularExpression(pattern: #"<text[^>]*start="([\d.]+)"[^>]*dur="([\d.]+)"[^>]*>(.*?)</text>"#, options: [.dotMatchesLineSeparators])
        let textMatches = textRegex.matches(in: xml, options: [], range: range)
        for m in textMatches {
            guard m.numberOfRanges >= 4,
                  let sRange = Range(m.range(at: 1), in: xml),
                  let dRange = Range(m.range(at: 2), in: xml),
                  let textRange = Range(m.range(at: 3), in: xml) else { continue }
            let startSec = Double(xml[sRange]) ?? 0.0
            let durSec = Double(xml[dRange]) ?? 0.0
            let startMs = Int(startSec * 1000)
            let durMs = Int(durSec * 1000)
            let rawText = String(xml[textRange])
            let cleanText = Self.stripTagsAndUnescape(rawText)
            if !cleanText.isEmpty {
                cues.append(CaptionCue(startMs: startMs, endMs: startMs + durMs, text: cleanText))
            }
        }

        return cues
    }

    public static func stripTagsAndUnescape(_ string: String) -> String {
        var cleaned = string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&apos;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&#34;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&#38;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&#60;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&#62;", with: ">")

        if cleaned.contains("&#") {
            let regex = try? NSRegularExpression(pattern: #"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#)
            let nsStr = cleaned as NSString
            let matches = regex?.matches(in: cleaned, range: NSRange(location: 0, length: nsStr.length)) ?? []
            for match in matches.reversed() {
                var codePoint: UInt32? = nil
                if match.range(at: 1).location != NSNotFound {
                    let hexStr = nsStr.substring(with: match.range(at: 1))
                    codePoint = UInt32(hexStr, radix: 16)
                } else if match.range(at: 2).location != NSNotFound {
                    let decStr = nsStr.substring(with: match.range(at: 2))
                    codePoint = UInt32(decStr, radix: 10)
                }
                if let cp = codePoint, let scalar = UnicodeScalar(cp) {
                    let replacement = String(Character(scalar))
                    cleaned = (cleaned as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Serializes launch, cancellation and timeout for one yt-dlp process, so a cancel that
/// arrives before launch still prevents the run, and terminate() is only called on a
/// launched process (calling it before launch raises an Objective-C exception).
private final class ProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var launched = false
    private var cancelled = false
    private var timedOut = false

    init(_ process: Process) {
        self.process = process
    }

    func launch() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try process.run()
        launched = true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if launched && process.isRunning { process.terminate() }
    }

    func timeOut() {
        lock.lock()
        defer { lock.unlock() }
        if launched && process.isRunning {
            timedOut = true
            process.terminate()
        }
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
}
