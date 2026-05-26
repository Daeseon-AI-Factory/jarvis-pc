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
  session_dir: string | null;
}

export async function invokeAnalyze(instruction: string): Promise<AnalysisResult> {
  return invoke<AnalysisResult>("analyze", { instruction });
}

export type FeedbackValue = "up" | "down";

export async function recordFeedback(
  sessionDir: string,
  value: FeedbackValue
): Promise<void> {
  await invoke("record_feedback", { sessionDir, value });
}
