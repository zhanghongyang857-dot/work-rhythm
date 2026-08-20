import { invoke } from "@tauri-apps/api/core";

export type Activity = {
  id: string;
  name: string;
  color: string;
  icon?: string;
  category?: string;
  isArchived: boolean;
};
export type ActivityInput = {
  name: string;
  color?: string;
  icon?: string;
  category?: string;
};
export type TimeEntry = {
  id: string;
  activityId?: string;
  activityName?: string;
  activityColor?: string;
  startedAtUtc: number;
  endedAtUtc?: number;
  status: "running" | "paused" | "completed";
  source: string;
  note?: string;
  pausedSeconds: number;
  focusSeconds: number;
};
export type BreakEntry = {
  id: string;
  startedAtUtc: number;
  endedAtUtc?: number;
  trigger: string;
  status: string;
};
export type TimerState = {
  entry?: TimeEntry;
  breakEntry?: BreakEntry;
  nextBreakAtUtc?: number;
  breakDue: boolean;
  focusMinutes: number;
  breakMinutes: number;
};
export type TodaySummary = {
  focusSeconds: number;
  breakSeconds: number;
  entryCount: number;
};
export type Settings = {
  timezone: string;
  focusMinutes: number;
  breakMinutes: number;
  remindersEnabled: boolean;
  doNotDisturbStart?: string;
  doNotDisturbEnd?: string;
};
export type Range = { startAtUtc: number; endAtUtc: number };
export type AnalyticsSummary = {
  totalFocusSeconds: number;
  totalBreakSeconds: number;
  daily: { date: string; focusSeconds: number }[];
  primaryActiveHour?: number;
};
export type Breakdown = {
  activityId?: string;
  name: string;
  color: string;
  focusSeconds: number;
};
export type HourTotal = { hour: number; focusSeconds: number };
export type ExportResult = { path: string; format: string };

export const native = {
  timer: {
    current: () => invoke<TimerState>("timer_get_current"),
    start: (activityId: string) =>
      invoke<TimerState>("timer_start", { activityId }),
    pause: () => invoke<TimerState>("timer_pause"),
    resume: () => invoke<TimerState>("timer_resume"),
    stop: (note?: string) => invoke<TimerState>("timer_stop", { note }),
    switchActivity: (activityId: string) =>
      invoke<TimerState>("timer_switch_activity", { activityId }),
    today: () => invoke<TodaySummary>("timer_get_today_summary"),
  },
  activities: {
    list: (includeArchived = false) =>
      invoke<Activity[]>("activities_list", { options: { includeArchived } }),
    create: (input: ActivityInput) =>
      invoke<Activity>("activities_create", { input }),
    update: (id: string, input: ActivityInput) =>
      invoke<Activity>("activities_update", { id, input }),
    archive: (id: string) => invoke<void>("activities_archive", { id }),
  },
  entries: {
    list: (range: Range) => invoke<TimeEntry[]>("entries_list", { range }),
    upsert: (input: {
      id?: string;
      activityId?: string;
      startedAtUtc: number;
      endedAtUtc: number;
      note?: string;
    }) => invoke<TimeEntry>("entries_upsert", { input }),
    delete: (id: string) => invoke<void>("entries_delete", { id }),
  },
  breaks: {
    start: () => invoke<TimerState>("breaks_start"),
    complete: () => invoke<TimerState>("breaks_complete"),
    defer: (minutes: number) => invoke<TimerState>("breaks_defer", { minutes }),
    skip: () => invoke<TimerState>("breaks_skip"),
  },
  analytics: {
    summary: (range: Range) =>
      invoke<AnalyticsSummary>("analytics_get_summary", { range }),
    breakdown: (range: Range) =>
      invoke<Breakdown[]>("analytics_get_breakdown", { range }),
    hourly: (range: Range) =>
      invoke<HourTotal[]>("analytics_get_hourly_activity", { range }),
  },
  settings: {
    get: () => invoke<Settings>("settings_get"),
    update: (input: Partial<Settings>) =>
      invoke<Settings>("settings_update", { input }),
  },
  data: {
    export: (format: "json" | "csv", range: Range) =>
      invoke<ExportResult>("data_export", { format, range }),
    backup: () => invoke<ExportResult>("data_backup"),
  },
};
