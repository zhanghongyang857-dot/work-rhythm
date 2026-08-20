use std::{collections::BTreeMap, fs, path::PathBuf};

use chrono::{TimeZone, Timelike, Utc};
use chrono_tz::Tz;
use rusqlite::{params, Connection, OptionalExtension};
use uuid::Uuid;

use crate::domain::{
    Activity, ActivityBreakdown, ActivityInput, AnalyticsSummary, BreakEntry, DayTotal, EntryInput,
    HourTotal, RangeInput, Settings, SettingsInput, TimeEntry, TimerState, TodaySummary,
};

pub const DEFAULT_COLOR: &str = "#716DE8";

pub fn now() -> i64 {
    Utc::now().timestamp_millis()
}

fn database_error(error: rusqlite::Error) -> String {
    format!("数据库操作失败：{error}")
}

fn validate_name(name: &str) -> Result<String, String> {
    let trimmed = name.trim();
    if trimmed.is_empty() || trimmed.chars().count() > 80 {
        return Err("活动名称需为 1 至 80 个字符".into());
    }
    Ok(trimmed.to_owned())
}

pub fn activities_list(conn: &Connection, include_archived: bool) -> Result<Vec<Activity>, String> {
    let mut statement = conn
        .prepare(
            "SELECT id, name, color, icon, category, is_archived, created_at_utc, updated_at_utc
             FROM activities WHERE (?1 = 1 OR is_archived = 0)
             ORDER BY is_archived, updated_at_utc DESC",
        )
        .map_err(database_error)?;
    let results = statement
        .query_map([include_archived as i64], |row| {
            Ok(Activity {
                id: row.get(0)?,
                name: row.get(1)?,
                color: row.get(2)?,
                icon: row.get(3)?,
                category: row.get(4)?,
                is_archived: row.get::<_, i64>(5)? != 0,
                created_at_utc: row.get(6)?,
                updated_at_utc: row.get(7)?,
            })
        })
        .map_err(database_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(database_error)?;
    Ok(results)
}

pub fn activities_create(conn: &mut Connection, input: ActivityInput) -> Result<Activity, String> {
    let name = validate_name(&input.name)?;
    let id = Uuid::new_v4().to_string();
    let timestamp = now();
    let color = input.color.unwrap_or_else(|| DEFAULT_COLOR.into());
    conn.execute(
        "INSERT INTO activities (id, name, color, icon, category, is_archived, created_at_utc, updated_at_utc)
         VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6, ?6)",
        params![id, name, color, input.icon, input.category, timestamp],
    )
    .map_err(database_error)?;
    activity_by_id(conn, &id)
}

pub fn activities_update(
    conn: &mut Connection,
    id: &str,
    input: ActivityInput,
) -> Result<Activity, String> {
    let name = validate_name(&input.name)?;
    let existing = activity_by_id(conn, id)?;
    let timestamp = now();
    conn.execute(
        "UPDATE activities SET name = ?2, color = ?3, icon = ?4, category = ?5, updated_at_utc = ?6 WHERE id = ?1",
        params![id, name, input.color.unwrap_or(existing.color), input.icon, input.category, timestamp],
    )
    .map_err(database_error)?;
    activity_by_id(conn, id)
}

pub fn activities_archive(conn: &mut Connection, id: &str) -> Result<(), String> {
    let changed = conn
        .execute(
            "UPDATE activities SET is_archived = 1, updated_at_utc = ?2 WHERE id = ?1",
            params![id, now()],
        )
        .map_err(database_error)?;
    if changed == 0 {
        return Err("找不到该活动".into());
    }
    Ok(())
}

fn activity_by_id(conn: &Connection, id: &str) -> Result<Activity, String> {
    conn.query_row(
        "SELECT id, name, color, icon, category, is_archived, created_at_utc, updated_at_utc FROM activities WHERE id = ?1",
        [id],
        |row| {
            Ok(Activity {
                id: row.get(0)?, name: row.get(1)?, color: row.get(2)?, icon: row.get(3)?, category: row.get(4)?,
                is_archived: row.get::<_, i64>(5)? != 0, created_at_utc: row.get(6)?, updated_at_utc: row.get(7)?,
            })
        },
    ).optional().map_err(database_error)?.ok_or_else(|| "找不到该活动".into())
}

