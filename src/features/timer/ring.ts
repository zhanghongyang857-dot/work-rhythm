export const FOCUS_DURATION_SECONDS = 50 * 60;
export const BREAK_DURATION_SECONDS = 5 * 60;

export function ringProgress(
  remainingSeconds: number,
  durationSeconds: number,
): number {
  if (durationSeconds <= 0) return 0;
  return Math.max(0, Math.min(1, 1 - remainingSeconds / durationSeconds));
}

export function formatDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;

  if (hours > 0)
    return `${hours}:${String(minutes).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`;
  return `${minutes}:${String(remainder).padStart(2, "0")}`;
}
