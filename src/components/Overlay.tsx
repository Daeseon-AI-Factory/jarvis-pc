import { CSSProperties, useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import {
  PhysicalPosition,
  PhysicalSize,
  currentMonitor,
  getCurrentWindow,
} from "@tauri-apps/api/window";
import { AnalysisResult, logBackend } from "../lib/ipc";

const OVERLAY_SHOW_EVENT = "sb-overlay-show";

interface MonitorInfo {
  dpr: number;
  logicalW: number;
  logicalH: number;
}

export default function Overlay() {
  const [result, setResult] = useState<AnalysisResult | null>(null);
  const [monitor, setMonitor] = useState<MonitorInfo | null>(null);

  useEffect(() => {
    let unlistenShow: (() => void) | undefined;
    let unlistenHide: (() => void) | undefined;
    const win = getCurrentWindow();
    // The whole point of the overlay is to be a HUD: clicks must always pass
    // through to whatever real app is underneath. We never flip this back to
    // false — closing is keyboard-only (⌥+Space toggles).
    void win.setIgnoreCursorEvents(true);
    listen<AnalysisResult>(OVERLAY_SHOW_EVENT, async (event) => {
      const payload = event.payload;
      setResult(payload);
      // capture한 monitor의 전역 위치 우선 사용 (multi-monitor 환경).
      // 없으면 overlay window의 currentMonitor() fallback (single monitor OK).
      const rect = payload.monitor_rect;
      const fallback = await currentMonitor();
      const targetX = rect ? rect[0] : fallback?.position.x ?? 0;
      const targetY = rect ? rect[1] : fallback?.position.y ?? 0;
      const targetW = rect ? rect[2] : fallback?.size.width ?? 1920;
      const targetH = rect ? rect[3] : fallback?.size.height ?? 1080;
      await win.setPosition(new PhysicalPosition(targetX, targetY));
      await win.setSize(new PhysicalSize(targetW, targetH));
      // DPR은 monitor 이동 후 다시 조회. overlay window가 새 monitor에 있을 때
      // 그 monitor의 scaleFactor 사용.
      const mon = await currentMonitor();
      const dpr = mon?.scaleFactor ?? 1;
      setMonitor({
        dpr,
        logicalW: targetW / dpr,
        logicalH: targetH / dpr,
      });
      await win.show();
      // Do NOT setFocus — focus would steal keyboard from the real app
      // beneath. The overlay is a heads-up display, not a focused window.
      void logBackend(
        "info",
        `overlay shown: monitor=(${targetX},${targetY},${targetW},${targetH}) dpr=${dpr}`
      );
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

  // physical-px 좌표를 CSS logical px로 변환. monitor 정보 없으면 1배.
  const dpr = monitor?.dpr ?? 1;
  const c = result.coordinates
    ? {
        left: result.coordinates[0] / dpr,
        top: result.coordinates[1] / dpr,
        width: result.coordinates[2] / dpr,
        height: result.coordinates[3] / dpr,
      }
    : null;

  // Bubble 위치 계산:
  //   - 박스 있으면 그 옆에 (오른쪽 비면 오른쪽, 아니면 왼쪽). 위 비면 위.
  //   - 박스 없으면 화면 중앙.
  const BUBBLE_W = 360;
  const BUBBLE_H_EST = 140;
  const GAP = 16;
  let bubbleStyle: CSSProperties = {
    top: "50%",
    left: "50%",
    transform: "translate(-50%, -50%)",
  };
  if (c && monitor) {
    const spaceRight = monitor.logicalW - (c.left + c.width);
    const spaceLeft = c.left;
    const spaceBelow = monitor.logicalH - (c.top + c.height);
    let style: CSSProperties = {};
    if (spaceRight >= BUBBLE_W + GAP) {
      style = { left: c.left + c.width + GAP, top: c.top };
    } else if (spaceLeft >= BUBBLE_W + GAP) {
      style = { left: c.left - BUBBLE_W - GAP, top: c.top };
    } else if (spaceBelow >= BUBBLE_H_EST + GAP) {
      style = { left: c.left, top: c.top + c.height + GAP };
    } else {
      style = { left: c.left, top: c.top - BUBBLE_H_EST - GAP };
    }
    bubbleStyle = { ...style, width: BUBBLE_W };
  }

  return (
    <div className="overlay-root">
      {c && (
        <div
          className="overlay-box"
          style={{
            left: c.left,
            top: c.top,
            width: c.width,
            height: c.height,
          }}
        />
      )}
      <div className="overlay-bubble" style={bubbleStyle}>
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