pub fn timer_get_current(conn: &Connection) -> Result<TimerState, String> {
    let timestamp = now();
    let entry = current_entry(conn, timestamp)?;
    let break_entry = current_break(conn)?;
    let settings = settings_get(conn)?;
    let next_break_at_utc = setting_i64(conn, "reminder_next_at_utc")?;
    let break_due = entry.as_ref().is_some_and(|item| item.status == "running")
        && settings.reminders_enabled
        && next_break_at_utc.is_some_and(|due| due <= timestamp)
        && break_entry.is_none()
        && !is_do_not_disturb(&settings);
    Ok(TimerState {
        entry,
        break_entry,
        next_break_at_utc,
        break_due,
        focus_minutes: settings.focus_minutes,
        break_minutes: settings.break_minutes,
    })
}

pub fn reminder_wait_ms(conn: &Connection) -> Result<Option<u64>, String> {
    let state = timer_get_current(conn)?;
    if state
        .entry
        .as_ref()
        .is_none_or(|entry| entry.status != "running")
        || state.break_entry.is_some()
        || !settings_get(conn)?.reminders_enabled
    {
        return Ok(None);
    }
    let due = state
        .next_break_at_utc
        .ok_or_else(|| "缺少下一次提醒时间".to_string())?;
    Ok(Some((due - now()).max(0) as u64))
}

pub fn timer_start(conn: &mut Connection, activity_id: &str) -> Result<TimerState, String> {
    if current_entry(conn, now())?.is_some() {
        return Err("已有未结束的计时记录".into());
    }
    let activity = activity_by_id(conn, activity_id)?;
    if activity.is_archived {
        return Err("不能开始已归档的活动".into());
    }
    let timestamp = now();
    let tx = conn.transaction().map_err(database_error)?;
    tx.execute(
        "INSERT INTO time_entries (id, activity_id, started_at_utc, status, source) VALUES (?1, ?2, ?3, 'running', 'timer')",
        params![Uuid::new_v4().to_string(), activity_id, timestamp],
    ).map_err(database_error)?;
    set_setting_tx(
        &tx,
        "reminder_next_at_utc",
        Some(timestamp + settings_get_tx(&tx)?.focus_minutes * 60_000),
    )?;
    tx.commit().map_err(database_error)?;
    timer_get_current(conn)
}

pub fn timer_pause(conn: &mut Connection) -> Result<TimerState, String> {
    let timestamp = now();
    let entry = current_entry(conn, timestamp)?.ok_or_else(|| "没有正在计时的活动".to_string())?;
    if entry.status != "running" {
        return Err("当前计时不处于运行状态".into());
    }
    let tx = conn.transaction().map_err(database_error)?;
    tx.execute(
        "UPDATE time_entries SET status = 'paused' WHERE id = ?1",
        [&entry.id],
    )
    .map_err(database_error)?;
    tx.execute(
        "INSERT INTO entry_pauses (id, time_entry_id, started_at_utc) VALUES (?1, ?2, ?3)",
        params![Uuid::new_v4().to_string(), entry.id, timestamp],
    )
    .map_err(database_error)?;
    tx.commit().map_err(database_error)?;
    timer_get_current(conn)
}

pub fn timer_resume(conn: &mut Connection) -> Result<TimerState, String> {
    let timestamp = now();
    let entry =
        current_entry(conn, timestamp)?.ok_or_else(|| "没有可继续的计时记录".to_string())?;
    if entry.status != "paused" {
        return Err("当前计时不处于暂停状态".into());
    }
    let tx = conn.transaction().map_err(database_error)?;
    let pause_started: i64 = tx.query_row("SELECT started_at_utc FROM entry_pauses WHERE time_entry_id = ?1 AND ended_at_utc IS NULL", [&entry.id], |row| row.get(0)).map_err(database_error)?;
    tx.execute("UPDATE entry_pauses SET ended_at_utc = ?2 WHERE time_entry_id = ?1 AND ended_at_utc IS NULL", params![entry.id, timestamp]).map_err(database_error)?;
    tx.execute(
        "UPDATE time_entries SET status = 'running' WHERE id = ?1",
        [&entry.id],
    )
    .map_err(database_error)?;
    if let Some(next) = setting_i64_tx(&tx, "reminder_next_at_utc")? {
        set_setting_tx(
            &tx,
            "reminder_next_at_utc",
            Some(next + timestamp - pause_started),
        )?;
    }
    tx.commit().map_err(database_error)?;
    timer_get_current(conn)
}

pub fn timer_stop(conn: &mut Connection, note: Option<String>) -> Result<TimerState, String> {
    let timestamp = now();
    let entry =
        current_entry(conn, timestamp)?.ok_or_else(|| "没有未结束的计时记录".to_string())?;
    let tx = conn.transaction().map_err(database_error)?;
    close_entry_tx(&tx, &entry.id, timestamp, note)?;
    set_setting_tx::<i64>(&tx, "reminder_next_at_utc", None)?;
    tx.commit().map_err(database_error)?;
    timer_get_current(conn)
}

