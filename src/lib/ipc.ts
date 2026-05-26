import { invoke } from "@tauri-apps/api/core";

export type LogLevel = "info" | "warn" | "error";

export async function logBackend(level: LogLevel, msg: string): Promise<void> {
  try {
    await invoke("log_event", { level, msg });
  } catch (err) {
    console.error("[ipc.logBackend] failed:", err);
  }
}

export interface AnalysisResult {
  screen_state: string | null;
  next_action: string | null;
  coordinates: [number, number, number, number] | null;
  reasoning: string | null;
  raw: string;
}

export async function invokeAnalyze(instruction: string): Promise<AnalysisResult> {
  return invoke<AnalysisResult>("analyze", { instruction });
}
