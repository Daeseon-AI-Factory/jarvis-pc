//
//  GeminiDispatcher.swift
//  ScreenBridge — Phase 2.3
//
//  Google Gemini 2.5 Flash dispatcher. URLSession async/await + responseSchema 강제
//  + 429/5xx exp backoff retry. SYSTEM_PROMPT는 systemInstruction, AI 지시 + 이미지는
//  user content (image FIRST + text AFTER — Gemini quirk, sweep cross_cutting).
//

import CoreGraphics
import Foundation

actor GeminiDispatcher: LLMDispatcher {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String = "gemini-2.5-flash") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// `GEMINI_API_KEY` 환경(`Env`) 로드. 없으면 nil — caller가 missingAPIKey 처리.
    static func fromEnvironment() -> GeminiDispatcher? {
        guard let key = Env.string("GEMINI_API_KEY"), !key.isEmpty else { return nil }
        return GeminiDispatcher(apiKey: key)
    }

    func analyze(
        imageData: Data,
        imageSize: CGSize,
        instruction: String
    ) async throws -> AnalysisResult {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw DispatcherError.invalidResponse("invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = Self.buildRequestBody(
            imageData: imageData, imageSize: imageSize, instruction: instruction
        )
        request.httpBody = try JSONEncoder().encode(body)

        let w = Int(imageSize.width.rounded())
        let h = Int(imageSize.height.rounded())
        Log.dispatcher.info(
            "[gemini] begin — instruction \(instruction.count, privacy: .public) chars, image \(imageData.count, privacy: .public) bytes (\(w, privacy: .public)x\(h, privacy: .public))"
        )
        let started = Date()

        let (data, _) = try await sendWithRetry(request)
        let elapsed = Date().timeIntervalSince(started)

        let geminiResp: GeminiResponse
        do {
            geminiResp = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8)?.prefix(300) ?? "<non-utf8>"
            Log.dispatcher.error(
                "[gemini] envelope decode fail: \(error.localizedDescription, privacy: .public); raw=\(preview, privacy: .public)"
            )
            throw DispatcherError.decoding(error.localizedDescription)
        }

        guard let candidate = geminiResp.candidates.first,
              let content = candidate.content,
              let part = content.parts.first,
              let text = part.text else {
            Log.dispatcher.error("[gemini] no candidates/parts/text")
            throw DispatcherError.invalidResponse("no candidates/parts/text")
        }

        if candidate.finishReason == "MAX_TOKENS" {
            Log.dispatcher.error("[gemini] finishReason=MAX_TOKENS — response truncated, fail loud")
            throw DispatcherError.maxTokens
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw DispatcherError.decoding("model text not utf8")
        }
        let result: AnalysisResult
        do {
            result = try JSONDecoder().decode(AnalysisResult.self, from: jsonData)
        } catch {
            Log.dispatcher.error(
                "[gemini] model JSON decode fail: \(error.localizedDescription, privacy: .public); raw=\(text.prefix(300), privacy: .public)"
            )
            throw DispatcherError.decoding(error.localizedDescription)
        }

        Log.dispatcher.info(
            "[gemini] ok \(String(format: "%.1f", elapsed), privacy: .public)s — target_text=\"\(result.targetText, privacy: .public)\""
        )
        return result.withRaw(text)
    }

    /// Exp backoff retry: 429/500/502/503/504 only. 1/2/4s + jitter. max 3 attempts.
    /// 400/401/403 등은 fail fast (재시도 무의미).
    private func sendWithRetry(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let retryableStatuses: Set<Int> = [429, 500, 502, 503, 504]
        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            let data: Data
            let urlResponse: URLResponse
            do {
                (data, urlResponse) = try await session.data(for: request)
            } catch let urlError as URLError {
                Log.dispatcher.error("[gemini] network error: \(urlError.localizedDescription, privacy: .public)")
                throw DispatcherError.network(urlError)
            }
            guard let httpResp = urlResponse as? HTTPURLResponse else {
                throw DispatcherError.invalidResponse("non-http response")
            }
            if 200..<300 ~= httpResp.statusCode {
                return (data, httpResp)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            if !retryableStatuses.contains(httpResp.statusCode) {
                Log.dispatcher.error(
                    "[gemini] http \(httpResp.statusCode, privacy: .public) non-retryable: \(body.prefix(300), privacy: .public)"
                )
                throw DispatcherError.httpStatus(httpResp.statusCode, body: String(body.prefix(500)))
            }
            if attempt == maxAttempts {
                Log.dispatcher.error(
                    "[gemini] retries exhausted last=\(httpResp.statusCode, privacy: .public)"
                )
                throw DispatcherError.retriesExhausted(lastStatus: httpResp.statusCode)
            }
            let backoffSec = pow(2.0, Double(attempt - 1)) + Double.random(in: 0...0.3)
            Log.dispatcher.notice(
                "[gemini] retry \(attempt, privacy: .public)/\(maxAttempts, privacy: .public) in \(String(format: "%.1f", backoffSec), privacy: .public)s (status=\(httpResp.statusCode, privacy: .public))"
            )
            try await Task.sleep(nanoseconds: UInt64(backoffSec * 1_000_000_000))
        }
        throw DispatcherError.retriesExhausted(lastStatus: 0)
    }

    // MARK: - Request body construction

    /// Gemini quirk: image part FIRST, text AFTER (sweep cross_cutting Layer 12 변형).
    /// systemInstruction은 SYSTEM_PROMPT, role 없음. user content는 image + text.
    static func buildRequestBody(
        imageData: Data,
        imageSize: CGSize,
        instruction: String
    ) -> GeminiRequest {
        let base64 = imageData.base64EncodedString()
        let w = Int(imageSize.width.rounded())
        let h = Int(imageSize.height.rounded())
        let userContent = GeminiContent(role: "user", parts: [
            .inlineData(GeminiInlineData(mimeType: "image/png", data: base64)),
            .text("AI가 시킨 지시:\n\(instruction)\n\n위 화면 (\(w)x\(h) px) 기준으로 응답해주세요."),
        ])
        let systemContent = GeminiContent(role: nil, parts: [
            .text(Prompts.systemPrompt)
        ])
        return GeminiRequest(
            contents: [userContent],
            systemInstruction: systemContent,
            generationConfig: GeminiGenerationConfig(
                responseMimeType: "application/json",
                responseSchema: Self.responseSchema,
                temperature: 0.2,
                maxOutputTokens: 2048
            )
        )
    }

    /// Flat fixed responseSchema (OpenAPI subset, no oneOf/anyOf — Gemini 미지원).
    /// `AnalysisResult` Codable shape 1:1 mirror (`raw`는 dispatcher 후채움 → 제외).
    nonisolated static let responseSchema: JSONSchema = .object(
        properties: [
            "screen_state": .string,
            "next_action": .string,
            "target_text": .string,
            "target_role": .string,                       // optional — AX role hint
            "coordinates": .array(items: .integer),
            "reasoning": .string,
        ],
        required: ["screen_state", "next_action", "target_text", "reasoning"]
    )
}