pub fn timer_switch(conn: &mut Connection, activity_id: &str) -> Result<TimerState, String> {
    let target = activity_by_id(conn, activity_id)?;
    if target.is_archived {
        return Err("不能开始已归档的活动".into());
    }
    let timestamp = now();
    let active =
        current_entry(conn, timestamp)?.ok_or_else(|| "没有未结束的计时记录".to_string())?;
    if active.activity_id.as_deref() == Some(activity_id) {
        return timer_get_current(conn);
    }
    let tx = conn.transaction().map_err(database_error)?;
    close_entry_tx(&tx, &active.id, timestamp, None)?;
    tx.execute("INSERT INTO time_entries (id, activity_id, started_at_utc, status, source) VALUES (?1, ?2, ?3, 'running', 'timer')", params![Uuid::new_v4().to_string(), activity_id, timestamp]).map_err(database_error)?;
    tx.commit().map_err(database_error)?;
    timer_get_current(conn)
}

fn close_entry_tx(
    tx: &rusqlite::Transaction<'_>,
    id: &str,
    timestamp: i64,
    note: Option<String>,
) -> Result<(), String> {
    tx.execute("UPDATE entry_pauses SET ended_at_utc = ?2 WHERE time_entry_id = ?1 AND ended_at_utc IS NULL", params![id, timestamp]).map_err(database_error)?;
    tx.execute("UPDATE time_entries SET ended_at_utc = ?2, status = 'completed', note = COALESCE(?3, note) WHERE id = ?1", params![id, timestamp, note]).map_err(database_error)?;
    Ok(())
}

pub fn entries_list(conn: &Connection, range: RangeInput) -> Result<Vec<TimeEntry>, String> {
    load_entries(conn, range.start_at_utc, range.end_at_utc, now())
}

pub fn entries_upsert(conn: &mut Connection, input: EntryInput) -> Result<TimeEntry, String> {
    if input.ended_at_utc <= input.started_at_utc {
        return Err("结束时间必须晚于开始时间".into());
    }
    if let Some(activity_id) = &input.activity_id {
        activity_by_id(conn, activity_id)?;
    }
    let id = input.id.unwrap_or_else(|| Uuid::new_v4().to_string());
    conn.execute(
        "INSERT INTO time_entries (id, activity_id, started_at_utc, ended_at_utc, status, source, note)
         VALUES (?1, ?2, ?3, ?4, 'completed', 'manual', ?5)
         ON CONFLICT(id) DO UPDATE SET activity_id = excluded.activity_id, started_at_utc = excluded.started_at_utc,
           ended_at_utc = excluded.ended_at_utc, note = excluded.note, source = 'manual'",
        params![id, input.activity_id, input.started_at_utc, input.ended_at_utc, input.note],
    ).map_err(database_error)?;
    entry_by_id(conn, &id, now())
}

pub fn entries_delete(conn: &mut Connection, id: &str) -> Result<(), String> {
    let changed = conn
        .execute(
            "DELETE FROM time_entries WHERE id = ?1 AND ended_at_utc IS NOT NULL",
            [id],
        )
        .map_err(database_error)?;
    if changed == 0 {
        return Err("只能删除已结束的历史记录".into());
    }
    Ok(())
}

pub fn breaks_start(conn: &mut Connection) -> Result<TimerState, String> {
    if current_break(conn)?.is_some() {
        return Err("已有进行中的休息".into());
    }
    let timestamp = now();
    conn.execute("INSERT INTO break_entries (id, started_at_utc, trigger, status) VALUES (?1, ?2, 'manual', 'running')", params![Uuid::new_v4().to_string(), timestamp]).map_err(database_error)?;
    setting_i64_write(conn, "reminder_next_at_utc", None)?;
    timer_get_current(conn)
}

pub fn breaks_complete(conn: &mut Connection) -> Result<TimerState, String> {
    let current = current_break(conn)?.ok_or_else(|| "没有进行中的休息".to_string())?;
    let timestamp = now();
    let focus_minutes = settings_get(conn)?.focus_minutes;
    conn.execute(
        "UPDATE break_entries SET ended_at_utc = ?2, status = 'completed' WHERE id = ?1",
        params![current.id, timestamp],
    )
    .map_err(database_error)?;
    setting_i64_write(
        conn,
        "reminder_next_at_utc",
        Some(timestamp + focus_minutes * 60_000),
    )?;
    timer_get_current(conn)
}

