# Latency Optimization Playbook

A transferable engineering playbook for cutting latency in LLM-backed, vision-heavy, or desktop-agent products. Synthesized from the ScreenBridge investigation (2026-05-29) across six dimensions: vision-LLM, macOS SDK, general LLM API, perceived UX, async patterns, and measurement.

**How to use this file:** Start a new project, skim the priority table, jump to the decision tree that matches your situation, and apply the first 3 tricks for that situation. Re-read after first measurement (you will be wrong about where the bottleneck is).

---

## TL;DR — first 15 minutes on any new vision-LLM project

These three are universally safe, zero-eval-required, and capture ~60% of the easy latency budget:

1. **Image downscale to 1024-1280px long edge** (5min). Vendors bill tokens by pixels and downscale anyway. Anywhere above ~1.19 MP is pure waste on Claude; ~1280px is the safe floor for screen UIs.
2. **JPEG q80 instead of PNG** for the upload (5min). 5-15x request body cut. Zero token-billing change.
3. **Put the image BEFORE the text** in your message (5min). Anthropic + Gemini both explicit. Free accuracy lift -> fewer retries.

If you do nothing else, do these three. Then measure before doing #4.

---

## The Priority Table

Sorted by impact * (1 / effort). Apply roughly top-down, but consult the decision tree below for situation-specific reordering.

| # | Trick | Impact | Effort | Apply first when |
|---|---|---|---|---|
| 1 | Image downscale to model native cap | 30-55% LLM latency + 40% token cost | 5min | Any vision LLM uploading >1024px |
| 2 | JPEG q80 / WebP lossy | 5-15x upload size cut | 5min | Upload >200KB, photographic content |
| 3 | Progressive UI (named stages) | 12s feels like 3s per stage | 1h | Pipeline has >=2 real stages, total >3s |
| 4 | async let / TaskGroup | sum -> max collapse | 30min | DAG has 2+ independent calls |
| 5 | Connection keep-alive + region pin | 100-400ms per warm call | 30min | Desktop/mobile w/ sparse repeated calls |
| 6 | Tight maxOutputTokens | Caps p99 runaway (9s -> 1.1s) | 5min | Output shape bounded |
| 7 | Friendly error + retry policy | Halves post-error abandonment | 1h | Any production LLM call |
| 8 | Critical-path measurement (signpost) | Decides next 5 optimizations | 1h | BEFORE applying tricks past #1-2 |
| 9 | responseSchema + low temperature | No parse-retry storms | 30min | Programmatic consumer |
| 10 | Streaming SSE | TTFT 0.6s vs full 8-15s | 1h | Text UI can render partial |
| 11 | Image-first text-after | Free accuracy lift | 5min | Always |
| 12 | AX batched attribute fetch | 6x IPC reduction | 1h | Any tree walk needing >=2 attrs/node |
| 13 | Frontmost-only AX + role-tier depth | ~10x AX phase cut | 30min | Agent/RPA targeting current focus |
| 14 | Vision OCR fast preset | 2-5x OCR speedup | 30min | OCR is fuzzy-matcher, not transcript |
| 15 | Task cancellation propagation | Frees quota on supersede | 30min | User-cancellable flow |
| 16 | Cold-start warm-up | Hides first-trigger handshake | 30min | Resident app, launch != first action |
| 17 | Elapsed counter + reveal animation | Eliminates 'frozen' panic | 1h | Reliably >3s ops |
| 18 | Retry: 1 immediate + exp backoff | Recovers transients politely | 1h | All production LLM calls |
| 19 | Explicit timeout tuning | Fail fast on hangs | 5min | Always |
| 20 | Synthetic monitoring vs fixtures | Auto-detect regression | 1d | After fixtures stable |
| 21 | Tier swap (Flash-Lite/Haiku) | 3-6x cost cut | 1d | AFTER your eval set exists |
| 22 | Prompt caching | 10x cost + 50-80% TTFT on prefix | 1d | Stable >=1024 tokens reused 3+ in TTL |
| 23 | Speculative prefetch (cheap stages) | Hides wait under input time | 1d | Predictable flow, free stages only |
| 24 | P50/P95/P99 telemetry | Average lies; tail decides UX | 1d | After measurement working |
| 25 | Sound + haptic feedback | 10s wait -> 0s perceived | 1h | Ops >5s + user can multitask |

---

## Decision tree — pick a path based on situation

### "I'm starting a new vision-LLM project"
Apply #1, #2, #11 (the TL;DR trio). Then add #8 (signpost measurement) before anything else. Do NOT start with prompt caching, tier swap, or streaming — those need eval set + telemetry.

### "End-to-end is 5s+ and I don't know where the time goes"
1. #8 — Add signpost or ContinuousClock at every stage boundary (1h)
2. #1 — Apply downscale FIRST even before measuring; it eliminates the most common confound
3. #6 — Cap maxOutputTokens; you're probably bleeding worst-case decode time

Resist: A/B-ing models, buying prompt caching, switching to gRPC. None of these matter if you can't see the breakdown.

