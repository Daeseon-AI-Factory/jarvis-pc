//
//  GeminiDispatcherTests.swift
//  ScreenBridgeTests — Phase 2.3
//

import Testing
import Foundation
import CoreGraphics
@testable import ScreenBridge

@Suite("GeminiDispatcher")
struct GeminiDispatcherTests {

    @Test("responseSchema는 AnalysisResult shape 1:1 mirror (raw 제외)")
    func responseSchemaCoversAnalysisResult() {
        let s = GeminiDispatcher.responseSchema
        guard case .object(let props, let req) = s else {
            Issue.record("responseSchema must be .object")
            return
        }
        // Phase 6.1 정책 (lock-in): coordinates는 fallback only. OCR matcher가 target_text로
        // 99% deterministic 좌표 결정 — coordinates는 schema 외 (LLM 추정은 OCR 실패 시만).
        #expect(Set(req) == Set(["screen_state", "next_action", "target_text", "reasoning"]))
        #expect(props["screen_state"] == .string)
        #expect(props["next_action"] == .string)
        #expect(props["target_text"] == .string)
        #expect(props["reasoning"] == .string)
        #expect(props["coordinates"] == .array(items: .integer))
        // raw는 schema에 없음 (dispatcher가 후채움 — DECISIONS Phase 2.1)
        #expect(props["raw"] == nil)
    }

    @Test("responseSchema는 Gemini-accepted JSON shape으로 encode")
    func responseSchemaEncodes() throws {
        let data = try JSONEncoder().encode(GeminiDispatcher.responseSchema)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["type"] as? String == "OBJECT")
        let required = try #require(json["required"] as? [String])
        #expect(Set(required) == Set(["screen_state", "next_action", "target_text", "reasoning"]))

        // OneOf/anyOf 절대 등장 X (Gemini 미지원)
        let raw = try #require(String(data: data, encoding: .utf8))
        #expect(!raw.contains("oneOf"))
        #expect(!raw.contains("anyOf"))
    }

    @Test("requestBody — image part가 FIRST, text가 AFTER (Gemini quirk)")
    func requestBodyImageFirst() throws {
        let req = GeminiDispatcher.buildRequestBody(
            imageData: Data([0x89, 0x50, 0x4E, 0x47]),  // PNG magic
            imageSize: CGSize(width: 1024, height: 768),
            instruction: "이 화면에서 Sign in 어디?"
        )

        let userContent = try #require(req.contents.first)
        #expect(userContent.role == "user")
        #expect(userContent.parts.count == 2)

        // FIRST = inlineData, AFTER = text
        if case .inlineData(let d) = userContent.parts[0] {
            #expect(d.mimeType == "image/png")
            #expect(!d.data.isEmpty)
            #expect(!d.data.contains("data:"))  // base64 raw, no prefix
        } else {
            Issue.record("first part should be inlineData")
        }
        if case .text(let t) = userContent.parts[1] {
            #expect(t.contains("AI가 시킨 지시"))
            #expect(t.contains("Sign in"))
            #expect(t.contains("1024x768"))
        } else {
            Issue.record("second part should be text")
        }

        // systemInstruction = SYSTEM_PROMPT, role 없음
        #expect(req.systemInstruction.role == nil)
        if case .text(let s) = req.systemInstruction.parts.first {
            #expect(s == Prompts.systemPrompt)
        } else {
            Issue.record("systemInstruction.parts[0] should be text")
        }
    }

    @Test("requestBody encode — generationConfig responseSchema 포함")
    func requestBodyEncodesWithSchema() throws {
        let req = GeminiDispatcher.buildRequestBody(
            imageData: Data(),
            imageSize: CGSize(width: 100, height: 100),
            instruction: "test"
        )
        let data = try JSONEncoder().encode(req)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let genConfig = try #require(json["generationConfig"] as? [String: Any])
        #expect(genConfig["responseMimeType"] as? String == "application/json")
        let schema = try #require(genConfig["responseSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "OBJECT")
    }

    @Test("fromEnvironment — GEMINI_API_KEY 있으면 non-nil, 없으면 nil")
    func fromEnvironmentBehavior() {
        let key = Env.string("GEMINI_API_KEY")
        let dispatcher = GeminiDispatcher.fromEnvironment()
        if key == nil || key?.isEmpty == true {
            #expect(dispatcher == nil)
        } else {
            #expect(dispatcher != nil)
        }
    }

    @Test("GeminiResponse decode — Gemini 실제 envelope 형식")
    func geminiResponseDecode() throws {
        let envelope = """
        {
          "candidates": [{
            "content": {
              "parts": [{
                "text": "{\\"screen_state\\":\\"GitHub settings\\",\\"next_action\\":\\"여기 [Add SSH key] 누르세요\\",\\"target_text\\":\\"Add SSH key\\",\\"reasoning\\":\\"사용자가 SSH 키 추가 요청\\"}"
              }]
            },
            "finishReason": "STOP"
          }]
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(GeminiResponse.self, from: envelope)
        let candidate = try #require(resp.candidates.first)
        #expect(candidate.finishReason == "STOP")
        let content = try #require(candidate.content)
        let part = try #require(content.parts.first)
        let text = try #require(part.text)
        // text 자체가 AnalysisResult JSON
        let result = try JSONDecoder().decode(AnalysisResult.self, from: text.data(using: .utf8)!)
        #expect(result.targetText == "Add SSH key")
        #expect(result.nextAction.contains("여기"))
    }

    // MARK: - Phase 7.1.5 — parseRetryAfterFromBody (429 quota respect)

    @Test("parseRetryAfterFromBody — Gemini 실제 quota body extract")
    func parseRetryAfterRealBody() {
        let body = #"{"message": "Quota exceeded for metric: ... limit: 20, model: gemini-2.5-flash\nPlease retry in 29.667199528s.", "code": 429}"#
        let result = GeminiDispatcher.parseRetryAfterFromBody(body)
        #expect(result == 29.667199528)
    }

    @Test("parseRetryAfterFromBody — 정수 초")
    func parseRetryAfterInt() {
        let body = "Please retry in 30s"
        #expect(GeminiDispatcher.parseRetryAfterFromBody(body) == 30.0)
    }

    @Test("parseRetryAfterFromBody — body에 없으면 nil (exp backoff fallback)")
    func parseRetryAfterMissing() {
        #expect(GeminiDispatcher.parseRetryAfterFromBody("Rate limit exceeded, try later") == nil)
        #expect(GeminiDispatcher.parseRetryAfterFromBody("") == nil)
        #expect(GeminiDispatcher.parseRetryAfterFromBody("{\"error\": \"unknown\"}") == nil)
    }

    @Test("parseRetryAfterFromBody — 짧은 wait (1.5초)")
    func parseRetryAfterShort() {
        let body = "Please retry in 1.5s"
        let result = GeminiDispatcher.parseRetryAfterFromBody(body)
        #expect(result == 1.5)
    }
}
