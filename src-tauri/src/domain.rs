use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Activity {
    pub id: String,
    pub name: String,
    pub color: String,
    pub icon: Option<String>,
    pub category: Option<String>,
    pub is_archived: bool,
    pub created_at_utc: i64,
    pub updated_at_utc: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityInput {
    pub name: String,
    pub color: Option<String>,
    pub icon: Option<String>,
    pub category: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityListOptions {
    pub include_archived: Option<bool>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TimeEntry {
    pub id: String,
    pub activity_id: Option<String>,
    pub activity_name: Option<String>,
    pub activity_color: Option<String>,
    pub started_at_utc: i64,
    pub ended_at_utc: Option<i64>,
    pub status: String,
    pub source: String,
    pub note: Option<String>,
    pub paused_seconds: i64,
    pub focus_seconds: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TimerState {
    pub entry: Option<TimeEntry>,
    pub break_entry: Option<BreakEntry>,
    pub next_break_at_utc: Option<i64>,
    pub break_due: bool,
    pub focus_minutes: i64,
    pub break_minutes: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BreakEntry {
    pub id: String,
    pub started_at_utc: i64,
    pub ended_at_utc: Option<i64>,
    pub trigger: String,
    pub status: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodaySummary {
    pub focus_seconds: i64,
    pub break_seconds: i64,
    pub entry_count: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub timezone: String,
    pub focus_minutes: i64,
    pub break_minutes: i64,
    pub reminders_enabled: bool,
    pub do_not_disturb_start: Option<String>,
    pub do_not_disturb_end: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsInput {
    pub timezone: Option<String>,
    pub focus_minutes: Option<i64>,
    pub break_minutes: Option<i64>,
    pub reminders_enabled: Option<bool>,
    pub do_not_disturb_start: Option<Option<String>>,
    pub do_not_disturb_end: Option<Option<String>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EntryInput {
    pub id: Option<String>,
    pub activity_id: Option<String>,
    pub started_at_utc: i64,
    pub ended_at_utc: i64,
    pub note: Option<String>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct RangeInput {
    pub start_at_utc: i64,
    pub end_at_utc: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityBreakdown {
    pub activity_id: Option<String>,
    pub name: String,
    pub color: String,
    pub focus_seconds: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DayTotal {
    pub date: String,
    pub focus_seconds: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AnalyticsSummary {
    pub total_focus_seconds: i64,
    pub total_break_seconds: i64,
    pub daily: Vec<DayTotal>,
    pub primary_active_hour: Option<u8>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HourTotal {
    pub hour: u8,
    pub focus_seconds: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportResult {
    pub path: String,
    pub format: String,
}