### "Users say it 'feels frozen' but my numbers say 8-15s which is normal for vision LLMs"
1. #3 — Progressive UI with REAL stages (1h, single biggest perceived-latency win)
2. #17 — Elapsed counter + result reveal fade-in (1h)
3. #7 — Friendly error messages (1h, for the failure path)

Reject: skeleton screens (wrong for single-result UI), cute message rotation (gets annoying at 50x/day), optimistic content rendering (predicting wrong actively misleads).

### "DAG analysis shows independent sub-calls running serially"
1. #4 — async let / TaskGroup (30min, the sum -> max collapse)
2. #15 — Use Task (not Task.detached) so cancellation propagates (30min)
3. #8 — Re-measure critical path AFTER parallelizing (1h; verify the slow call moved)

Watch: rate limits (4 parallel = 4x quota burn) and that the new max() isn't the same call as before.

### "Desktop / menu-bar / tray app with sparse calls"
1. #5 — Single shared URLSession + region-pinned endpoint (30min)
2. #16 — Cold-start warm-up call on app activation (30min)
3. #19 — Explicit timeouts (5min)

Reject: prompt caching (5min TTL evaporates between user triggers), edge cache (unique per call). Listen for `NSWorkspace willSleepNotification` to invalidate stale connections.

### "Agent / RPA / screen-reader pipeline (OCR + AX + LLM)"
1. #12 — Batched attribute fetch (1h, the single biggest AX win)
2. #13 — Frontmost-only filter + role-tiered depth cap (30min)
3. #14 — OCR fast preset since you're fuzzy-matching against known targets (30min)

Do NOT apply ROI cropping if OCR's role is to RESCUE wrong LLM bboxes — bootstrapping from the bad signal defeats the purpose. Tier depth cap by bundle ID: Electron 4, native Cocoa 8.

### "Production errors showing up in logs / abandonment after errors"
1. #18 — Retry policy: 1 immediate + exp backoff cap 3 (1h)
2. #19 — Explicit request + resource timeouts (5min)
3. #7 — Friendly error mapping with collapsible details (1h)

Pair Anthropic retries with Idempotency-Key. Don't lose forensic info — friendly text + collapsible raw error + log path.

### "Evaluating a cheaper/faster model tier"
1. #20 — Synthetic monitoring vs fixtures FIRST (1d, you need a baseline)
2. #21 — A/B on YOUR real eval set, not vendor MMLU (1d)
3. #24 — P50/P95/P99 over N>=100 (1d)

Vendor benchmarks don't predict your accuracy. Groq Llama 4 Scout looked great on paper, collapsed to 76s on real vision use. Don't trust "feels faster" — measure percentiles.

### "Chat / agent loop / repeating system prompt within 5 min"
1. #22 — Prompt caching with cache_control on last static block (1d)
2. #10 — Streaming response (1h)
3. #9 — responseSchema for tool-use stability (30min)

Cache requires BYTE-EXACT prefix match; one whitespace invalidates. Cache write costs 1.25-2x — net negative at <3 reuses.

### "User input takes 2-3s before LLM call (typing, selection)"
1. #23 — Speculative prefetch CHEAP stages only (screenshot, OCR, local lookup) (1d)
2. #3 — Progressive UI showing 'captured -> waiting for query' (1h)
3. #17 — Optimistic UI for trigger acknowledgment only (1h)

NEVER speculatively call paid LLM endpoints — wrong predictions burn quota. Apply optimistic UI to chrome (panel appearing, button feedback) — NEVER to semantic content (predicted arrow direction).

---

## Anti-patterns (do not apply blindly)

| Anti-pattern | Why it backfires |
|---|---|
| `.fast` OCR for transcripts shown to users | Skips small/stylized text; only safe when downstream fuzzy-matches |
| Prompt caching for sparse desktop tools | 5min TTL evaporates; write cost makes it net negative |
| Streaming with structured JSON output | Partial JSON isn't valid until complete; can't render usefully |
| Optimistic UI for semantic content | Wrong prediction = active misdirection (user trusts you) |
| Skeleton screens for single-result outputs | Arrow that points nowhere is worse than a spinner |
| Speculative LLM call on input change | Burns free-tier quota on wrong predictions |
| Race / multi-vendor parallel for cost-bounded tasks | N-vendor parallel = N-x cost; only for read-only + latency >> cost |
| Trimming system prompt to shave 5 tokens | Caching gives 90% of the benefit at 0% accuracy cost; trim is over-rated |
| Cute rotating status messages on productivity tools | Whimsy ages into annoyance at 50x/day |
| Edge cache (Cloudflare Worker) for personalized prompts | Hit rate ~0 + adds privacy boundary; only helps high-duplicate workloads |
| Lowering temperature to "speed up" the model | Temperature doesn't change per-token decode; on Gemini 3+ it CAUSES loops |
| Tier swap before having an eval set | "Feels faster" lies; you need percentiles + accuracy on real data |
| Task.detached for "more parallelism" | Loses cancellation propagation; leaks running work on user supersede |
| Cache + memoization on always-unique inputs | Lookup overhead > hit savings; screenshots almost never repeat byte-for-byte |
| Trusting URLSession defaults for timeouts | 60s/7d defaults are landmines; tune both knobs explicitly |
| gRPC for a desktop client | 50ms transport savings vs 10s LLM time is noise; the dep weight isn't justified |

