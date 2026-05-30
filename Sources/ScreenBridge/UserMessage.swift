//
//  UserMessage.swift
//  ScreenBridge — Phase 4.2
//
//  DispatcherError + ScreenCapture.CaptureError → 비-AI-native 친화 한국어.
//  jargon 금지 ("VNRequest failed" X), 다음 액션 시사 ("다시 시도", "키 확인").
//

import Foundation

enum UserMessage {

    static func from(_ error: DispatcherError) -> String {
        switch error {
        case .missingAPIKey:
            return "AI 키가 없어요. 설정에서 등록해주세요."

        case .network:
            return "인터넷 연결을 확인해주세요."

        case .httpStatus(let code, _) where code == 401 || code == 403:
            return "AI 키가 잘못된 것 같아요. 다시 확인해주세요."

        case .httpStatus(let code, _) where code == 429:
            return "오늘 무료 사용량을 다 썼어요. 잠시 후 다시 시도하거나 키를 바꿔주세요."

        case .httpStatus:
            return "AI가 잠시 응답하지 않아요. 잠시 후 다시 시도해주세요."

        case .decoding, .invalidResponse:
            return "AI 응답을 알아볼 수 없어요. 다시 시도해주세요."

        case .maxTokens:
            return "응답이 너무 길어요. 화면이 복잡하면 좀 더 단순한 부분으로 다시 시도해주세요."

        case .retriesExhausted:
            return "여러 번 시도했지만 실패했어요. 잠시 후 다시 시도해주세요."
        }
    }
}