pub fn breaks_defer(conn: &mut Connection, minutes: i64) -> Result<TimerState, String> {
    if !(1..=120).contains(&minutes) {
        return Err("延后时间需在 1 至 120 分钟之间".into());
    }
    setting_i64_write(conn, "reminder_next_at_utc", Some(now() + minutes * 60_000))?;
    timer_get_current(conn)
}

pub fn breaks_skip(conn: &mut Connection) -> Result<TimerState, String> {
    let timestamp = now();
    let focus_minutes = settings_get(conn)?.focus_minutes;
    conn.execute("INSERT INTO break_entries (id, started_at_utc, ended_at_utc, trigger, status) VALUES (?1, ?2, ?2, 'reminder', 'skipped')", params![Uuid::new_v4().to_string(), timestamp]).map_err(database_error)?;
    setting_i64_write(
        conn,
        "reminder_next_at_utc",
        Some(timestamp + focus_minutes * 60_000),
    )?;
    timer_get_current(conn)
}

pub fn settings_get(conn: &Connection) -> Result<Settings, String> {
    let timezone = setting_string(conn, "timezone")?.unwrap_or_else(|| "UTC".into());
    let (focus_minutes, break_minutes, reminders_enabled, dnd_start, dnd_end): (i64, i64, i64, Option<String>, Option<String>) = conn.query_row(
        "SELECT focus_minutes, break_minutes, is_enabled, do_not_disturb_start, do_not_disturb_end FROM reminder_rules WHERE id = 'global'",
        [], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
    ).map_err(database_error)?;
    Ok(Settings {
        timezone,
        focus_minutes,
        break_minutes,
        reminders_enabled: reminders_enabled != 0,
        do_not_disturb_start: dnd_start,
        do_not_disturb_end: dnd_end,
    })
}

pub fn settings_update(conn: &mut Connection, input: SettingsInput) -> Result<Settings, String> {
    let current = settings_get(conn)?;
    let timezone = input.timezone.unwrap_or(current.timezone);
    if timezone.parse::<Tz>().is_err() {
        return Err("请输入有效的 IANA 时区，例如 Asia/Singapore".into());
    }
    let focus = input.focus_minutes.unwrap_or(current.focus_minutes);
    let rest = input.break_minutes.unwrap_or(current.break_minutes);
    if !(1..=240).contains(&focus) || !(1..=120).contains(&rest) {
        return Err("专注时长需为 1–240 分钟，休息时长需为 1–120 分钟".into());
    }
    let tx = conn.transaction().map_err(database_error)?;
    set_setting_tx(&tx, "timezone", Some(timezone))?;
    tx.execute("UPDATE reminder_rules SET focus_minutes = ?1, break_minutes = ?2, is_enabled = ?3, do_not_disturb_start = ?4, do_not_disturb_end = ?5, updated_at_utc = ?6 WHERE id = 'global'", params![focus, rest, input.reminders_enabled.unwrap_or(current.reminders_enabled) as i64, input.do_not_disturb_start.unwrap_or(current.do_not_disturb_start), input.do_not_disturb_end.unwrap_or(current.do_not_disturb_end), now()]).map_err(database_error)?;
    tx.commit().map_err(database_error)?;
    settings_get(conn)
}

pub fn today_summary(conn: &Connection) -> Result<TodaySummary, String> {
    let tz = timezone(conn)?;
    let timestamp = now();
    let local_now = tz
        .timestamp_millis_opt(timestamp)
        .single()
        .ok_or_else(|| "无法读取当前时间".to_string())?;
    let start = local_midnight(local_now.date_naive(), tz)?;
    let focus_seconds = active_segments(conn, start, timestamp)?
        .iter()
        .map(|item| item.end - item.start)
        .sum::<i64>()
        / 1000;
    let break_seconds = break_seconds(conn, start, timestamp)? / 1000;
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM time_entries WHERE started_at_utc >= ?1 AND started_at_utc < ?2",
            params![start, timestamp],
            |row| row.get(0),
        )
        .map_err(database_error)?;
    Ok(TodaySummary {
        focus_seconds,
        break_seconds,
        entry_count: count,
    })
}