---

## The four transferable principles

If you remember nothing else from this playbook:

1. **Measure first, optimize second.** Optimizing off the critical path is a 0-impact activity. Spend the first hour on signpost / ContinuousClock instrumentation before any code changes past the TL;DR trio.

2. **Perceived latency dominates actual latency.** Above 3s wall-clock, UX work (progressive stages, elapsed counter, friendly errors) beats engineering work. A 12s op with 4 named stages feels like a 3s op with one spinner.

3. **The vendor will pay you to pre-process on the client.** Image downscale, JPEG compression, tight maxOutputTokens — all are pure wins because the vendor was going to do the same work anyway, on your dime.

4. **Cold and warm are different products.** Average them and you optimize neither. Resident vs launch-per-call architecture flips which one dominates; design for the one your users actually hit.

---

## Maintenance

When applying a trick from this playbook to a new project, log it in that project's DECISIONS.md (5-part: options / trade-off / choice / rationale / reversal cost) — even if you adopted it from here. The trade-offs are context-dependent and your future self needs to know whether the decision was deliberate or copied.

When you discover a NEW trick that should be in here, add it with: mechanism, impact (with numbers), trade-off, when-to-apply, transferable-to. Padding with generic advice is worse than omitting.

---

*Last synthesized: 2026-05-29 from ScreenBridge 6-dimension sweep (vision-LLM, macOS SDK, general LLM API, perceived UX, async patterns, measurement). Reflect on it; don't follow it as gospel.*


---

## Priority order (전체 25 tricks, 효과 큰 순)

1. **[5min] Image downscale to model's native cap (1024-1280 long edge)** — 30-55% Gemini latency cut + ~40% token cost cut; Anthropic bills same tokens for 1.19MP and 2MP so anything above is pure waste
   - apply when: Any vision LLM call where you send a screenshot/photo larger than 1024px long edge. Single biggest lever, near-zero accuracy cost above 768px.

2. **[5min] JPEG q80 / WebP lossy instead of PNG for vision uploads** — 5-15x request body reduction (2MB PNG -> 180KB JPEG), saves ~1.5s upload on residential 10Mbps uplink, zero billed-token change
   - apply when: Upload size > 200KB, image is screenshot/photographic (not pure line art/QR/tiny text). Especially KR/mobile networks where uplink << downlink.

3. **[1h] Progressive UI (named multi-stage status)** — Strongest perceived-latency win — 12s opaque wait feels like 3s per stage. Doubles as transparency/trust.
   - apply when: Pipeline has >=2 real stages and total wall-clock > 3s. Stages must already exist (no faking).

4. **[30min] async let / TaskGroup for independent sub-tasks (critical-path collapse)** — sum(A,B,C) -> max(A,B,C). 3 tasks of 1s/2s/3s: 6s -> 3s. Universally underused — most devs serialize by reflex.
   - apply when: DAG analysis reveals 2+ independent calls in your pipeline (OCR + vision LLM, multi-region capture, parallel tool_use). Compile-time-fixed fan-out: async let; runtime N: TaskGroup.

5. **[30min] Connection keep-alive + region-pinned endpoint (warm URLSession)** — 100-400ms saved per warm call (skip TCP+TLS handshake), 150-300ms TTFT swing from region (asia-northeast1 vs us-central1 for KR users)
   - apply when: Desktop/mobile app with sparse-but-repeated API calls. ALWAYS use a single shared URLSession; pin region closest to users that data policy allows.

6. **[5min] Tight maxOutputTokens cap (~1.5x p99 observed)** — Caps worst-case runaway: 2048 cap @ 225 TPS = 9s; cutting to 256 = 1.1s. Doesn't slow happy path.
   - apply when: Output shape is bounded/structured. Most production apps leave the vendor default (4-8k) — a latency landmine.

7. **[1h] Friendly error messages with retry + collapsible details** — Halves abandonment after errors. Reframes failure as recoverable transient.
   - apply when: Any LLM API integration that will hit 429/timeout/401 in production (i.e. all of them). Wrap dispatcher errors with user-cause-action mapping.

8. **[1h] Critical path identification + signpost measurement** — Decides which OTHER optimizations matter. Optimizing non-critical-path = 0 wall-clock change. 1h investment guides next week of work.
   - apply when: BEFORE applying any other latency trick beyond #1-2. 'OCR is slow' might be irrelevant if Gemini is the 90% path.

9. **[30min] responseSchema / structured output + low temperature** — Eliminates parse-retry storms (each retry = 2-15s). Enables client-side response cache on temp=0.
   - apply when: Output is consumed programmatically (agent, tool-use, coordinate extraction). Skip for human-facing chat. On Gemini 3+, keep temp=1.0 and cache externally.

10. **[1h] Streaming response (SSE) for any UX that can render partial** — TTFT 0.6s vs full 8-15s = ~60-90% perceived-latency cut
   - apply when: Text-first UI (chat, write-as-you-think, progressive status). SKIP when only final structured JSON matters AND you can't parse partial.