// MARK: - Gemini API Request shapes

struct GeminiRequest: Encodable, Sendable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent
    let generationConfig: GeminiGenerationConfig
}

struct GeminiContent: Encodable, Sendable {
    let role: String?
    let parts: [GeminiPart]

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(role, forKey: .role)
        try c.encode(parts, forKey: .parts)
    }

    private enum CodingKeys: String, CodingKey {
        case role, parts
    }
}

enum GeminiPart: Encodable, Sendable {
    case text(String)
    case inlineData(GeminiInlineData)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode(t, forKey: .text)
        case .inlineData(let d):
            try c.encode(d, forKey: .inlineData)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case inlineData
    }
}

struct GeminiInlineData: Encodable, Sendable {
    let mimeType: String
    let data: String  // base64 raw, no "data:image/png;base64," prefix
}

struct GeminiGenerationConfig: Encodable, Sendable {
    let responseMimeType: String
    let responseSchema: JSONSchema
    let temperature: Double
    let maxOutputTokens: Int
}

/// OpenAPI-subset response schema. Gemini는 flat fixed만 (no oneOf/anyOf).
/// `indirect enum` — Swift struct는 자기참조 stored property 금지 (infinite size).
indirect enum JSONSchema: Encodable, Sendable, Equatable {
    case string
    case integer
    case array(items: JSONSchema)
    case object(properties: [String: JSONSchema], required: [String])

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string:
            try c.encode("STRING", forKey: .type)
        case .integer:
            try c.encode("INTEGER", forKey: .type)
        case .array(let items):
            try c.encode("ARRAY", forKey: .type)
            try c.encode(items, forKey: .items)
        case .object(let props, let req):
            try c.encode("OBJECT", forKey: .type)
            try c.encode(props, forKey: .properties)
            try c.encode(req, forKey: .required)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, properties, items, required
    }
}

// MARK: - Gemini API Response shapes

struct GeminiResponse: Decodable, Sendable {
    let candidates: [Candidate]
}

struct Candidate: Decodable, Sendable {
    let content: CandidateContent?
    let finishReason: String?
}

struct CandidateContent: Decodable, Sendable {
    let parts: [CandidatePart]
}

struct CandidatePart: Decodable, Sendable {
    let text: String?
}
