import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { AnalysisResult, logBackend } from "../lib/ipc";

const OVERLAY_SHOW_EVENT = "screenbridge://overlay/show";

export default function Overlay() {
  const [result, setResult] = useState<AnalysisResult | null>(null);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    const win = getCurrentWindow();
    // Default state: window passes clicks through so users can keep working.
    void win.setIgnoreCursorEvents(true);
    listen<AnalysisResult>(OVERLAY_SHOW_EVENT, async (event) => {
      setResult(event.payload);
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
    const win = getCurrentWindow();
    await win.setIgnoreCursorEvents(true);
    await win.hide();
    void logBackend("info", "overlay hidden");
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
        <p className="bubble-hint">클릭 또는 ESC로 닫기</p>
      </div>
    </div>
  );
}