11. **[5min] Image-first, text-after ordering in prompt** — Free accuracy win on Claude+Gemini (both vendors explicit). Fewer retries -> indirect latency win.
   - apply when: Always.

12. **[1h] AXUIElementCopyMultipleAttributeValues batching** — 6x mach IPC reduction per AX node. On a 2000-element tree, single biggest available AX win.
   - apply when: Any AX/UIAutomation/AT-SPI tree walk needing >=2 attrs per node. Universal across all OS automation tree APIs.

13. **[30min] Frontmost-only AX filter + role-tiered depth cap** — ~10x AX phase cut (1-2s -> <200ms). Combine with #12.
   - apply when: Automation/RPA tool targeting current user focus. Include {frontmost, dock, controlcenter, systemuiserver} only.

14. **[30min] Vision OCR fast preset (.fast + usesLanguageCorrection=false + minimumTextHeight)** — Each ~20-35% latency cut, stack to ~2-5x speedup. Free when OCR is a secondary signal matched against known target strings.
   - apply when: OCR is a matcher/locator (not user-facing transcript) AND targets are >=12pt UI labels. NOT for doc OCR / accessibility transcripts.

15. **[30min] Cancellation propagation (Task.cancel on supersede)** — Frees CPU/GPU/quota when user re-triggers. Prevents abandoned-run contention.
   - apply when: Any user-cancellable flow (ESC, re-trigger, navigation). Use Task (not Task.detached) to inherit cancellation.

16. **[30min] Cold-start warm-up (URLSession handshake on launch)** — First-trigger latency cut by skip of TCP+TLS. First impression matters disproportionately.
   - apply when: Resident menu-bar/tray app where launch != first user action. NOT when user fires immediately on launch.

17. **[1h] Time estimate display + elapsed counter + result reveal animation** — Frozen-app perception eliminated. User waits 15s without aborting. 200ms reveal animation makes result feel noticed-immediately.
   - apply when: Operations reliably > 3s. Use REAL p50/p95 telemetry, not guesses — wrong estimates collapse trust worse than no estimate.

18. **[1h] Retry policy: 1 immediate + exp backoff with jitter (cap 3)** — Recovers transient network blips without storming 429s. Combine with idempotency-key on Anthropic for safe POST retry.
   - apply when: All production LLM calls. Surface failure to UI after cap — user is staring at the panel.

19. **[5min] Timeout tuning (request vs resource, never vendor defaults)** — Fail fast on stuck servers (Gemini 30-120s stalls happen) without killing legit slow generations.
   - apply when: Always set both timeoutIntervalForRequest and timeoutIntervalForResource explicitly. Tune per endpoint (vision longer, short text tighter).

20. **[1d] Synthetic monitoring (nightly bench against fixtures)** — Auto-catches regression ('yesterday 8s, today 12s after commit X'). Connects R4 (test gate) to perf budget.
   - apply when: Phase 2+ after fixtures stable. Mind free-tier quota burn — sample, don't run full eval nightly.

21. **[1d] Tier swap (Flash-Lite/Haiku for bounded tasks, Flash/Sonnet for reasoning)** — Flash-Lite ~3-6x cheaper + slight TTFT win. Haiku 4.5 vs Sonnet 4.6: $1/$5 vs $3/$15.
   - apply when: AFTER eval set exists. Validate per-use-case on YOUR real data, not vendor's MMLU. Groq Llama 4 Scout 76s collapse is the cautionary tale.

22. **[1d] Prompt caching (Anthropic ephemeral / Gemini context cache)** — 10x cost cut + 50-80% TTFT cut on cached prefix. Killer for chat sessions / agent loops.
   - apply when: Stable system prompt >=1024 tokens (Sonnet) / >=4096 (Haiku) / >=32k (Gemini 2.5 Flash) AND reused >=3 times within TTL. REJECT for sparse-trigger desktop tools.

23. **[1d] Speculative prefetch (capture-on-panel-open, before submit)** — Hides multi-second wait under user input time. 13s -> 10s perceived for 3s typing flow.
   - apply when: Predictable user-action sequence AND prefetch op is cheap (capture is free; LLM call is NOT — burns quota). Privacy-OK to act before explicit consent.

24. **[1d] P50/P95/P99 percentile telemetry (never average)** — Average lies: 'avg 10s' could be 'P50 8s P99 25s' = 5% users abandoning. Foundation for SLO.
   - apply when: After basic measurement working. Need N>=100 samples for meaningful P99.

25. **[1h] Sound + haptic feedback (DND-aware, opt-in)** — Converts 10s blocking wait to 0s perceived — user multitasks during wait. Haptic for trigger-ack, sound for completion.
   - apply when: Operations > 5s AND user can productively switch focus. ALWAYS respect macOS DND/Focus modes; default off.


---

## ScreenBridge — Pending Tricks (Backlog)

- **JPEG q80 instead of PNG** 
  - impact: ?
  - next: Replace CGImageDestination PNG encoder with JPEG q80 in ScreenCapture pipeline; measure upload bytes before/after on 1024px capture

