//
//  ModelDownloadProgress.swift
//  ScreenBridge — v0.3 First-launch model download progress
//
//  QwenLocalDispatcher가 ~2GB Hugging Face download 박는 동안 사용자에게 시각화.
//  SwiftUI ProgressView + percent label + 한국어 친화 안내.
//

import Foundation
import SwiftUI

@MainActor
final class ModelDownloadProgress: ObservableObject {
    static let shared = ModelDownloadProgress()

    enum Status: Sendable, Equatable {
        case idle
        case downloading(fractionCompleted: Double)
        case finished
        case failed(String)
    }

    @Published var status: Status = .idle

    /// 모델 ID (예: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit").
    @Published var modelID: String = ""

    /// 첫 launch 박힘 시작 시간 — 진행률 + ETA 추정.
    @Published var startedAt: Date?

    private init() {}

    func begin(modelID: String) {
        self.modelID = modelID
        self.startedAt = Date()
        self.status = .downloading(fractionCompleted: 0)
    }

    func update(fraction: Double) {
        self.status = .downloading(fractionCompleted: fraction)
    }

    func finish() {
        self.status = .finished
    }

    func fail(_ reason: String) {
        self.status = .failed(reason)
    }
}
