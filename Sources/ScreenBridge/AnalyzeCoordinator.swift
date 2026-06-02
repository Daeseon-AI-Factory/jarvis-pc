//
//  AnalyzeCoordinator.swift
//  ScreenBridge — Phase 4.2
//
//  capture + dispatcher 흐름. 중복 trigger reject (actor isolation).
//
//  Phase 4.2는 단일 `.done`/`.failed` 반환. Phase 5.x에서 stage stream 가능.
//

import CoreGraphics
import Foundation

actor AnalyzeCoordinator {
    private let capture: ScreenCaptureService
    private let dispatcher: LLMDispatcher
    private let ocr: OCRService
    private let ax: AXService
    private var isRunning: Bool = false

    // Phase 7.0: SessionState scaffold. Transition은 7.1에서 wire (AppDelegate hotkey 분기).
    // 지금은 *snapshot 가능*만 — 외부 코드가 state 읽을 수 있으나 자동 transition X.
    enum SessionState: Sendable, Equatable {
        case idle
        case analyzing(stepIndex: Int)
        case waitingForUserClick(stepIndex: Int, deadlineAt: Date)
        case completed
        case cancelled(reason: CancelReason)
    }
    enum CancelReason: Sendable, Equatable {
        case userEsc, idleTimeout, error, appQuit
    }

    private var sessionState: SessionState = .idle
    private(set) var sessionID: String?
    private(set) var history: [StepSummary] = []
    // Phase 7.1: 첫 instruction 저장 → continuation에서 LLM에 *같은 instruction* 박음.
    // 사용자가 매 step 재입력할 필요 X.
    private(set) var currentInstruction: String?
    // 45s idle timeout — waitingForUserClick 진입 시 set. 다음 transition (continue / cancel / complete) 시 unset.
    private(set) var idleDeadline: Date?
    // Phase 7.3: audit log entry — session 통째 박음. 매 step append + finalize 시 save.
    private var auditEntry: SessionAuditEntry?

    init(
        capture: ScreenCaptureService = LiveScreenCapture(),
        dispatcher: LLMDispatcher,
        ocr: OCRService = VisionOCRService(),
        ax: AXService = LiveAXService()
    ) {
        self.capture = capture
        self.dispatcher = dispatcher
        self.ocr = ocr
        self.ax = ax
    }

    /// 외부 코드 (AppDelegate)가 state 읽을 때. await 강제 — race 차단 (synthesis risk #2).
    func snapshotState() -> SessionState { sessionState }

    /// Phase 7.1: 진짜 continuation. AppDelegate가 waitingForUserClick state 시 호출.
    /// 같은 instruction + history 누적된 previousSteps로 LLM에 다음 step 물음.
    /// req.instruction / sessionID / previousSteps는 caller가 박지 X — coordinator state 사용.
    func continueSession() async -> AnalyzeStage {
        guard let prevInstruction = currentInstruction,
              let prevSessionID = sessionID else {
            Log.dispatcher.notice("[session] continueSession: no active session, fallback to idle")
            sessionState = .idle
            return .failed(.invalidResponse("no_active_session"))
        }
        Log.dispatcher.info("[session] continue — sessionID=\(prevSessionID, privacy: .public) step=\(self.history.count + 1, privacy: .public) instruction=\"\(prevInstruction, privacy: .public)\"")
        let req = AnalyzeRequest(
            instruction: prevInstruction,
            triggeredAt: Date(),
            sessionID: prevSessionID,
            previousSteps: history.isEmpty ? nil : history
        )
        return await run(req, isContinuation: true)
    }

    /// 사용자가 cancel — esc / menu-bar item / 새 task 시작 / completion 후 timeout.
    func cancelSession(reason: CancelReason) {
        let prevID = sessionID
        // Phase 7.3: audit finalize + save (취소도 박음 — 어디서 멈췄나 분석 가능).
        if var entry = auditEntry {
            entry.outcome = (reason == .idleTimeout) ? .cancelledByTimeout : .cancelledByUser
            entry.completedAt = Date()
            SessionAuditLog.save(entry)
        }
        auditEntry = nil
        sessionState = .cancelled(reason: reason)
        sessionID = nil
        currentInstruction = nil
        history.removeAll()
        idleDeadline = nil
        Log.dispatcher.info("[session] cancel — reason=\(String(describing: reason), privacy: .public) prevID=\(prevID ?? "nil", privacy: .public) audit saved")
        // .cancelled → 다음 hotkey 시 .idle로 자동 복귀 (sentinel transition).
        sessionState = .idle
        // v0.3 Inspector: cancel publish.
        Task { @MainActor in
            InspectorState.shared.finishCancelled()
        }
    }

    /// idleDeadline 초과 시 호출 — AppDelegate가 timer로 check.
    func checkIdleTimeout() -> Bool {
        guard let deadline = idleDeadline else { return false }
        guard Date() >= deadline else { return false }
        Log.dispatcher.info("[session] idle timeout — auto-cancel")
        cancelSession(reason: .idleTimeout)
        return true
    }

    /// Analyze 1회 실행. 진행 중이면 즉시 `.failed(.invalidResponse)` 반환.
    /// `isContinuation=true`면 기존 session state 유지. 새 task (false)는 fresh session 시작.
    func run(_ req: AnalyzeRequest, isContinuation: Bool = false) async -> AnalyzeStage {
        if isRunning {
            Log.dispatcher.notice("[analyze] reject — 이미 진행 중")
            return .failed(.invalidResponse("이미 분석 중"))
        }
        isRunning = true
        defer { isRunning = false }

        // v0.3 Layer 2: SensitivityRouter — 민감 앱 (1Password / 은행 / 카드 등) 검사.
        // Qwen local 박힌 후 (v0.3+) → .localOnly로 swap. v0.2는 fail-closed 차단.
        // 단 isContinuation는 router 통과 시 *이전 session* 그대로 — 매 step router 박지 X
        // (사용자가 첫 trigger 시 안전한 앱이면 continuation 안에서 swap 안 함).
        if !isContinuation {
            let routerDecision = SensitivityRouter.decide(
                frontmostBundleID: req.frontmostBundleID,
                localModelAvailable: false   // v0.3 Qwen wire 후 dynamic check 박음
            )
            switch routerDecision {
            case .cloud:
                break  // 기존 흐름
            case .localOnly:
                Log.dispatcher.info("[router] sensitive app \(req.frontmostBundleID ?? "?", privacy: .public) → local model only")
                // v0.3: Qwen dispatcher로 swap 박음. 현재는 cloud 그대로 (Qwen wire ef81ae6에 박혀있지만 routing X).
                break
            case .blockedLocalModelNotInstalled:
                Log.dispatcher.notice("[router] sensitive app \(req.frontmostBundleID ?? "?", privacy: .public) BLOCKED — Qwen 미설치, cloud 차단")
                return .failed(.invalidResponse("sensitive_app_blocked"))
            }
        }

        // v0.2: secret mask — instruction이 LLM에 가기 *전*, audit log에 박히기 *전*.
        // sk-/AKIA/ghp_/카드/주민번호 등 detect → redact.
        let maskedInstruction = SecretMasker.mask(req.instruction)
        if maskedInstruction != req.instruction {
            let hits = SecretMasker.detect(req.instruction)
            Log.dispatcher.notice("[secret] instruction masked — \(hits.count, privacy: .public) pattern(s): \(hits.map { $0.name }.joined(separator: ","), privacy: .public)")
        }
        // 진짜 req 갱신 — masked version으로 dispatcher 호출.
        let maskedReq = AnalyzeRequest(
            instruction: maskedInstruction,
            triggeredAt: req.triggeredAt,
            sessionID: req.sessionID,
            previousSteps: req.previousSteps
        )

        // Phase 7.1 — session bookkeeping. fresh task면 new sessionID/history,
        // continuation이면 기존 유지. currentInstruction은 첫 run 시 박힘.
        if !isContinuation {
            sessionID = UUID().uuidString
            history.removeAll()
            currentInstruction = maskedInstruction
            // Phase 7.3: audit entry 박음. 매 step append + finalize 시 outcome 갱신.
            // instruction은 *masked* version — disk persist 시점에 이미 secret 제거.
            auditEntry = SessionAuditEntry(
                sessionID: sessionID!,
                instruction: maskedInstruction,
                startedAt: Date(),
                steps: [],
                completedAt: nil,
                outcome: .inProgress
            )
            Log.dispatcher.info("[session] new — sessionID=\(self.sessionID ?? "?", privacy: .public)")
            // v0.3 Inspector: MainActor publish (별도 panel 봄).
            let publishedID = sessionID!
            let publishedInstr = maskedInstruction
            Task { @MainActor in
                InspectorState.shared.beginSession(
                    id: publishedID,
                    instruction: publishedInstr,
                    dispatcherName: "auto",
                    privacyMode: "cloud"
                )
            }
        }
        sessionState = .analyzing(stepIndex: history.count)
        idleDeadline = nil
        // v0.3 Inspector — analyzing 진입 publish.
        let stepIdx = history.count
        Task { @MainActor in
            InspectorState.shared.markAnalyzing(stepIndex: stepIdx)
        }

        Log.dispatcher.info(
            "[analyze] begin — step=\(self.history.count + 1, privacy: .public) instruction \(maskedInstruction.count, privacy: .public) chars continuation=\(isContinuation, privacy: .public)"
        )
        let started = Date()

        // 1. capture
        let imageData: Data
        let geometry: DisplayGeometry
        do {
            (imageData, geometry) = try await capture.captureCursorScreen()
        } catch let err as ScreenCapture.CaptureError {
            Log.dispatcher.error("[analyze] capture failed: \(String(describing: err), privacy: .public)")
            switch err {
            case .permissionDenied:
                return .failed(.invalidResponse("permission_denied"))
            case .noScreen, .displayNotFound:
                return .failed(.invalidResponse("display_unavailable"))
            case .encodeFailed:
                return .failed(.invalidResponse("encode_failed"))
            }
        } catch {
            Log.dispatcher.error("[analyze] capture error: \(error.localizedDescription, privacy: .public)")
            return .failed(.invalidResponse(error.localizedDescription))
        }

        let captureElapsed = Date().timeIntervalSince(started)
        Log.dispatcher.info(
            "[analyze] captured \(imageData.count, privacy: .public) bytes in \(String(format: "%.1f", captureElapsed), privacy: .public)s"
        )

        // 2. dispatcher + OCR + AX 3개 병렬 (Phase 6.2 — AX matcher 추가).
        // v0.2: masked instruction 사용 — secret이 외부 LLM 서버에 안 감.
        async let dispatcherFuture: AnalysisResult = dispatcher.analyze(
            imageData: imageData,
            imageSize: geometry.sentSize,
            instruction: maskedInstruction
        )
        async let ocrFuture: [OCRBox] = ocr.recognize(
            pngData: imageData,
            sentSize: geometry.sentSize
        )
        async let axFuture: [AXElement] = ax.queryAllElements()

        let result: AnalysisResult
        do {
            result = try await dispatcherFuture
        } catch let err as DispatcherError {
            Log.dispatcher.error("[analyze] dispatcher failed: \(String(describing: err), privacy: .public)")
            return .failed(err)
        } catch {
            Log.dispatcher.error("[analyze] dispatcher error: \(error.localizedDescription, privacy: .public)")
            return .failed(.invalidResponse(error.localizedDescription))
        }

        // OCR 실패는 fatal X — AX 또는 LLM coords fallback.
        let ocrBoxes: [OCRBox]
        do {
            ocrBoxes = try await ocrFuture
        } catch {
            Log.dispatcher.error("[analyze] OCR failed (not fatal): \(error.localizedDescription, privacy: .public)")
            ocrBoxes = []
        }

        // AX 실패도 fatal X — 권한 거부 또는 일부 앱 (Electron 등) tree 비어있음.
        let axElements: [AXElement]
        do {
            axElements = try await axFuture
        } catch {
            Log.dispatcher.notice("[analyze] AX failed (not fatal): \(error.localizedDescription, privacy: .public)")
            axElements = []
        }

        // 3. target_text 매칭 — OCR + AX 합집합 candidate (Phase 6.2).
        // OCRBox → MatchCandidate (sent→logical pt 변환)
        let ocrCandidates: [MatchCandidate] = ocrBoxes.compactMap { box in
            let boxInt = [
                Int(box.rectInSentImage.origin.x.rounded()),
                Int(box.rectInSentImage.origin.y.rounded()),
                Int(box.rectInSentImage.width.rounded()),
                Int(box.rectInSentImage.height.rounded()),
            ]
            guard let logical = geometry.logicalRectFromSentBox(boxInt) else { return nil }
            return MatchCandidate(
                text: box.text,
                rectInLogicalPt: logical,
                confidence: box.confidence,
                source: .ocr
            )
        }
        // AXElement → MatchCandidate (이미 logical pt, confidence 1.0)
        let axCandidates: [MatchCandidate] = axElements.map { el in
            MatchCandidate(
                text: el.text,
                rectInLogicalPt: el.rectInLogicalPt,
                confidence: 1.0,
                source: .ax(role: el.role)
            )
        }
        let allCandidates = ocrCandidates + axCandidates

        // Spatial fusion: LLM coords → logical pt hint.
        let llmHintLogical: CGRect? = result.coordinates.flatMap { coords in
            guard coords.count == 4 else { return nil }
            return geometry.logicalRectFromSentBox(coords)
        }
        // Preferred role: LLM이 명시한 target_role 우선, 없으면 instruction keyword 추론.
        // LLM target_role이 더 정확 (instruction 분석 + 화면 context 둘 다 봄).
        let preferredRole: String?
        if let llmRole = result.targetRole, !llmRole.isEmpty {
            preferredRole = llmRole
            Log.dispatcher.info("[match] preferred role from LLM: \(llmRole, privacy: .public)")
        } else if let inferred = ElementMatcher.inferPreferredRole(from: req.instruction) {
            preferredRole = inferred
            Log.dispatcher.info("[match] preferred role from instruction keyword: \(inferred, privacy: .public)")
        } else {
            preferredRole = nil
        }
        // Multi-target: top 2 distinct candidates. 사용자가 1번/2번 시각 선택 (user-in-the-loop).
        let matches = ElementMatcher.matchTop(
            targetText: result.targetText,
            candidates: allCandidates,
            llmHintRect: llmHintLogical,
            preferredRole: preferredRole,
            maxResults: 2
        )

        // Phase 7.1: 2-layer irreversible-action gate. LLM이 누락해도 backend가 강제 true.
        let isIrreversible = result.requiresConfirmation
            || IrreversibleActions.isIrreversible(nextAction: result.nextAction, targetText: result.targetText)
        if isIrreversible && !result.requiresConfirmation {
            Log.dispatcher.notice("[safety] keyword post-filter → requires_confirmation forced true")
        }
        let safeResult = AnalysisResult(
            screenState: result.screenState,
            nextAction: result.nextAction,
            targetText: result.targetText,
            targetRole: result.targetRole,
            coordinates: result.coordinates,
            reasoning: result.reasoning,
            raw: result.raw,
            taskComplete: result.taskComplete,
            requiresConfirmation: isIrreversible,
            stepActionSummary: result.stepActionSummary
        )

        let totalElapsed = Date().timeIntervalSince(started)
        let matchTag = matches.isEmpty ? "LLM-fallback" : matches[0].sourceTag
        Log.dispatcher.info(
            "[analyze] complete \(String(format: "%.1f", totalElapsed), privacy: .public)s — target_text=\"\(result.targetText, privacy: .public)\" \(matchTag, privacy: .public) matches=\(matches.count, privacy: .public) (ocr=\(ocrBoxes.count, privacy: .public) ax=\(axElements.count, privacy: .public)) irreversible=\(isIrreversible, privacy: .public) task_complete=\(result.taskComplete, privacy: .public)"
        )

        // Phase 7.3: step record append to audit entry.
        let primarySource = matches.first?.sourceTag ?? "LLM-fallback"
        let stepNumber = history.count + 1
        let stepRecord = SessionAuditEntry.StepRecord(
            stepNumber: stepNumber,
            targetText: safeResult.targetText,
            nextAction: safeResult.nextAction,
            sourceTag: primarySource,
            stepActionSummary: safeResult.stepActionSummary,
            requiresConfirmation: safeResult.requiresConfirmation,
            analysisElapsedSec: totalElapsed,
            timestamp: Date()
        )
        auditEntry?.steps.append(stepRecord)

        // v0.3 Inspector: step publish (MainActor).
        let inspectorStep = InspectorState.StepView(
            stepNumber: stepNumber,
            targetText: safeResult.targetText,
            nextAction: safeResult.nextAction,
            sourceTag: primarySource,
            irreversible: safeResult.requiresConfirmation,
            elapsedSec: totalElapsed,
            timestamp: Date()
        )
        Task { @MainActor in
            InspectorState.shared.appendStep(inspectorStep)
        }

        // Phase 7.1: state transition + history 누적.
        if result.taskComplete {
            sessionState = .completed
            idleDeadline = nil
            // Phase 7.3: audit finalize + save.
            auditEntry?.outcome = .completed
            auditEntry?.completedAt = Date()
            if let entry = auditEntry { SessionAuditLog.save(entry) }
            Log.dispatcher.info("[session] task complete — sessionID=\(self.sessionID ?? "?", privacy: .public) total steps=\(self.history.count + 1, privacy: .public) audit saved")
            // v0.3 Inspector: 완료 publish.
            Task { @MainActor in
                InspectorState.shared.finishCompleted()
            }
        } else {
            // step 누적: 이번 step의 *사용자 행동 요약*을 다음 call의 previousSteps에 박을 거.
            // LLM이 step_action_summary 박았으면 사용, 없으면 fallback ("step N 진행").
            let summary = result.stepActionSummary ?? "step \(history.count + 1) 진행 (\(result.targetText))"
            history.append(StepSummary(stepNumber: history.count + 1, actionTaken: summary))
            // waitingForUserClick — 45s idle timeout.
            let deadline = Date().addingTimeInterval(45)
            sessionState = .waitingForUserClick(stepIndex: history.count - 1, deadlineAt: deadline)
            idleDeadline = deadline
            // Phase 7.3: 매 step audit save (atomic) — task complete 안 기다림, 디버그용.
            if let entry = auditEntry { SessionAuditLog.save(entry) }
            Log.dispatcher.info("[session] waitingForUserClick step=\(self.history.count, privacy: .public) deadline=45s summary=\"\(summary, privacy: .public)\"")
        }
        return .done(result: safeResult, geometry: geometry, matches: matches)
    }
}