- **Tier swap to Flash-Lite** 
  - impact: ?
  - next: After fixtures eval set exists (Phase 3+), A/B Gemini 2.5 Flash vs Flash-Lite on real ScreenBridge corpus; only swap if accuracy drop < 5%

- **Tight maxOutputTokens (256-512)** 
  - impact: ?
  - next: GeminiDispatcher.swift:175 currently 2048; drop to 512; verify no truncation in fixtures sample

- **HTTP/2 + keep-alive + region pin + inline base64** 
  - impact: ?
  - next: Switch to single shared URLSession; add launch-time warm-up call to generativelanguage.googleapis.com; evaluate asia-northeast1 for KR users

- **VNRecognizeTextRequest .fast** 
  - impact: ?
  - next: OCRService — flip recognitionLevel to .fast; verify ElementMatcher fuzzy match still resolves target_text on Mom's UI screenshots in fixtures/

- **usesLanguageCorrection = false** 
  - impact: ?
  - next: OCRService — disable; matcher does fuzzy contains/Levenshtein so 1-2 char errors survive

- **minimumTextHeight = 0.01-0.015** 
  - impact: ?
  - next: Set conservatively (0.01); log box-count-at-0 vs box-count-at-threshold during dogfooding to detect missed menu-bar items

- **regionOfInterest (ROI) cropping** 
  - impact: ?
  - next: Defer — Gemini bbox can be wrong; ROI bootstrapping defeats the rescue path. Reconsider for AX-focused-window ROI (skip wallpaper/other monitors)

- **AX depth cap with role tiering** 
  - impact: ?
  - next: Tier maxDepth=4 for Electron/Chromium bundle IDs, depth=8 for native Cocoa; current uniform 8 hurts on Slack/Chrome

- **Frontmost-only AX filter** 
  - impact: ?
  - next: Limit walk to {frontmost PID, com.apple.dock, com.apple.controlcenter, com.apple.systemuiserver}; expected 10x AX phase cut

- **AXUIElementCopyMultipleAttributeValues batching** 
  - impact: ?
  - next: Replace 6 sequential AXUIElementCopyAttributeValue calls per node with one batched call; biggest AX optimization available

- **SCStreamConfiguration .nominal** 
  - impact: ?
  - next: Switch from .best to .nominal; saves 100-300ms per capture + reduces memory pressure on Retina

- **CGImageDestination PNG (skip NSBitmapImageRep)** 
  - impact: ?
  - next: Refactor to remove AppKit import from ScreenCapture; pair with JPEG q80 switch

- **vImage downscale instead of CGContext** 
  - impact: ?
  - next: Defer to Phase 7+ (streaming preview); not the current bottleneck

- **Connection keep-alive (single URLSession)** 
  - impact: ?
  - next: Audit dispatcher for per-call URLSession() creation; replace with shared instance

- **Retry exp backoff + 1 immediate** 
  - impact: ?
  - next: Add to GeminiDispatcher: ECONNRESET -> 1 immediate; 429/503 -> exp 1s/2s/4s ±20% jitter, cap 3

- **timeoutIntervalForRequest + Resource** 
  - impact: ?
  - next: Set request=30s, resource=45s on shared URLSession config

- **Region-pinned endpoint (asia-northeast1)** 
  - impact: ?
  - next: Free-tier generativelanguage.googleapis.com auto-routes; for paid migration to Vertex, choose asia-northeast1. Track as DECISIONS.md entry when revisited

- **Anthropic prompt caching** 
  - impact: ?
  - next: Only when Sonnet fallback is wired (Phase 4+) — cache system + tool schemas, place dynamic content after cache boundary

- **Idempotency-Key (Anthropic)** 
  - impact: ?
  - next: Add to dispatcher when Sonnet fallback exists; UUID per logical attempt

- **WebSocket/SSE streaming** 
  - impact: ?
  - next: Same blocker as #4 — structured JSON output can't be streamed usefully until partial parse path exists

- **Compression (gzip request/response)** 
  - impact: ?
  - next: Verify URLSession auto-decompresses responses; enable Content-Encoding: gzip for >50KB image payloads or migrate to Gemini Files API for repeat uses

- **Loading message specificity** 
  - impact: ?
  - next: Wait for telemetry to know real p50/p95 — hardcoded '3-5초' on a 10s op destroys trust. Phase 1 task: instrument first

- **Elapsed counter display** 
  - impact: ?
  - next: Add SwiftUI TimelineView counter to TriggerPanel during analyzing state

- **Progressive UI (multi-stage status)** 
  - impact: ?
  - next: Expose existing pipeline stages (capture/OCR/AX/LLM/render) as named status in TriggerPanel — THE single biggest perceived-latency win for ScreenBridge

- **Subtle continuous animation** 
  - impact: ?
  - next: NSProgressIndicator or SF Symbols hierarchical pulse in panel; avoid bouncy custom spinners

- **Stage progress bar (weighted)** 
  - impact: ?
  - next: Pair with progressive UI #44; weight by real p50 per stage from telemetry

