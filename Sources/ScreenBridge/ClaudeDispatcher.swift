//
//  ClaudeDispatcher.swift
//  ScreenBridge — Phase 7.2
//
//  Anthropic Messages API + tool_use forced JSON. Gemini 429 daily quota 도달 시
//  FallbackDispatcher가 swap. claude-sonnet-4-6 (vision, 정확도 ↑ vs Gemini Flash).
//  비용 ~$0.003/M input token (Gemini의 30배 — 단 dogfooding에 ₩100-200/월 안 넘음).
//

import CoreGraphics
import Foundation

actor ClaudeDispatcher: LLMDispatcher {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String = "claude-sonnet-4-6") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// `ANTHROPIC_API_KEY` 환경 로드. 없으면 nil — FallbackDispatcher 비활성.
    static func fromEnvironment() -> ClaudeDispatcher? {
        guard let key = Env.string("ANTHROPIC_API_KEY"), !key.isEmpty else { return nil }
        return ClaudeDispatcher(apiKey: key)
    }

    func analyze(
        imageData: Data,
        imageSize: CGSize,
        instruction: String
    ) async throws -> AnalysisResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body = Self.buildRequestBody(
            imageData: imageData, imageSize: imageSize, instruction: instruction, model: model
        )
        request.httpBody = try JSONEncoder().encode(body)

        let w = Int(imageSize.width.rounded())
        let h = Int(imageSize.height.rounded())
        Log.dispatcher.info(
            "[claude] begin — instruction \(instruction.count, privacy: .public) chars, image \(imageData.count, privacy: .public) bytes (\(w, privacy: .public)x\(h, privacy: .public))"
        )
        let started = Date()

        let (data, _) = try await sendWithRetry(request)
        let elapsed = Date().timeIntervalSince(started)

        let claudeResp: ClaudeResponse
        do {
            claudeResp = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8)?.prefix(300) ?? "<non-utf8>"
            Log.dispatcher.error(
                "[claude] envelope decode fail: \(error.localizedDescription, privacy: .public); raw=\(preview, privacy: .public)"
            )
            throw DispatcherError.decoding(error.localizedDescription)
        }

        // tool_use block 찾음 — Claude가 *반드시* respond_with_analysis tool 호출 (tool_choice forced).
        guard let toolUse = claudeResp.content.first(where: { $0.type == "tool_use" }),
              let inputValue = toolUse.input else {
            Log.dispatcher.error("[claude] no tool_use block — stop_reason=\(claudeResp.stopReason ?? "?", privacy: .public)")
            throw DispatcherError.invalidResponse("no tool_use block")
        }

        // input 자체가 AnalysisResult JSON (snake_case keys). JSONValue → JSONEncoder → AnalysisResult.
        let result: AnalysisResult
        let rawJSON: String
        do {
            let inputData = try JSONEncoder().encode(inputValue)
            result = try JSONDecoder().decode(AnalysisResult.self, from: inputData)
            rawJSON = String(data: inputData, encoding: .utf8) ?? ""
        } catch {
            Log.dispatcher.error(
                "[claude] tool input decode fail: \(error.localizedDescription, privacy: .public)"
            )
            throw DispatcherError.decoding(error.localizedDescription)
        }

        Log.dispatcher.info(
            "[claude] ok \(String(format: "%.1f", elapsed), privacy: .public)s — target_text=\"\(result.targetText, privacy: .public)\""
        )
        return result.withRaw(rawJSON)
    }

    /// 앱 launch 시 TLS handshake 미리. Claude는 *model list* 없음 — 대신 *비싸지 않은* GET
    /// (또는 HEAD). 단 Anthropic은 model list endpoint X — prewarm 효과 작음. POST messages는
    /// cost 발생 → skip. 기본 noop으로 둠.
    func prewarm() async {
        // Anthropic은 public health check endpoint 없음 — prewarm noop.
        // 첫 호출 cold TLS는 받아들임 (Gemini fallback 시점이라 latency 영향 작음).
    }

    /// Exp backoff retry: 429/500/502/503/504. 1/2/4s + jitter. max 2 attempts (Gemini와 동일 정책).
    private func sendWithRetry(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let retryableStatuses: Set<Int> = [429, 500, 502, 503, 504]
        let maxAttempts = 2

        for attempt in 1...maxAttempts {
            let data: Data
            let urlResponse: URLResponse
            do {
                (data, urlResponse) = try await session.data(for: request)
            } catch let urlError as URLError {
                Log.dispatcher.error("[claude] network error: \(urlError.localizedDescription, privacy: .public)")
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
                    "[claude] http \(httpResp.statusCode, privacy: .public) non-retryable: \(body.prefix(300), privacy: .public)"
                )
                throw DispatcherError.httpStatus(httpResp.statusCode, body: String(body.prefix(500)))
            }
            if attempt == maxAttempts {
                Log.dispatcher.error(
                    "[claude] retries exhausted last=\(httpResp.statusCode, privacy: .public) body=\(body.prefix(500), privacy: .public)"
                )
                throw DispatcherError.retriesExhausted(lastStatus: httpResp.statusCode)
            }
            let backoffSec = pow(2.0, Double(attempt - 1)) + Double.random(in: 0...0.3)
            Log.dispatcher.notice(
                "[claude] retry \(attempt, privacy: .public)/\(maxAttempts, privacy: .public) in \(String(format: "%.1f", backoffSec), privacy: .public)s (status=\(httpResp.statusCode, privacy: .public))"
            )
            try await Task.sleep(nanoseconds: UInt64(backoffSec * 1_000_000_000))
        }
        throw DispatcherError.retriesExhausted(lastStatus: 0)
    }

    // MARK: - Request body construction

    /// Anthropic Messages API + tool_use forced JSON. tool_choice {type: "tool", name: ...}로
    /// Claude가 *반드시* respond_with_analysis tool 호출 → input 자체가 JSON.
    static func buildRequestBody(
        imageData: Data,
        imageSize: CGSize,
        instruction: String,
        model: String
    ) -> ClaudeRequest {
        let base64 = imageData.base64EncodedString()
        let w = Int(imageSize.width.rounded())
        let h = Int(imageSize.height.rounded())

        let userMessage = ClaudeMessage(
            role: "user",
            content: [
                .image(ClaudeImageSource(
                    type: "base64",
                    mediaType: "image/png",
                    data: base64
                )),
                .text("AI가 시킨 지시:\n\(instruction)\n\n위 화면 (\(w)x\(h) px) 기준으로 응답해주세요."),
            ]
        )

        return ClaudeRequest(
            model: model,
            maxTokens: 2048,
            system: Prompts.systemPrompt,
            messages: [userMessage],
            tools: [Self.responseTool],
            toolChoice: ClaudeToolChoice(type: "tool", name: "respond_with_analysis")
        )
    }

    /// Forced JSON schema via tool_use. Claude가 *이 tool*만 호출 가능 (tool_choice 강제).
    nonisolated static let responseTool = ClaudeTool(
        name: "respond_with_analysis",
        description: "사용자 화면 분석 결과를 박는 tool — 이 tool 외에는 응답 안 함",
        inputSchema: AnyEncodable([
            "type": "object" as Any,
            "properties": [
                "screen_state": ["type": "string"] as Any,
                "next_action": ["type": "string"] as Any,
                "target_text": ["type": "string"] as Any,
                "target_role": ["type": "string"] as Any,
                "coordinates": ["type": "array", "items": ["type": "integer"]] as Any,
                "reasoning": ["type": "string"] as Any,
                "task_complete": ["type": "boolean"] as Any,
                "requires_confirmation": ["type": "boolean"] as Any,
                "step_action_summary": ["type": "string"] as Any,
            ] as [String: Any],
            "required": ["screen_state", "next_action", "target_text", "reasoning"] as [String],
        ])
    )
}