pub fn analytics_summary(conn: &Connection, range: RangeInput) -> Result<AnalyticsSummary, String> {
    validate_range(&range)?;
    let tz = timezone(conn)?;
    let segments = active_segments(conn, range.start_at_utc, range.end_at_utc)?;
    let mut days = BTreeMap::<String, i64>::new();
    let mut hours = [0_i64; 24];
    for segment in &segments {
        split_segment(segment.start, segment.end, tz, |at, until, local| {
            *days.entry(local.date_naive().to_string()).or_default() += until - at;
            hours[local.hour() as usize] += until - at;
        })?;
    }
    let primary_active_hour = hours
        .iter()
        .enumerate()
        .max_by_key(|(_, seconds)| *seconds)
        .and_then(|(hour, seconds)| (*seconds > 0).then_some(hour as u8));
    let daily = days
        .into_iter()
        .map(|(date, milliseconds)| DayTotal {
            date,
            focus_seconds: milliseconds / 1000,
        })
        .collect();
    Ok(AnalyticsSummary {
        total_focus_seconds: segments
            .iter()
            .map(|item| item.end - item.start)
            .sum::<i64>()
            / 1000,
        total_break_seconds: break_seconds(conn, range.start_at_utc, range.end_at_utc)? / 1000,
        daily,
        primary_active_hour,
    })
}

pub fn analytics_breakdown(
    conn: &Connection,
    range: RangeInput,
) -> Result<Vec<ActivityBreakdown>, String> {
    validate_range(&range)?;
    let mut totals = BTreeMap::<(Option<String>, String, String), i64>::new();
    for segment in active_segments(conn, range.start_at_utc, range.end_at_utc)? {
        *totals
            .entry((segment.activity_id, segment.name, segment.color))
            .or_default() += segment.end - segment.start;
    }
    Ok(totals
        .into_iter()
        .map(|((activity_id, name, color), ms)| ActivityBreakdown {
            activity_id,
            name,
            color,
            focus_seconds: ms / 1000,
        })
        .collect())
}

pub fn analytics_hourly(conn: &Connection, range: RangeInput) -> Result<Vec<HourTotal>, String> {
    validate_range(&range)?;
    let tz = timezone(conn)?;
    let mut hours = [0_i64; 24];
    for segment in active_segments(conn, range.start_at_utc, range.end_at_utc)? {
        split_segment(segment.start, segment.end, tz, |at, until, local| {
            hours[local.hour() as usize] += until - at
        })?;
    }
    Ok(hours
        .into_iter()
        .enumerate()
        .map(|(hour, ms)| HourTotal {
            hour: hour as u8,
            focus_seconds: ms / 1000,
        })
        .collect())
}

pub fn export_data(
    conn: &Connection,
    data_dir: &PathBuf,
    format: &str,
    range: RangeInput,
) -> Result<PathBuf, String> {
    validate_range(&range)?;
    let entries = entries_list(conn, range.clone())?;
    let extension = match format {
        "json" => "json",
        "csv" => "csv",
        _ => return Err("只支持 JSON 或 CSV 导出".into()),
    };
    let export_dir = data_dir.join("exports");
    fs::create_dir_all(&export_dir).map_err(|e| e.to_string())?;
    let path = export_dir.join(format!("work-rhythm-{}.{}", now(), extension));
    let content = if format == "json" {
        serde_json::to_string_pretty(&entries).map_err(|e| e.to_string())?
    } else {
        csv_rows(&entries)
    };
    fs::write(&path, content).map_err(|e| e.to_string())?;
    Ok(path)
}

pub fn backup_database(data_dir: &PathBuf) -> Result<PathBuf, String> {
    let source = data_dir.join("work-rhythm.sqlite3");
    let backup_dir = data_dir.join("backups");
    fs::create_dir_all(&backup_dir).map_err(|e| e.to_string())?;
    let target = backup_dir.join(format!("work-rhythm-{}.sqlite3", now()));
    fs::copy(source, &target).map_err(|e| e.to_string())?;
    Ok(target)
}

fn csv_rows(entries: &[TimeEntry]) -> String {
    let mut result = "id,activity,started_at_utc,ended_at_utc,focus_seconds,note\n".to_owned();
    for entry in entries {
        result.push_str(&format!(
            "\"{}\",\"{}\",{},{},{},\"{}\"\n",
            entry.id,
            entry
                .activity_name
                .clone()
                .unwrap_or_default()
                .replace('"', "\"\""),
            entry.started_at_utc,
            entry.ended_at_utc.unwrap_or_default(),
            entry.focus_seconds,
            entry.note.clone().unwrap_or_default().replace('"', "\"\"")
        ));
    }
    result
}

#[derive(Clone)]
struct Segment {
    activity_id: Option<String>,
    name: String,
    color: String,
    start: i64,
    end: i64,
}

