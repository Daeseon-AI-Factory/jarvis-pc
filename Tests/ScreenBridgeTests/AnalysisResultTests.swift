//
//  AnalysisResultTests.swift
//  ScreenBridgeTests — Phase 2.1
//

import Testing
import Foundation
@testable import ScreenBridge

@Suite("AnalysisResult")
struct AnalysisResultTests {

    @Test("decodes snake_case JSON to camelCase fields")
    func decodesSnakeCase() throws {
        let json = """
        {
            "screen_state": "GitHub settings page",
            "next_action": "여기 [Add SSH key] 버튼 누르세요",
            "target_text": "Add SSH key",
            "coordinates": [120, 340, 180, 36],
            "reasoning": "사용자가 SSH 키를 추가하려 함"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(AnalysisResult.self, from: json)

        #expect(result.screenState == "GitHub settings page")
        #expect(result.nextAction == "여기 [Add SSH key] 버튼 누르세요")
        #expect(result.targetText == "Add SSH key")
        #expect(result.coordinates == [120, 340, 180, 36])
        #expect(result.reasoning == "사용자가 SSH 키를 추가하려 함")
        #expect(result.raw == "")
    }

    @Test("coordinates omitted → nil (OCR will determine)")
    func coordinatesOptional() throws {
        let json = """
        {
            "screen_state": "Vercel env page",
            "next_action": "여기 [Environment Variables] 탭 누르세요",
            "target_text": "Environment Variables",
            "reasoning": "사용자가 env 추가 위해 탭 이동 필요"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(AnalysisResult.self, from: json)

        #expect(result.coordinates == nil)
        #expect(result.targetText == "Environment Variables")
    }

    @Test("encode produces snake_case JSON without raw")
    func encodesSnakeCaseWithoutRaw() throws {
        let result = AnalysisResult(
            screenState: "test",
            nextAction: "여기 [Save] 누르세요",
            targetText: "Save",
            coordinates: [10, 20, 100, 40],
            reasoning: "save 필요",
            raw: "raw should be excluded"
        )

        let data = try JSONEncoder().encode(result)
        let dict = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(dict["screen_state"] as? String == "test")
        #expect(dict["next_action"] as? String == "여기 [Save] 누르세요")
        #expect(dict["target_text"] as? String == "Save")
        #expect(dict["reasoning"] as? String == "save 필요")
        #expect(dict["raw"] == nil)

        let coords = try #require(dict["coordinates"] as? [Int])
        #expect(coords == [10, 20, 100, 40])
    }

    @Test("withRaw populates raw, other fields unchanged")
    func withRawHelper() {
        let base = AnalysisResult(
            screenState: "s",
            nextAction: "n",
            targetText: "t",
            reasoning: "r"
        )
        let withRaw = base.withRaw("{\"k\":\"v\"}")

        #expect(withRaw.raw == "{\"k\":\"v\"}")
        #expect(withRaw.screenState == base.screenState)
        #expect(withRaw.nextAction == base.nextAction)
        #expect(withRaw.targetText == base.targetText)
        #expect(withRaw.coordinates == base.coordinates)
        #expect(withRaw.reasoning == base.reasoning)
    }

    @Test("missing required field throws")
    func missingRequiredFieldThrows() {
        let json = """
        {
            "screen_state": "missing next_action",
            "target_text": "X",
            "reasoning": "..."
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AnalysisResult.self, from: json)
        }
    }
}
