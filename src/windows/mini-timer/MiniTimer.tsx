import { listen } from "@tauri-apps/api/event";
import { useEffect, useState } from "react";
import { WindowControls } from "../../components/ui/WindowControls";
import {
  FOCUS_DURATION_SECONDS,
  ringProgress,
} from "../../features/timer/ring";
import {
  native,
  type Activity,
  type TimerState,
} from "../../lib/native-client/api";
import { formatDuration } from "../../lib/time";
import { ProgressRing } from "./ProgressRing";

export function MiniTimer() {
  const [now, setNow] = useState(() => Date.now());
  const [timer, setTimer] = useState<TimerState>();
  const [activities, setActivities] = useState<Activity[]>([]);
  const [error, setError] = useState("");

  const refresh = async () => {
    try {
      const [nextTimer, nextActivities] = await Promise.all([
        native.timer.current(),
        native.activities.list(),
      ]);
      setTimer(nextTimer);
      setActivities(nextActivities);
      setError("");
    } catch (reason) {
      setError(String(reason));
    }
  };

  useEffect(() => {
    const interval = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(interval);
  }, []);
  useEffect(() => {
    void refresh();
    let timerDispose: (() => void) | undefined;
    let activityDispose: (() => void) | undefined;
    void listen("timer:changed", refresh).then((dispose) => {
      timerDispose = dispose;
    });
    void listen("activity:changed", refresh).then((dispose) => {
      activityDispose = dispose;
    });
    return () => {
      timerDispose?.();
      activityDispose?.();
    };
  }, []);

  const entry = timer?.entry;
  const elapsed = entry
    ? entry.focusSeconds +
      (entry.status === "running"
        ? Math.max(
            0,
            Math.floor((now - entry.startedAtUtc) / 1000) -
              entry.pausedSeconds -
              entry.focusSeconds,
          )
        : 0)
    : 0;
  const isPaused = entry?.status === "paused";
  const isBreaking = Boolean(timer?.breakEntry);
  const breakDue = Boolean(
    timer?.breakDue ||
    (!isBreaking && timer?.nextBreakAtUtc && timer.nextBreakAtUtc <= now),
  );
  const remaining = isBreaking
    ? Math.max(
        0,
        (timer?.breakMinutes ?? 5) * 60 -
          Math.floor((now - (timer?.breakEntry?.startedAtUtc ?? now)) / 1000),
      )
    : Math.max(0, Math.ceil(((timer?.nextBreakAtUtc ?? now) - now) / 1000));
  const ringDuration = (isBreaking ? timer?.breakMinutes : timer?.focusMinutes)
    ? (isBreaking ? timer!.breakMinutes : timer!.focusMinutes) * 60
    : FOCUS_DURATION_SECONDS;
  const act = async (operation: () => Promise<TimerState>) => {
    try {
      setTimer(await operation());
      setError("");
    } catch (reason) {
      setError(String(reason));
    }
  };

  return (
    <main className="mini-timer-shell">
      <header className="mini-titlebar" data-tauri-drag-region>
        <span data-tauri-drag-region>WORK RHYTHM</span>
        <WindowControls />
      </header>
      <div className="rings">
        <ProgressRing
          accent="focus"
          label="今天已学习"
          value={formatDuration(elapsed)}
          detail={entry?.activityName ?? "选择活动后开始"}
          progress={ringProgress(
            elapsed,
            Math.max(FOCUS_DURATION_SECONDS, elapsed || 1),
          )}
        />
        <ProgressRing
          accent="break"
          label={isBreaking ? "正在休息" : "距离下次休息"}
          value={formatDuration(remaining)}
          detail={`${timer?.breakMinutes ?? 5} 分钟休息`}
          progress={ringProgress(remaining, ringDuration)}
        />
      </div>
      <div className="mini-actions">
        {entry ? (
          <button
            onClick={() =>
              void act(() =>
                isPaused ? native.timer.resume() : native.timer.pause(),
              )
            }
          >
            {isPaused ? "继续" : "暂停"}
          </button>
        ) : null}
        {isBreaking ? (
          <button onClick={() => void act(native.breaks.complete)}>
            结束休息
          </button>
        ) : null}
        {entry ? (
          <button
            className="quiet"
            onClick={() => void act(() => native.timer.stop())}
          >
            结束
          </button>
        ) : null}
        {!entry ? (
          <select
            aria-label="选择活动开始"
            defaultValue=""
            onChange={(event) =>
              event.target.value &&
              void act(() => native.timer.start(event.target.value))
            }
          >
            <option value="" disabled>
              开始活动…
            </option>
            {activities.map((activity) => (
              <option key={activity.id} value={activity.id}>
                {activity.name}
              </option>
            ))}
          </select>
        ) : null}
      </div>
      {breakDue ? (
        <div className="break-due">
          <strong>该休息一下了</strong>
          <button onClick={() => void act(native.breaks.start)}>
            开始休息
          </button>
          <button onClick={() => void act(() => native.breaks.defer(10))}>
            延后 10 分钟
          </button>
          <button onClick={() => void act(native.breaks.skip)}>跳过</button>
        </div>
      ) : null}
      <p className="mini-status">
        <span />
        {error
          ? "操作未完成"
          : entry
            ? isPaused
              ? "计时已暂停"
              : "正在专注"
            : "准备就绪"}
      </p>
    </main>
  );
}