fn active_segments(conn: &Connection, start: i64, end: i64) -> Result<Vec<Segment>, String> {
    let timestamp = now();
    let mut stmt = conn.prepare("SELECT e.id, e.activity_id, COALESCE(a.name, '未归类'), COALESCE(a.color, '#9899A4'), e.started_at_utc, COALESCE(e.ended_at_utc, ?1) FROM time_entries e LEFT JOIN activities a ON a.id = e.activity_id WHERE e.started_at_utc < ?2 AND COALESCE(e.ended_at_utc, ?1) > ?3").map_err(database_error)?;
    let entries: Vec<(String, Option<String>, String, String, i64, i64)> = stmt
        .query_map(params![timestamp, end, start], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, i64>(4)?,
                row.get::<_, i64>(5)?,
            ))
        })
        .map_err(database_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(database_error)?;
    let mut result = Vec::new();
    for (id, activity_id, name, color, entry_start, entry_end) in entries {
        let pauses = pauses_for(conn, &id, timestamp)?;
        let mut cursor = entry_start.max(start);
        for (pause_start, pause_end) in pauses {
            let p_start = pause_start.max(start);
            let p_end = pause_end.min(end);
            if p_end <= cursor {
                continue;
            }
            if p_start > cursor {
                result.push(Segment {
                    activity_id: activity_id.clone(),
                    name: name.clone(),
                    color: color.clone(),
                    start: cursor,
                    end: p_start.min(entry_end).min(end),
                });
            }
            cursor = cursor.max(p_end);
        }
        let finish = entry_end.min(end);
        if finish > cursor {
            result.push(Segment {
                activity_id,
                name,
                color,
                start: cursor,
                end: finish,
            });
        }
    }
    Ok(result)
}

fn load_entries(
    conn: &Connection,
    start: i64,
    end: i64,
    timestamp: i64,
) -> Result<Vec<TimeEntry>, String> {
    let mut stmt = conn.prepare("SELECT e.id, e.activity_id, a.name, a.color, e.started_at_utc, e.ended_at_utc, e.status, e.source, e.note FROM time_entries e LEFT JOIN activities a ON a.id = e.activity_id WHERE e.started_at_utc < ?2 AND COALESCE(e.ended_at_utc, ?1) > ?3 ORDER BY e.started_at_utc DESC").map_err(database_error)?;
    let raw: Vec<(
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        i64,
        Option<i64>,
        String,
        String,
        Option<String>,
    )> = stmt
        .query_map(params![timestamp, end, start], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, Option<String>>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, i64>(4)?,
                row.get::<_, Option<i64>>(5)?,
                row.get::<_, String>(6)?,
                row.get::<_, String>(7)?,
                row.get::<_, Option<String>>(8)?,
            ))
        })
        .map_err(database_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(database_error)?;
    raw.into_iter()
        .map(
            |(
                id,
                activity_id,
                activity_name,
                activity_color,
                started_at_utc,
                ended_at_utc,
                status,
                source,
                note,
            )| {
                let paused = pauses_for(conn, &id, timestamp)?
                    .iter()
                    .map(|(a, b)| b - a)
                    .sum::<i64>();
                let finish = ended_at_utc.unwrap_or(timestamp);
                Ok(TimeEntry {
                    id,
                    activity_id,
                    activity_name,
                    activity_color,
                    started_at_utc,
                    ended_at_utc,
                    status,
                    source,
                    note,
                    paused_seconds: paused / 1000,
                    focus_seconds: ((finish - started_at_utc - paused).max(0)) / 1000,
                })
            },
        )
        .collect()
}

fn entry_by_id(conn: &Connection, id: &str, timestamp: i64) -> Result<TimeEntry, String> {
    let mut entries = load_entries(conn, i64::MIN / 2, i64::MAX / 2, timestamp)?;
    entries.retain(|item| item.id == id);
    entries
        .into_iter()
        .next()
        .ok_or_else(|| "找不到该记录".into())
}