- **Sound feedback (DND-aware)** 
  - impact: ?
  - next: Settings toggle, default off; NSSound system 'Tink' or 'Pop'; suppress on Focus/DND

- **Haptic feedback on trigger** 
  - impact: ?
  - next: NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) on hotkey-press only

- **Speculative prefetch (cheap stages only)** 
  - impact: ?
  - next: TriggerPanel open -> immediately capture + OCR + AX (free); withhold LLM call until submit. Phase 2-3 candidate

- **Doherty/Nielsen threshold budget** 
  - impact: ?
  - next: Add stage budget to DECISIONS.md: <100ms hotkey ack, <1s stage transitions, <10s total or audio alert

- **Status message rotation** 
  - impact: ?
  - next: Keep dry — productivity tool used 50x/day. Rotate only within stage exceeding p75; stop after p99 and show 'still working — Cmd+. cancel'

- **Result reveal animation** 
  - impact: ?
  - next: SwiftUI .transition(.opacity).animation(.easeOut(duration: 0.2)) on overlay; no bounce/scale

- **Friendly error messages** 
  - impact: ?
  - next: Map dispatcher errors: timeout -> '느려요 다시?', 429 -> '오늘 할당량 다 썼어요', 401 -> 'API 키 확인 (.env)', generic -> 'logs/build.log 확인'

- **TaskGroup (dynamic fan-out)** 
  - impact: ?
  - next: Future: multi-display capture, multi-window AX query

- **Speculative execution (prefetch on hint)** 
  - impact: ?
  - next: Same as #50 — cheap stages on panel open

- **Cold-start warm-up (URLSession handshake)** 
  - impact: ?
  - next: Fire dummy HEAD to generativelanguage.googleapis.com on app activation; justifies 'menu bar -> ready' promise

- **Task priority** 
  - impact: ?
  - next: Mark dispatcher Task .userInitiated, build.log flush .utility

- **Cancellation propagation on supersede** 
  - impact: ?
  - next: Replace isRunning-rejects-new with cancel-old-start-new pattern; better UX when user adjusts instruction mid-flight

- **Backpressure (AsyncStream buffering)** 
  - impact: ?
  - next: When Phase 5.x stage stream lands, use .bufferingNewest(1) for HUD consumer

- **Streaming partial LLM result** 
  - impact: ?
  - next: Biggest wall-clock perceived lever — defer to Phase 7+ once response schema can support partial parse

- **OSSignposter (Instruments)** 
  - impact: ?
  - next: Add to AnalyzeCoordinator phase boundaries (capture/OCR/AX/dispatcher/render) THIS WEEK — gates all other measurement work

- **ContinuousClock** 
  - impact: ?
  - next: Replace Date() spans in dispatcher logging

- **Instruments Time Profiler** 
  - impact: ?
  - next: Run once after signpost lands to inspect OCR/AX local CPU hotspots

- **Instruments Network** 
  - impact: ?
  - next: Run on cold + warm trigger to decompose Gemini 10s into DNS/TLS/server-processing

- **Custom signpost track** 
  - impact: ?
  - next: Phase 2+: emit image-size + OCR-token-count metadata for dimension breakdowns

- **P50/P95/P99 percentile** 
  - impact: ?
  - next: Once N>=50 real triggers logged, compute percentiles from logs/build.log structured entries

- **Cold vs warm separation** 
  - impact: ?
  - next: Tag first-trigger-after-launch separately in telemetry; justifies/refutes menu-bar architecture in DECISIONS.md

- **A/B test framework (model comparison)** 
  - impact: ?
  - next: v0.2+ when dispatcher swap reconsidered; gate Sonnet/Haiku adoption on evidence not vibes

- **Synthetic monitoring (nightly bench)** 
  - impact: ?
  - next: After fixtures stable: run dispatcher against N fixture screens nightly, alert on p95 regression. Mind 250 RPD cap — sample 10/night


---

## Transferable Patterns (다음 프로젝트 transfer)

### Measure-first, optimize-second (critical-path discipline)

**Principle:** Optimizing anything OFF the critical path produces zero wall-clock change. Before any latency work past the trivial #1-#2, instrument the pipeline with stage boundaries (signpost/ContinuousClock). The instrumentation buys 'we know what to fix next' for months.

**Examples:**
- ScreenBridge: Gemini 8-15s dominates; cutting OCR 300ms -> 50ms saves 0 wall-clock until LLM phase is also addressed
- Build systems (bazel/buck): action graph critical path determines build time; parallelism cap on non-critical tasks is harmless
- Web request handling: DB query taking 80% of latency makes service-layer micro-optimizations invisible
- ML training: data loader bottleneck masks model arch improvements

### Vendor pays for what you send (pre-resize/pre-compress on client)

**Principle:** Anywhere the server bills tokens/units proportional to input size AND will downscale anyway, do the downscale on the client. You save (a) upload bytes, (b) billed tokens, (c) server-side preprocessing time — all three for one cheap client op. The rule of thumb 'width*height/750 = tokens' is publishable across vendors.

