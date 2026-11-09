import Foundation

public enum GeminiError: LocalizedError, Sendable {
    case missingAPIKey
    case fatalAuthError(String)
    case badRequest(String)
    case allModelsFailed([String])

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key is not set. Please set it in Settings or export GEMINI_API_KEY."
        case .fatalAuthError(let msg):
            return "Authentication failed (401/403): \(msg)"
        case .badRequest(let msg):
            return "Bad request (400): \(msg)"
        case .allModelsFailed(let attempts):
            return "All models in rotation failed:\n" + attempts.map { "  • \($0)" }.joined(separator: "\n")
        }
    }
}

public actor GeminiService {
    public static let shared = GeminiService()

    public static let defaultModels: [String] = [
        "gemini-3.8-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite"
    ]

    public static let systemInstruction = """
    You summarize YouTube video transcripts. The input starts with metadata header lines (Title, Channel, URL, Duration, Captions) followed by the transcript, which may be auto-generated, unpunctuated, or in any language.

    Always write your answer in English, whatever language the transcript is in.
    Return JSON with these fields:
    - tldr: one sentence capturing the main point of the video.
    - summary: 2-4 paragraphs (separate paragraphs with a blank line) explaining what the video covers.
    - key_points: 5-10 concise, self-contained key points or takeaways, in the order they appear.
    - notable_quotes: short verbatim quotes worth remembering (translated to English if needed); empty list if none stand out.
    - topics: 3-8 short topic tags (one to three words each).
    Base everything only on the transcript; do not invent facts. Ignore caption artifacts such as [Music] or repeated filler words.
    """

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func summarize(
        transcriptText: String,
        apiKey: String,
        models: [String] = defaultModels,
        onStatusChange: (@Sendable (String) -> Void)? = nil
    ) async throws -> (summary: VideoSummary, model: String) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanKey.isEmpty {
            throw GeminiError.missingAPIKey
        }

        var attempts: [String] = []

        for (index, model) in models.enumerated() {
            onStatusChange?("Summarizing with \(model)...")

            do {
                let summary = try await executeModelRequest(
                    model: model,
                    transcriptText: transcriptText,
                    apiKey: cleanKey
                )
                return (summary, model)
            } catch let error as GeminiError {
                // Fatal non-rotatable errors
                throw error
            } catch {
                let reason = error.localizedDescription
                attempts.append("\(model): \(reason)")
                if index + 1 < models.count {
                    onStatusChange?("\(model) unavailable (\(reason)), trying \(models[index + 1])...")
                }
            }
        }

        throw GeminiError.allModelsFailed(attempts)
    }

    private func executeModelRequest(
        model: String,
        transcriptText: String,
        apiKey: String
    ) async throws -> VideoSummary {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.badRequest("Invalid Gemini URL for model \(model)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": transcriptText]
                    ]
                ]
            ],
            "systemInstruction": [
                "parts": [
                    ["text": Self.systemInstruction]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "tldr": ["type": "STRING", "description": "One sentence capturing the main point."],
                        "summary": ["type": "STRING", "description": "2-4 paragraphs."],
                        "key_points": [
                            "type": "ARRAY",
                            "items": ["type": "STRING"],
                            "description": "5-10 items."
                        ],
                        "notable_quotes": [
                            "type": "ARRAY",
                            "items": ["type": "STRING"],
                            "description": "May be empty."
                        ],
                        "topics": [
                            "type": "ARRAY",
                            "items": ["type": "STRING"],
                            "description": "Short tags."
                        ]
                    ],
                    "required": ["tldr", "summary", "key_points", "notable_quotes", "topics"]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unauthorized"
            throw GeminiError.fatalAuthError(errorBody)
        }

        if http.statusCode == 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Bad Request"
            throw GeminiError.badRequest(errorBody)
        }

        guard (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "GeminiService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(errorBody)"])
        }

        // Parse Gemini Response JSON
        guard let responseJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = responseJson["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "GeminiService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini API response structure"])
        }

        guard let textData = text.data(using: .utf8) else {
            throw NSError(domain: "GeminiService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not decode text data"])
        }

        let decoder = JSONDecoder()
        return try decoder.decode(VideoSummary.self, from: textData)
    }
}
