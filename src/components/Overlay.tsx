import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import {
  PhysicalPosition,
  PhysicalSize,
  currentMonitor,
  getCurrentWindow,
} from "@tauri-apps/api/window";
import { AnalysisResult, logBackend } from "../lib/ipc";

const OVERLAY_SHOW_EVENT = "sb-overlay-show";

export default function Overlay() {
  const [result, setResult] = useState<AnalysisResult | null>(null);

  useEffect(() => {
    let unlistenShow: (() => void) | undefined;
    let unlistenHide: (() => void) | undefined;
    const win = getCurrentWindow();
    // The whole point of the overlay is to be a HUD: clicks must always pass
    // through to whatever real app is underneath. We never flip this back to
    // false — closing is keyboard-only (⌥+Space toggles).
    void win.setIgnoreCursorEvents(true);
    listen<AnalysisResult>(OVERLAY_SHOW_EVENT, async (event) => {
      setResult(event.payload);
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
      // Do NOT setFocus — focus would steal keyboard from the real app
      // beneath. The overlay is a heads-up display, not a focused window.
      void logBackend("info", "overlay shown (HUD mode, click-through)");
    }).then((fn) => {
      unlistenShow = fn;
    });
    // ⌥+Space (TRIGGER_EVENT)을 overlay 활성 중에 누르면 toggle off.
    // backend가 emit하는 그 채널은 trigger panel도 listen하지만, overlay에선
    // 자기 자신을 닫는 의미로 해석한다.
    listen("sb-trigger", async () => {
      void logBackend("info", "overlay received trigger → close");
      await close();
    }).then((fn) => {
      unlistenHide = fn;
    });
    return () => {
      unlistenShow?.();
      unlistenHide?.();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ESC keydown은 click-through 모드에선 window가 focus 못 잡아 도달 X.
  // 닫기는 backend의 ⌥+Space 단축키가 broadcast하는 sb-trigger 이벤트로
  // 위 listen 핸들러가 처리.

  async function close() {
    setResult(null);
    const win = getCurrentWindow();
    await win.hide();
    // Shrink back so the next show() doesn't get a "remembered" big rect.
    await win.setSize(new PhysicalSize(1, 1));
    void logBackend("info", "overlay hidden");
  }

  // Feedback 👍/👎 버튼은 click-through 모드에선 마우스로 못 누름.
  // session_dir은 그대로 result에 남아있으므로 v0.2에서 별도 micro-window
  // (always-on-top, 클릭 받기)로 옮기면 활성화 가능. recordFeedback IPC는
  // ipc.ts에 그대로 살아있음.

  if (!result) return null;

  const c = result.coordinates;
  // 전체가 click-through. onClick 핸들러 없음. bubble의 ⬆/⬇ 버튼도 클릭
  // 통과되어 동작 안 함 — v0.2에서 별도 micro-window로 옮길 후보.
  return (
    <div className="overlay-root">
      {c && (
        <div
          className="overlay-box"
          style={{ left: c[0], top: c[1], width: c[2], height: c[3] }}
        />
      )}
      <div className="overlay-bubble">
        {result.next_action && (
          <p className="bubble-action">{result.next_action}</p>
        )}
        {result.reasoning && (
          <p className="bubble-reason">{result.reasoning}</p>
        )}
        {!result.next_action && !result.reasoning && (
          <p className="bubble-raw">{result.raw}</p>
        )}
        <p className="bubble-hint">⌥ Space 다시 누르면 닫힘</p>
      </div>
    </div>
  );
}