**Examples:**
- Vision LLMs: Anthropic caps at 1.19MP, Gemini tiles at 768x768 — sending 4K is paying for nothing
- Image search / OCR APIs: Google Vision API rate-limits and bills per pixel-tier
- Audio transcription (Whisper): downsample to 16kHz mono before sending — server does it anyway
- Embedding APIs: truncate to model's max context before sending; server truncates silently otherwise

### Perceived latency >= actual latency (progressive disclosure of stages)

**Principle:** Humans rate '4 short visible waits' as faster than '1 long opaque wait' of equal total time. If your pipeline has real stages, name them in the UI. Brain treats each transition as progress (dopamine), even if no individual stage finished faster. This is THE highest-leverage UX trick for any >3s op.

**Examples:**
- ScreenBridge: 12s opaque 'analyzing' -> '캡처중 / OCR중 / AI분석중 / 좌표매칭중' feels 3-4x shorter
- Compilers/linters: tsc / cargo prints staged progress; users tolerate 30s builds because each line proves liveness
- Image generation UIs (Midjourney, DALL-E): show 'composing / refining / upscaling' steps even though they're loose abstractions
- Checkout flows: 'verifying card / authorizing / confirming' beats a 3s spinner

### Fan-out independent work; max() not sum()

**Principle:** Most engineers serialize by reflex even when calls are independent. Draw the dependency DAG. If A and B both depend on X but not each other, run them concurrent (async let / Promise.all / goroutine + WaitGroup). Wall-clock collapses from sum to max. Universally underused.

**Examples:**
- ScreenBridge: OCR + Gemini both depend on screenshot but not each other -> async let collapses 8s+0.3s sequential to 8s parallel
- API aggregator: user profile + recent orders + recommendations -> Promise.all not await chain
- Multi-vendor LLM ensemble: gemini + claude + openai run concurrent, pick best/first
- Microservice fan-out: validate-user + check-inventory + compute-tax independent -> parallel
- Test harnesses: independent test files in parallel runners

### Connection reuse + region-pin = quietly the biggest network win

**Principle:** A single shared URLSession (or http.Client, or HttpClient) reuses TCP+TLS across requests, saving ~1-2 RTTs per warm call. Adding region-pinned endpoints (closest to user) saves another 100-300ms RTT. These cost a few lines of config and are invisible until you measure. Most apps create per-call clients out of inertia and pay the handshake every time.

**Examples:**
- Mobile/desktop apps with sparse API calls: warm pool + closest region = first-trigger 200-500ms faster
- Serverless cold-start mitigation: provisioned concurrency + region affinity
- DB clients: pgx pool, JDBC pool — same pattern at TCP/protocol layer
- CDN selection: pick edge based on user IP geolocation

### Bound the worst case (tight maxOutputTokens, tight timeouts)

**Principle:** Vendor defaults are tuned for vendor's worst-case use (large generations possible), not yours. Most apps have known output shape (~120 tokens, ~5s typical) but leave maxOutputTokens=4096 and timeoutIntervalForRequest=60s — landmines for p99. Set bounds at ~1.5x your observed p99. Doesn't slow happy path, hard-caps tail.

**Examples:**
- LLM API: maxOutputTokens 256 instead of vendor default 4096 -> worst-case 1.1s instead of 9s decode runaway
- HTTP clients: explicit request + connection timeout vs default 'forever'
- DB queries: SET statement_timeout = '5s' for OLTP paths
- Cron jobs: --timeout flag instead of 'run until OOM killer'

### OCR/recognition cheap presets when downstream fuzzy-matches

**Principle:** Heavy recognition modes (.accurate + language correction) exist for transcripts shown to humans. When the consumer is a fuzzy string matcher against a KNOWN target (agent click-targeting, UI test harnesses), recall of clean glyphs is what matters — 1-2 character noise still resolves via Levenshtein. Switch to .fast + disable correction + raise min-text-height. 2-5x speedup is free.

**Examples:**
- ScreenBridge: OCR is a target_text matcher, not a transcript -> .fast + no correction
- RPA frameworks (UiPath, Playwright): locate-by-text against known label -> cheap preset
- OCR-as-search-index: don't run accurate OCR on 1M doc archive when fuzzy index handles typos
- QR/barcode detection: detector preset, not recognition preset

### Tree-walk APIs: batch attribute fetches + filter scope + role-tier depth

**Principle:** AX/AT-SPI/UIAutomation/DOM walking is dominated by per-node IPC round-trips. Three multiplicative wins: (1) batch attribute fetch (one IPC for N attrs), (2) filter to user-focused scope (frontmost app, not every running process), (3) cap depth by node-role-class (Electron deep + low-signal -> shallow cap; native Cocoa -> deeper). Each is 2-10x; stacked is 50-100x.

**Examples:**
- ScreenBridge: 6 sequential AXUIElementCopyAttributeValue -> 1 AXUIElementCopyMultipleAttributeValues
- Browser DOM walking: document.querySelectorAll over getElementsByX loops with property lookups
- Filesystem tree walks: stat() batching via getdents+statx
- Kubernetes informers: list+watch with field selectors instead of polling every pod

### Errors should re-frame as recoverable (user-cause-action mapping)