fn current_entry(conn: &Connection, timestamp: i64) -> Result<Option<TimeEntry>, String> {
    let id: Option<String> = conn
        .query_row(
            "SELECT id FROM time_entries WHERE ended_at_utc IS NULL LIMIT 1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(database_error)?;
    id.map(|entry_id| entry_by_id(conn, &entry_id, timestamp))
        .transpose()
}

fn current_break(conn: &Connection) -> Result<Option<BreakEntry>, String> {
    conn.query_row("SELECT id, started_at_utc, ended_at_utc, trigger, status FROM break_entries WHERE ended_at_utc IS NULL LIMIT 1", [], |row| Ok(BreakEntry { id: row.get(0)?, started_at_utc: row.get(1)?, ended_at_utc: row.get(2)?, trigger: row.get(3)?, status: row.get(4)? })).optional().map_err(database_error)
}

fn pauses_for(
    conn: &Connection,
    entry_id: &str,
    timestamp: i64,
) -> Result<Vec<(i64, i64)>, String> {
    let mut stmt = conn.prepare("SELECT started_at_utc, COALESCE(ended_at_utc, ?2) FROM entry_pauses WHERE time_entry_id = ?1 ORDER BY started_at_utc").map_err(database_error)?;
    let results = stmt
        .query_map(params![entry_id, timestamp], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })
        .map_err(database_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(database_error)?;
    Ok(results)
}

fn break_seconds(conn: &Connection, start: i64, end: i64) -> Result<i64, String> {
    let timestamp = now();
    let mut stmt = conn.prepare("SELECT started_at_utc, COALESCE(ended_at_utc, ?1) FROM break_entries WHERE started_at_utc < ?2 AND COALESCE(ended_at_utc, ?1) > ?3").map_err(database_error)?;
    let pairs = stmt
        .query_map(params![timestamp, end, start], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?))
        })
        .map_err(database_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(database_error)?;
    Ok(pairs
        .into_iter()
        .map(|(a, b)| b.min(end) - a.max(start))
        .sum())
}