// MARK: - Anthropic API Request shapes

struct ClaudeRequest: Encodable, Sendable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]
    let tools: [ClaudeTool]
    let toolChoice: ClaudeToolChoice

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
        case toolChoice = "tool_choice"
    }
}

struct ClaudeMessage: Encodable, Sendable {
    let role: String
    let content: [ClaudeContent]
}

enum ClaudeContent: Encodable, Sendable {
    case text(String)
    case image(ClaudeImageSource)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode("text", forKey: .type)
            try c.encode(t, forKey: .text)
        case .image(let src):
            try c.encode("image", forKey: .type)
            try c.encode(src, forKey: .source)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, source
    }
}

struct ClaudeImageSource: Encodable, Sendable {
    let type: String           // "base64"
    let mediaType: String      // "image/png"
    let data: String           // base64 raw

    private enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

struct ClaudeTool: Encodable, Sendable {
    let name: String
    let description: String
    let inputSchema: AnyEncodable

    private enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct ClaudeToolChoice: Encodable, Sendable {
    let type: String   // "tool"
    let name: String   // "respond_with_analysis"
}

/// Type-erased Encodable wrapper for JSON-Schema-as-dictionary (tool input_schema).
/// JSONSerialization → Data → JSON encode 박음. Sendable로 nonisolated static let에 사용 가능.
struct AnyEncodable: Encodable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        // JSON value → Encodable container. 단 SingleValueContainer + JSONSerialization 다시 decode.
        let decoded = try JSONSerialization.jsonObject(with: data)
        var container = encoder.singleValueContainer()
        try Self.encodeJSON(decoded, into: &container)
    }

