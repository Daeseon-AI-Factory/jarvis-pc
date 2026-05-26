import { FormEvent, useEffect, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { listen } from "@tauri-apps/api/event";
import { logBackend } from "../lib/ipc";

const TRIGGER_EVENT = "screenbridge://trigger";

export default function TriggerPanel() {
  const [instruction, setInstruction] = useState("");
  const [status, setStatus] = useState<"idle" | "loading" | "error">("idle");
  const [error, setError] = useState<string | null>(null);
  const inputRef = useRef<HTMLTextAreaElement | null>(null);

  // Listen for hotkey / tray trigger events. Show + focus the window and
  // move the cursor into the textarea so the user can paste immediately.
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    listen(TRIGGER_EVENT, async () => {
      const win = getCurrentWindow();
      await win.show();
      await win.setFocus();
      requestAnimationFrame(() => inputRef.current?.focus());
      void logBackend("info", "trigger panel shown");
    }).then((fn) => {
      unlisten = fn;
    });
    return () => {
      unlisten?.();
    };
  }, []);

  // ESC closes the panel (just hide — the global shortcut re-opens it).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        void cancel();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function analyze(e?: FormEvent) {
    e?.preventDefault();
    if (!instruction.trim() || status === "loading") return;
    setStatus("loading");
    setError(null);
    void logBackend("info", `analyze submit: ${instruction.length} chars`);
    // Phase 4.2 wires the actual analyze IPC. For now, keep the loading
    // state visible briefly so the UI shape can be inspected.
    setTimeout(() => {
      setStatus("idle");
    }, 600);
  }

  async function cancel() {
    setInstruction("");
    setStatus("idle");
    setError(null);
    await getCurrentWindow().hide();
    void logBackend("info", "trigger panel hidden");
  }

  return (
    <main className="trigger-panel">
      <form onSubmit={analyze}>
        <label htmlFor="instruction">AI가 뭐라 했나?</label>
        <textarea
          id="instruction"
          ref={inputRef}
          value={instruction}
          onChange={(e) => setInstruction(e.target.value)}
          placeholder="여기에 AI 지시를 붙여넣으세요..."
          rows={6}
          disabled={status === "loading"}
        />
        {error && <p className="error">{error}</p>}
        <div className="actions">
          <button type="button" onClick={cancel} disabled={status === "loading"}>
            Cancel
          </button>
          <button type="submit" disabled={!instruction.trim() || status === "loading"}>
            {status === "loading" ? "Analyzing…" : "Analyze"}
          </button>
        </div>
      </form>
    </main>
  );
}
