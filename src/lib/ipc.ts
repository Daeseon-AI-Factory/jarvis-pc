import { invoke } from "@tauri-apps/api/core";

export type LogLevel = "info" | "warn" | "error";

export async function logBackend(level: LogLevel, msg: string): Promise<void> {
  try {
    await invoke("log_event", { level, msg });
  } catch (err) {
    console.error("[ipc.logBackend] failed:", err);
  }
}
