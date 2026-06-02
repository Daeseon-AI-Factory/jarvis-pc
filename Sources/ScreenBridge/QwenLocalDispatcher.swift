//
//  QwenLocalDispatcher.swift
//  ScreenBridge — Phase 9.0 Week 2-3 wire (2026-05-31)
//
//  Qwen2.5-VL-3B 4-bit via MLXVLM. 100% on-device — Mac에서만, 외부 cloud 0.
//  5-layer 보안 Layer 4 (사용자 결정 "Local LLM 필수").
//
//  Vision input: PNG Data → CIImage → UserInput.Image.ciImage
//  Chat: .system(Prompts.systemPrompt) + .user(instruction) + image
//  Decoding: greedy (temperature 0.0, topK 1, topP 0.001), JSON-via-prompt
//  Retry: 1번 parse fail 시 corrective re-ask
//
//  Privacy invariant: URLSession 0. network = HF Hub download (첫 launch)만.
//  그 후 모든 inference local (Apple Silicon Metal GPU).
//
//  성능 (예상, mlx-community/Qwen2.5-VL-3B-Instruct-4bit):
//  - First-launch download ~2GB
//  - Cold start ~2-4s on M1, ~1-2s on M2/M3
//  - Inference 4-8s (vs Gemini 8-15s — 비슷 또는 빠름)
//  - RAM peak 3-4GB (load-on-demand 30s idle unload)
//  - Disk 1.9-2.2GB
//

import CoreGraphics
import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM

