import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import {
  PhysicalPosition,
  PhysicalSize,
  currentMonitor,
  getCurrentWindow,
} from "@tauri-apps/api/window";
import {
  AnalysisResult,
  FeedbackValue,
  logBackend,
  recordFeedback,
} from "../lib/ipc";

const OVERLAY_SHOW_EVENT = "sb-overlay-show";

export default function Overlay() {
  const [result, setResult] = useState<AnalysisResult | null>(null);
  const [feedback, setFeedback] = useState<FeedbackValue | null>(null);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    const win = getCurrentWindow();
    // Default state: window passes clicks through so users can keep working.
    void win.setIgnoreCursorEvents(true);
    listen<AnalysisResult>(OVERLAY_SHOW_EVENT, async (event) => {
      setResult(event.payload);
      setFeedback(null);
      // Stretch to cover the active monitor *before* showing so the user
      // never sees a 1×1 dot resize itself.
      const monitor = await currentMonitor();
      if (monitor) {
        await win.setPosition(
          new PhysicalPosition(monitor.position.x, monitor.position.y)
        );
        await win.setSize(
          new PhysicalSize(monitor.size.width, monitor.size.height)
        );
      }
      await win.show();
      await win.setFocus();
      // Stop passthrough while the user is actively reading; clicks should
      // hit the bubble / dismiss surface.
      await win.setIgnoreCursorEvents(false);
      void logBackend("info", "overlay shown");
    }).then((fn) => {
      unlisten = fn;
    });
    return () => unlisten?.();
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") void close();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function close() {
    setResult(null);
    setFeedback(null);
    const win = getCurrentWindow();
    await win.setIgnoreCursorEvents(true);
    await win.hide();
    // Shrink back so the next show() doesn't get a "remembered" big rect.
    await win.setSize(new PhysicalSize(1, 1));
    void logBackend("info", "overlay hidden");
  }

  async function sendFeedback(value: FeedbackValue) {
    if (!result?.session_dir) return;
    setFeedback(value);
    try {
      await recordFeedback(result.session_dir, value);
      void logBackend("info", `feedback recorded: ${value}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      void logBackend("warn", `feedback failed: ${msg}`);
      // Keep the visual selection even if the write failed; the user
      // already pressed it and re-pressing is fine.
    }
  }

  if (!result) return null;

  const c = result.coordinates;
  return (
    <div className="overlay-root" onClick={close}>
      {c && (
        <div
          className="overlay-box"
          style={{ left: c[0], top: c[1], width: c[2], height: c[3] }}
        />
      )}
      <div className="overlay-bubble" onClick={(e) => e.stopPropagation()}>
        {result.next_action && (
          <p className="bubble-action">{result.next_action}</p>
        )}
        {result.reasoning && (
          <p className="bubble-reason">{result.reasoning}</p>
        )}
        {!result.next_action && !result.reasoning && (
          <p className="bubble-raw">{result.raw}</p>
        )}
        {result.session_dir && (
          <div className="bubble-feedback">
            <button
              type="button"
              className={feedback === "up" ? "selected" : ""}
              onClick={() => sendFeedback("up")}
              aria-label="좋아요"
            >
              ⬆
            </button>
            <button
              type="button"
              className={feedback === "down" ? "selected" : ""}
              onClick={() => sendFeedback("down")}
              aria-label="별로"
            >
              ⬇
            </button>
          </div>
        )}
        <p className="bubble-hint">클릭 또는 ESC로 닫기</p>
      </div>
    </div>
  );
}