    private static func encodeJSON(_ value: Any, into container: inout SingleValueEncodingContainer) throws {
        // Dict / array / scalar — JSONEncoder가 *Encodable*만 받음. 변환 필요.
        // Trick: JSONSerialization data → write to container as Data가 아닌, custom Encoder 사용.
        // 가장 간단: wrap into JSONValue enum.
        try container.encode(JSONValue(value))
    }
}

enum JSONValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(_ value: Any) {
        if let v = value as? String { self = .string(v); return }
        if let v = value as? Bool { self = .bool(v); return }
        if let v = value as? Int { self = .int(v); return }
        if let v = value as? Double { self = .double(v); return }
        if let v = value as? [Any] { self = .array(v.map(JSONValue.init)); return }
        if let v = value as? [String: Any] {
            var d: [String: JSONValue] = [:]
            for (k, val) in v { d[k] = JSONValue(val) }
            self = .object(d)
            return
        }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - Anthropic API Response shapes

struct ClaudeResponse: Decodable, Sendable {
    let content: [ClaudeResponseBlock]
    let stopReason: String?

    private enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

struct ClaudeResponseBlock: Decodable, Sendable {
    let type: String                       // "text" | "tool_use"
    let text: String?                      // type=="text" 시
    let name: String?                      // type=="tool_use" 시
    let input: JSONValue?                  // type=="tool_use" 시, Sendable JSON

    private enum CodingKeys: String, CodingKey {
        case type, text, name, input
    }

    /// Tool input을 raw Any 형태로 변환 (JSONSerialization 사용 등).
    func inputAsRaw() -> Any? {
        guard let v = input else { return nil }
        return JSONValue.toRaw(v)
    }
}

extension JSONValue {
    static func toRaw(_ v: JSONValue) -> Any {
        switch v {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let arr): return arr.map(JSONValue.toRaw)
        case .object(let dict):
            var d: [String: Any] = [:]
            for (k, val) in dict { d[k] = JSONValue.toRaw(val) }
            return d
        case .null: return NSNull()
        }
    }
}

// Decodable conformance for JSONValue
extension JSONValue: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }
}