actor QwenLocalDispatcher: LLMDispatcher {
    private let modelID: String
    private var container: ModelContainer?
    private var lastUsedAt: Date?
    private let idleUnloadAfter: TimeInterval = 30

    /// Set once across all instances. 20MB cap prevents MLX cache from ballooning to multi-GB
    /// during long streams on M1 8GB Macs. mlx-swift 0.29: `MLX.GPU.set(cacheLimit:)`.
    private static let cacheCapApplied: Void = {
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
    }()

    init(modelID: String = "mlx-community/Qwen2.5-VL-3B-Instruct-4bit") {
        self.modelID = modelID
        _ = Self.cacheCapApplied
    }

    static func make() -> QwenLocalDispatcher { QwenLocalDispatcher() }

    // MARK: - LLMDispatcher

    func analyze(
        imageData: Data,
        imageSize: CGSize,
        instruction: String
    ) async throws -> AnalysisResult {
        let t0 = Date()
        try await ensureLoaded()
        guard let container else {
            throw DispatcherError.invalidResponse("qwen_container_nil_after_load")
        }

        // 1. PNG Data → CIImage → UserInput.Image.
        //    MLXVLM UserInput.Image는 .ciImage(CIImage) / .url(URL) / .array(MLXArray)만 받음.
        //    NSImage / CGImage / Data 직접 X.
        //    Image는 Chat.Message.user(_:images:) 안에 박음 — pinned 2.21+ API.
        guard let ciImage = CIImage(data: imageData) else {
            throw DispatcherError.invalidResponse("qwen_ciimage_decode_failed")
        }
        let userImage = UserInput.Image.ciImage(ciImage)

        // 2. First attempt: system prompt + user instruction (with image).
        let firstChat: [Chat.Message] = [
            .system(Prompts.systemPrompt),
            .user(instruction, images: [userImage]),
        ]
        let firstRaw = try await runGeneration(
            container: container,
            chat: firstChat,
            attemptLabel: "primary"
        )

        // 3. Parse — strip markdown fences defensively, then JSONDecode.
        if let decoded = try? decodeAnalysisResult(from: firstRaw) {
            lastUsedAt = Date()
            scheduleIdleUnload()
            let dt = Date().timeIntervalSince(t0)
            Log.dispatcher.info("[qwen] analyze ok (primary) \(Int(dt * 1000), privacy: .public)ms")
            return decoded.withRaw(firstRaw)
        }

        Log.dispatcher.notice("[qwen] primary parse failed — retrying with re-ask")

        // 4. Retry once — append assistant turn + corrective user turn.
        //    Swift 6 strict concurrency: rebuild UserInput from scratch (UserInput is consuming sending).
        let retryChat: [Chat.Message] = [
            .system(Prompts.systemPrompt),
            .user(instruction, images: [userImage]),
            .assistant(firstRaw),
            .user("위 응답은 invalid JSON입니다. STRICT JSON only — ```json fence 금지, prose 금지. 같은 schema로 다시 답하세요."),
        ]
        let retryRaw = try await runGeneration(
            container: container,
            chat: retryChat,
            attemptLabel: "retry"
        )

        do {
            let decoded = try decodeAnalysisResult(from: retryRaw)
            lastUsedAt = Date()
            scheduleIdleUnload()
            let dt = Date().timeIntervalSince(t0)
            Log.dispatcher.info("[qwen] analyze ok (retry) \(Int(dt * 1000), privacy: .public)ms")
            return decoded.withRaw(retryRaw)
        } catch {
            let preview = String(retryRaw.prefix(200))
            Log.dispatcher.error("[qwen] retry parse failed — first200=\(preview, privacy: .public)")
            throw DispatcherError.decoding("qwen_json_parse_failed_after_retry: \(preview)")
        }
    }

    // MARK: - Loading

    private func ensureLoaded() async throws {
        if container != nil { return }
        Log.dispatcher.notice("[qwen] cold start — loading \(self.modelID, privacy: .public)")
        let t0 = Date()

        let cfg = ModelConfiguration(id: modelID)
        do {
            self.container = try await VLMModelFactory.shared.loadContainer(
                configuration: cfg
            ) { progress in
                let pct = Int(progress.fractionCompleted * 100)
                if pct % 10 == 0 {
                    Log.dispatcher.info("[qwen] download \(pct, privacy: .public)%")
                }
            }
        } catch {
            throw DispatcherError.invalidResponse("qwen_load_failed: \(error)")
        }

        let dt = Date().timeIntervalSince(t0)
        Log.dispatcher.notice("[qwen] loaded in \(Int(dt * 1000), privacy: .public)ms")
        self.lastUsedAt = Date()
    }

    // MARK: - Generation (mid-level path — exposes .info event for tokens/sec measurement)

    private func runGeneration(
        container: ModelContainer,
        chat: [Chat.Message],
        attemptLabel: String
    ) async throws -> String {
        let userInput = UserInput(
            chat: chat,
            processing: UserInput.Processing(resize: CGSize(width: 1024, height: 1024))
        )

        // Greedy-ish decoding for JSON stability. pinned 2.21+: temperature/topP/maxTokens 박힘.
        // topK는 노출 X — temperature 0.0 + topP 0.001로 사실상 greedy effective.
        // immutable let — Sendable closure 안에서 capture 가능.
        var paramsBuilder = GenerateParameters()
        paramsBuilder.temperature = 0.0
        paramsBuilder.topP = 0.001
        paramsBuilder.maxTokens = 512
        let params = paramsBuilder

        // Swift 6 Sendable closure — accumulate inside, return tuple out.
        let result: (raw: String, info: GenerateCompletionInfo?)
        do {
            result = try await container.perform { context -> (String, GenerateCompletionInfo?) in
                let lmInput = try await context.processor.prepare(input: userInput)
                let stream = try MLXLMCommon.generate(
                    input: lmInput,
                    parameters: params,
                    context: context
                )
                var localRaw = ""
                var localInfo: GenerateCompletionInfo?
                for await event in stream {
                    switch event {
                    case .chunk(let s):
                        localRaw += s
                    case .info(let i):
                        localInfo = i
                    case .toolCall:
                        continue
                    }
                }
                return (localRaw, localInfo)
            }
        } catch {
            throw DispatcherError.invalidResponse("qwen_generate_failed (\(attemptLabel)): \(error)")
        }
        let raw = result.raw
        let info = result.info

        if let info {
            Log.dispatcher.info(
                "[qwen] \(attemptLabel, privacy: .public) tps=\(info.tokensPerSecond, privacy: .public) gen_tokens=\(info.generationTokenCount, privacy: .public) prompt_tokens=\(info.promptTokenCount, privacy: .public)"
            )
            // v0.3 Inspector publish — 사용자가 *진짜 local 작동*인지 시각화.
            let publishedTps = info.tokensPerSecond
            Task { @MainActor in
                InspectorState.shared.lastTokensPerSecond = publishedTps
            }
        }
        return raw
    }

    // MARK: - JSON parse

    private func decodeAnalysisResult(from raw: String) throws -> AnalysisResult {
        let cleaned = stripMarkdownFences(raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw DispatcherError.decoding("qwen_utf8_encode_failed")
        }
        return try JSONDecoder().decode(AnalysisResult.self, from: data)
    }

    /// Strip ```json ... ``` or ``` ... ``` fences if Qwen ignored the no-fence instruction.
    nonisolated private func stripMarkdownFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let firstNewline = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: firstNewline)...])
            } else {
                t = String(t.dropFirst(3))
            }
        }
        if t.hasSuffix("```") {
            t = String(t.dropLast(3))
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Idle unload (RAM 회수)

    private func scheduleIdleUnload() {
        let delay = idleUnloadAfter
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000) + 500_000_000)
            await self?.unloadIfIdle()
        }
    }

    func unloadIfIdle() async {
        guard container != nil else { return }
        guard let last = lastUsedAt else { return }
        let idle = Date().timeIntervalSince(last)
        guard idle >= idleUnloadAfter else { return }
        Log.dispatcher.info("[qwen] idle unload (idle=\(Int(idle), privacy: .public)s)")
        container = nil
        lastUsedAt = nil
        // MLX cache flush 자동 — Memory.cacheLimit 박힌 ceiling.
    }

    // MARK: - First-launch download (explicit pre-fetch for SettingsView UI)

    func ensureModelDownloaded() async throws {
        try await ensureLoaded()
    }
}