**Principle:** Raw error codes/stack traces make users blame themselves and quit. Map error class -> human cause -> retry action. Pair with retry policy: 1 immediate (network blip) + exp backoff (429/503) + cap. Halves post-error abandonment. Critical for free-tier LLMs that WILL hit quota/429 in normal operation.

**Examples:**
- ScreenBridge: 429 -> '오늘 할당량 다 썼어요 (내일 리셋)' + Retry button, not 'HTTP 429'
- OAuth flows: 'session expired — sign in again' button vs 'invalid_grant'
- Payment flows: 'card declined by bank, try another?' vs error code from gateway
- File uploads: 'connection dropped — resume from 80%?' vs network error

### Prompt caching pays back at >=3 reuses within TTL — not before

**Principle:** Anthropic cache write costs 1.25-2x normal input; cache read costs 0.1x. Math: net negative at 1-2 calls, breakeven ~3 calls, big win at 10+. Sparse desktop tools with >5min gaps between user triggers DON'T qualify. Chat sessions, agent loops, batch eval DO. Same pattern shape applies to any 'pre-compute warm vs lazy' decision.

**Examples:**
- Anthropic prompt caching: chat assistants (10s gaps) win huge; menu-bar tools (10min gaps) lose
- CDN edge cache: cache TTL must outlive user re-fetch interval
- ML model warm pools: keep loaded if traffic > N rps, evict if sparse
- JIT compilation cache: hot functions compile once, cold functions interpret

### Speculation is free when cheap, expensive when paid

**Principle:** Prefetch / speculative execution wins when wrong-prediction cost is small (free CPU, local cache fill) and loses when wrong-prediction cost is real (LLM API quota, billable infra). Decompose your pipeline: speculate on the free stages (capture, OCR, local AX query) and gate the paid stages (LLM call) on explicit user submit.

**Examples:**
- ScreenBridge: speculate on screen capture (free) at panel-open; never speculate on Gemini call (250 RPD cap)
- Search autocomplete: speculate on local index search; gate paid third-party search on Enter
- GitHub Copilot: speculative inline completions are cheap relative to chat-mode latency value
- Browser link prefetch: <link rel=prefetch> is cheap; speculative POST is dangerous

### Average lies; percentiles tell the truth

**Principle:** 'Average latency 10s' could be 'P50 8s, P99 25s' meaning 5% of users abandon. SLO design, vendor evaluation, regression detection — all require P50/P95/P99 over N>=100 samples. Average is the second-worst metric (max is the worst). HdrHistogram-style bucketing keeps O(1) memory.

**Examples:**
- LLM vendor SLA validation: 'avg TTFT 600ms' meaningless without P99
- API rate-limit tuning: P99 latency under load decides whether to add capacity
- ML model serving: tail latency dominates user experience even when average is fine
- CI/CD pipeline budgets: median build time hides 'every Friday afternoon takes 45 min'

### Cold vs warm: separate the metrics, separate the optimizations

**Principle:** First call (cold: process launch, no cache, no connection) and Nth call (warm: handshake reused, cache hot) are different products with different fixes. Averaging them hides both. Cold optimizations (warm-up call at launch, cache preheating) help first impressions. Warm optimizations (keep-alive, prompt cache) help repeat use. Resident vs launch-per-trigger architecture flips which dominates.

**Examples:**
- ScreenBridge menu-bar: 1 cold, 1000s warm -> warm dominates. Optimize keep-alive.
- CLI tools (launch-per-call): every call is cold. Optimize startup, lazy-init carefully.
- Serverless lambda: provisioned concurrency targets cold separately from execution time
- Mobile app launch: first-launch tutorials hide cold start; subsequent launches need different perf budget

### Cancellation propagation as a quota-saving feature

**Principle:** Structured concurrency (Swift Task tree, JS AbortController, Go context.Context) propagates cancellation to in-flight network calls. When user supersedes (re-types, navigates away, hits new hotkey), the abandoned request CAN be killed before it bills. Most code path 'guards against double-trigger' by REJECTING new work — better UX is to CANCEL old work and accept new.

**Examples:**
- ScreenBridge: replace isRunning-rejects-new with cancel-old-start-new -> instant responsiveness to user's revised intent
- Search-as-you-type: cancel previous keystroke's fetch when next keystroke arrives
- Map navigation: cancel old route calculation when destination changes
- Chat streams: abort previous stream when user sends new message

### Document trade-offs at decision time; future-you needs the 'why not'

**Principle:** When choosing between A and B for a latency lever, write the trade-off as 5-part (options / trade-off / choice / rationale / reversal cost). Six months later when 'should we add streaming?' resurfaces, you'll have the answer with reasons, not a second debate from scratch. Maps to ScreenBridge R9 / DECISIONS.md pattern.

**Examples:**
- ScreenBridge: streaming rejected because structured JSON output can't usefully stream — documented, so next session doesn't re-investigate
- Architecture decision records (ADRs) in any service
- RFC docs in standards bodies
- DECISIONS.md for any non-trivial trade-off (model swap, dispatcher choice, framework selection)

