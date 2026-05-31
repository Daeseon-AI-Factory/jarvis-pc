//
//  QwenLocalDispatcher.swift
//  ScreenBridge — Phase 9.0 (Local-first, 사용자 결정 2026-05-31)
//
//  Qwen2.5-VL-3B 4-bit via mlx-swift-examples (MLXVLM). 100% on-device — Mac에서만,
//  외부 cloud 0. 5-layer 보안 Layer 4 (진짜 답).
//
//  Probe D-prime (Week 1): 5 fixture sanity check
//  - 1Password vault / 카카오뱅크 / Mail compose / Slack DM / Notion
//  - 80%+ 정확도 → 진행
//  - <70% → fallback (Gemma 3 / InternVL / Moondream 평가)
//
//  성능 (예상, M1 8GB load-on-demand):
//  - First-launch download ~2GB (Hugging Face mlx-community/Qwen2.5-VL-3B-Instruct-4bit)
//  - Cold start 2-4s "보안 모드 켜는 중..." UI
//  - Inference 4-8s (vs Gemini 8-15s — 비슷 또는 빠름)
//  - RAM peak 3-4GB (load-on-demand 30초 idle unload)
//  - Disk 1.9-2.2GB
//
//  Apple FM swap path (v0.4, WWDC26 발표 시): LLMDispatcher protocol 그대로,
//  FoundationModelDispatcher swap 12-24h.
//

import CoreGraphics
import Foundation
// Phase 9.0 dep — mlx-swift-examples
// 첫 build 시 ~1-2GB Metal artifacts download. 그 후 incremental.
// import MLXVLM
// import MLXLMCommon

/// Local Qwen2.5-VL-3B dispatcher. 100% on-device.
///
/// **상태**: Phase 9.0 Week 1 skeleton. `analyze(...)` 는 *Probe D-prime 박힘 전*엔
/// `notImplemented` throw. Week 1 fixture sanity check 완료 후 실제 inference wire.
///
/// **Privacy invariant**: 이 dispatcher는 *외부 network 호출 0*.
/// `URLSession` 사용 X. mlx-swift는 *Hugging Face download 시*만 network (첫 launch).
/// 그 후 모든 inference local.
actor QwenLocalDispatcher: LLMDispatcher {
    /// 모델 식별자 — Hugging Face hub. mlx-community 양자화된 버전 사용.
    private let modelID: String

    /// Model loaded 상태 — load-on-demand pattern (M1 8GB RAM 부담 작게).
    /// nil = 모델 unload, 첫 호출 시 load.
    /// Phase 9.0 wire 시점에 ModelContainer 또는 비슷한 type으로 박음.
    private var modelLoaded: Bool = false

    /// 마지막 inference 시점 — idle unload trigger (30s 후 자동 unload).
    private var lastUsedAt: Date?

    /// 30초 idle 후 모델 unload (M1 8GB RAM 회수).
    private let idleUnloadAfter: TimeInterval = 30

    init(modelID: String = "mlx-community/Qwen2.5-VL-3B-Instruct-4bit") {
        self.modelID = modelID
    }

    /// 사용자가 dispatcher 결정 시 (env-based 또는 setting toggle).
    /// 단순화 — Always available (Phase 9.0). Setting toggle은 Week 7-8에 박음.
    static func make() -> QwenLocalDispatcher {
        return QwenLocalDispatcher()
    }

    func analyze(
        imageData: Data,
        imageSize: CGSize,
        instruction: String
    ) async throws -> AnalysisResult {
        // Phase 9.0 Week 1 — skeleton. 실제 inference wire는 Week 2-3.
        // 현재 호출 시 notImplemented throw — Probe D-prime 시점에 wire.
        Log.dispatcher.notice("[qwen] Phase 9.0 skeleton — not implemented (Week 2-3 wire)")
        throw DispatcherError.invalidResponse("qwen_phase_9_0_skeleton — not implemented")

        // Week 2-3 wire 예정 — pseudo:
        //
        // 1. 모델 load (lazy):
        //    if !modelLoaded {
        //        Log.dispatcher.info("[qwen] loading Qwen2.5-VL-3B 4-bit (~2-4s cold start)")
        //        // VLMModelFactory.shared.load(modelID: modelID) 등
        //        modelLoaded = true
        //    }
        //
        // 2. Image → CVPixelBuffer 또는 MLXArray
        //    Vision/CoreGraphics → MLX 호환 tensor
        //
        // 3. Prompt 박음:
        //    let systemPrompt = Prompts.systemPrompt  // 기존 Gemini용 재사용
        //    let userPrompt = "AI가 시킨 지시:\n\(instruction)\n\n..."
        //
        // 4. Generate (structured output):
        //    Qwen은 *responseSchema 없음* — JSON 강제는 system prompt + parse retry.
        //    또는 *constraint-based decoding* (mlx-swift-examples 지원 확인 필요).
        //
        // 5. AnalysisResult 박음 + 반환 + lastUsedAt = Date()
        //
        // 6. Background idle unload (30s 후) — separate Task.
    }

    /// First-launch model download. Phase 9.0 Week 2-3에 wire.
    /// ~2GB download from Hugging Face. 진행률 UI 박음 (SwiftUI ProgressView).
    func ensureModelDownloaded() async throws {
        Log.dispatcher.notice("[qwen] ensureModelDownloaded — not implemented (Week 2-3 wire)")
        throw DispatcherError.invalidResponse("qwen_download_skeleton")
    }

    /// Idle unload — 30초 idle 시 RAM 회수 (M1 8GB 부담 작게).
    /// Background Task에서 호출.
    func unloadIfIdle() async {
        guard modelLoaded else { return }
        guard let last = lastUsedAt else { return }
        let idle = Date().timeIntervalSince(last)
        guard idle >= idleUnloadAfter else { return }
        Log.dispatcher.info("[qwen] idle unload — RAM 회수 (idle=\(Int(idle), privacy: .public)s)")
        modelLoaded = false
        lastUsedAt = nil
        // 실제 unload (Week 2-3 wire): model deinit 또는 명시 release.
    }

    // Phase 9.0 Week 2-3 추가 method:
    // - func parsePromptResponse(_ text: String) throws -> AnalysisResult
    // - func preprocessImage(_ data: Data, size: CGSize) throws -> /* tensor */
}