fn timezone(conn: &Connection) -> Result<Tz, String> {
    Ok(setting_string(conn, "timezone")?
        .unwrap_or_else(|| "UTC".into())
        .parse()
        .unwrap_or(chrono_tz::UTC))
}
fn local_midnight(day: chrono::NaiveDate, tz: Tz) -> Result<i64, String> {
    tz.from_local_datetime(
        &day.and_hms_opt(0, 0, 0)
            .ok_or_else(|| "无效日期".to_string())?,
    )
    .single()
    .or_else(|| {
        tz.from_local_datetime(&day.and_hms_opt(0, 0, 0).unwrap())
            .earliest()
    })
    .map(|d| d.timestamp_millis())
    .ok_or_else(|| "无法转换本地日期".into())
}
fn split_segment<F: FnMut(i64, i64, chrono::DateTime<Tz>)>(
    mut start: i64,
    end: i64,
    tz: Tz,
    mut consume: F,
) -> Result<(), String> {
    while start < end {
        let local = tz
            .timestamp_millis_opt(start)
            .single()
            .ok_or_else(|| "无法转换本地时间".to_string())?;
        let tomorrow = local
            .date_naive()
            .succ_opt()
            .ok_or_else(|| "日期超出范围".to_string())?;
        let next_day = local_midnight(tomorrow, tz)?;
        let next_hour = ((start / 3_600_000) + 1) * 3_600_000;
        let until = end.min(next_day).min(next_hour);
        consume(start, until, local);
        start = until;
    }
    Ok(())
}
fn validate_range(range: &RangeInput) -> Result<(), String> {
    if range.end_at_utc <= range.start_at_utc
        || range.end_at_utc - range.start_at_utc > 370_i64 * 86_400_000
    {
        return Err("请选择不超过 370 天的有效时间范围".into());
    }
    Ok(())
}
fn setting_string(conn: &Connection, key: &str) -> Result<Option<String>, String> {
    let json: Option<String> = conn
        .query_row(
            "SELECT value_json FROM settings WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .map_err(database_error)?;
    json.map(|value| serde_json::from_str::<String>(&value).map_err(|e| e.to_string()))
        .transpose()
}
fn setting_i64(conn: &Connection, key: &str) -> Result<Option<i64>, String> {
    let json: Option<String> = conn
        .query_row(
            "SELECT value_json FROM settings WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .map_err(database_error)?;
    json.map(|value| serde_json::from_str::<i64>(&value).map_err(|e| e.to_string()))
        .transpose()
}
fn setting_i64_tx(tx: &rusqlite::Transaction<'_>, key: &str) -> Result<Option<i64>, String> {
    let json: Option<String> = tx
        .query_row(
            "SELECT value_json FROM settings WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .map_err(database_error)?;
    json.map(|value| serde_json::from_str::<i64>(&value).map_err(|e| e.to_string()))
        .transpose()
}
fn set_setting_tx<T: serde::Serialize>(
    tx: &rusqlite::Transaction<'_>,
    key: &str,
    value: Option<T>,
) -> Result<(), String> {
    match value { Some(value) => tx.execute("INSERT INTO settings (key, value_json, updated_at_utc) VALUES (?1, ?2, ?3) ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json, updated_at_utc=excluded.updated_at_utc", params![key, serde_json::to_string(&value).map_err(|e|e.to_string())?, now()]).map_err(database_error)?, None => tx.execute("DELETE FROM settings WHERE key = ?1", [key]).map_err(database_error)? };
    Ok(())
}
fn setting_i64_write(conn: &Connection, key: &str, value: Option<i64>) -> Result<(), String> {
    match value { Some(value) => conn.execute("INSERT INTO settings (key, value_json, updated_at_utc) VALUES (?1, ?2, ?3) ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json, updated_at_utc=excluded.updated_at_utc", params![key, serde_json::to_string(&value).map_err(|e|e.to_string())?, now()]).map_err(database_error)?, None => conn.execute("DELETE FROM settings WHERE key = ?1", [key]).map_err(database_error)? };
    Ok(())
}
fn settings_get_tx(tx: &rusqlite::Transaction<'_>) -> Result<Settings, String> {
    let timezone: Option<String> = tx
        .query_row(
            "SELECT value_json FROM settings WHERE key = 'timezone'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(database_error)?
        .map(|json| serde_json::from_str(&json).map_err(|e| e.to_string()))
        .transpose()?;
    let row: (i64,i64,i64,Option<String>,Option<String>)=tx.query_row("SELECT focus_minutes, break_minutes, is_enabled, do_not_disturb_start, do_not_disturb_end FROM reminder_rules WHERE id = 'global'", [], |row| Ok((row.get(0)?,row.get(1)?,row.get(2)?,row.get(3)?,row.get(4)?))).map_err(database_error)?;
    Ok(Settings {
        timezone: timezone.unwrap_or_else(|| "UTC".into()),
        focus_minutes: row.0,
        break_minutes: row.1,
        reminders_enabled: row.2 != 0,
        do_not_disturb_start: row.3,
        do_not_disturb_end: row.4,
    })
}
fn is_do_not_disturb(settings: &Settings) -> bool {
    let (Some(start), Some(end)) = (&settings.do_not_disturb_start, &settings.do_not_disturb_end)
    else {
        return false;
    };
    let current = chrono::Local::now().format("%H:%M").to_string();
    if start <= end {
        current >= *start && current < *end
    } else {
        current >= *start || current < *end
    }
}

#[cfg(test)]
mod tests {
    use rusqlite::Connection;

    use super::*;

    fn database() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        crate::db::migrate(&conn).unwrap();
        conn
    }

    fn activity(conn: &mut Connection, name: &str) -> Activity {
        activities_create(
            conn,
            ActivityInput {
                name: name.into(),
                color: None,
                icon: None,
                category: None,
            },
        )
        .unwrap()
    }

    #[test]
    fn only_one_open_entry_is_allowed() {
        let mut conn = database();
        let first = activity(&mut conn, "写作");
        let second = activity(&mut conn, "编码");
        timer_start(&mut conn, &first.id).unwrap();
        assert!(timer_start(&mut conn, &second.id).is_err());
        assert_eq!(
            current_entry(&conn, now()).unwrap().unwrap().activity_id,
            Some(first.id)
        );
    }

    #[test]
    fn switching_closes_the_old_entry_in_one_operation() {
        let mut conn = database();
        let first = activity(&mut conn, "论文");
        let second = activity(&mut conn, "编程");
        timer_start(&mut conn, &first.id).unwrap();
        timer_switch(&mut conn, &second.id).unwrap();
        let open: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM time_entries WHERE ended_at_utc IS NULL",
                [],
                |row| row.get(0),
            )
            .unwrap();
        let closed: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM time_entries WHERE ended_at_utc IS NOT NULL",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(open, 1);
        assert_eq!(closed, 1);
    }

    #[test]
    fn paused_time_is_excluded_from_focus_duration() {
        let mut conn = database();
        let item = activity(&mut conn, "阅读");
        timer_start(&mut conn, &item.id).unwrap();
        timer_pause(&mut conn).unwrap();
        conn.execute(
            "UPDATE entry_pauses SET started_at_utc = ?1 WHERE ended_at_utc IS NULL",
            [now() - 30_000],
        )
        .unwrap();
        timer_resume(&mut conn).unwrap();
        let state = timer_get_current(&conn).unwrap();
        assert!(state.entry.unwrap().paused_seconds >= 30);
    }
}
