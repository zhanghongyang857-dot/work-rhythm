use tauri::{AppHandle, Emitter, Manager, State};

use crate::{
    db::AppState,
    domain::{
        Activity, ActivityBreakdown, ActivityInput, ActivityListOptions, AnalyticsSummary,
        EntryInput, ExportResult, HourTotal, RangeInput, Settings, SettingsInput, TimeEntry,
        TimerState, TodaySummary,
    },
    services,
};

fn connection<'a>(
    state: &'a State<'_, AppState>,
) -> Result<std::sync::MutexGuard<'a, rusqlite::Connection>, String> {
    state.conn.lock().map_err(|_| "数据库锁已损坏".to_string())
}

fn timer_changed(app: &AppHandle, state: &State<'_, AppState>) {
    let _ = state.reminder_tx.send(());
    let _ = app.emit("timer:changed", ());
}
fn activity_changed(app: &AppHandle) {
    let _ = app.emit("activity:changed", ());
}
fn settings_changed(app: &AppHandle) {
    let _ = app.emit("settings:changed", ());
}

#[tauri::command]
pub fn timer_get_current(state: State<'_, AppState>) -> Result<TimerState, String> {
    services::timer_get_current(&*connection(&state)?)
}
#[tauri::command]
pub fn timer_start(
    app: AppHandle,
    state: State<'_, AppState>,
    activity_id: String,
) -> Result<TimerState, String> {
    let result = services::timer_start(&mut *connection(&state)?, &activity_id)?;
    timer_changed(&app, &state);
    Ok(result)
}
#[tauri::command]
pub fn timer_pause(app: AppHandle, state: State<'_, AppState>) -> Result<TimerState, String> {
    let result = services::timer_pause(&mut *connection(&state)?)?;
    timer_changed(&app, &state);
    Ok(result)
}
#[tauri::command]
pub fn timer_resume(app: AppHandle, state: State<'_, AppState>) -> Result<TimerState, String> {
    let result = services::timer_resume(&mut *connection(&state)?)?;
    timer_changed(&app, &state);
    Ok(result)
}
#[tauri::command]
pub fn timer_stop(
    app: AppHandle,
    state: State<'_, AppState>,
    note: Option<String>,
) -> Result<TimerState, String> {
    let result = services::timer_stop(&mut *connection(&state)?, note)?;
    timer_changed(&app, &state);
    Ok(result)
}
#[tauri::command]
pub fn timer_switch_activity(
    app: AppHandle,
    state: State<'_, AppState>,
    activity_id: String,
) -> Result<TimerState, String> {
    let result = services::timer_switch(&mut *connection(&state)?, &activity_id)?;
    timer_changed(&app, &state);
    Ok(result)
}
#[tauri::command]
pub fn timer_get_today_summary(state: State<'_, AppState>) -> Result<TodaySummary, String> {
    services::today_summary(&*connection(&state)?)
}

#[tauri::command]
pub fn activities_list(
    state: State<'_, AppState>,
    options: Option<ActivityListOptions>,
) -> Result<Vec<Activity>, String> {
    services::activities_list(
        &*connection(&state)?,
        options
            .and_then(|item| item.include_archived)
            .unwrap_or(false),
    )
}
#[tauri::command]
pub fn activities_create(
    app: AppHandle,
    state: State<'_, AppState>,
    input: ActivityInput,
) -> Result<Activity, String> {
    let result = services::activities_create(&mut *connection(&state)?, input)?;
    activity_changed(&app);
    Ok(result)
}
#[tauri::command]
pub fn activities_update(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
    input: ActivityInput,
) -> Result<Activity, String> {
    let result = services::activities_update(&mut *connection(&state)?, &id, input)?;
    activity_changed(&app);
    Ok(result)
}
#[tauri::command]
pub fn activities_archive(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    services::activities_archive(&mut *connection(&state)?, &id)?;
    activity_changed(&app);
    Ok(())
}

#[tauri::command]
pub fn entries_list(
    state: State<'_, AppState>,
    range: RangeInput,
) -> Result<Vec<TimeEntry>, String> {
    services::entries_list(&*connection(&state)?, range)
}
#[tauri::command]
pub fn entries_upsert(
    app: AppHandle,
    state: State<'_, AppState>,
    input: EntryInput,
) -> Result<TimeEntry, String> {
    let result = services::entries_upsert(&mut *connection(&state)?, input)?;
    timer_changed(&app, &state);
    Ok(result)
}
#[tauri::command]
pub fn entries_delete(
    app: AppHandle,
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    services::entries_delete(&mut *connection(&state)?, &id)?;
    timer_changed(&app, &state);
    Ok(())
}

#[tauri::command]
pub fn breaks_start(app: AppHandle, state: State<'_, AppState>) -> Result<TimerState, String> {
    let result = services::breaks_start(&mut *connection(&state)?)?;
    timer_changed(&app, &state);
    Ok(result)
}
#[tauri::command]
pub fn breaks_complete(app: AppHandle, state: State<'_, AppState>) -> Result<TimerState, String> {
    let result = services::breaks_complete(&mut *connection(&state)?)?;
    timer_changed(&app, &state);
    Ok(result)
}
#[tauri::command]
pub fn breaks_defer(
    app: AppHandle,
    state: State<'_, AppState>,
    minutes: i64,
) -> Result<TimerState, String> {
    let result = services::breaks_defer(&mut *connection(&state)?, minutes)?;
    timer_changed(&app, &state);
    Ok(result)
}
#[tauri::command]
pub fn breaks_skip(app: AppHandle, state: State<'_, AppState>) -> Result<TimerState, String> {
    let result = services::breaks_skip(&mut *connection(&state)?)?;
    timer_changed(&app, &state);
    Ok(result)
}

#[tauri::command]
pub fn analytics_get_summary(
    state: State<'_, AppState>,
    range: RangeInput,
) -> Result<AnalyticsSummary, String> {
    services::analytics_summary(&*connection(&state)?, range)
}
#[tauri::command]
pub fn analytics_get_breakdown(
    state: State<'_, AppState>,
    range: RangeInput,
) -> Result<Vec<ActivityBreakdown>, String> {
    services::analytics_breakdown(&*connection(&state)?, range)
}
#[tauri::command]
pub fn analytics_get_hourly_activity(
    state: State<'_, AppState>,
    range: RangeInput,
) -> Result<Vec<HourTotal>, String> {
    services::analytics_hourly(&*connection(&state)?, range)
}

#[tauri::command]
pub fn settings_get(state: State<'_, AppState>) -> Result<Settings, String> {
    services::settings_get(&*connection(&state)?)
}
#[tauri::command]
pub fn settings_update(
    app: AppHandle,
    state: State<'_, AppState>,
    input: SettingsInput,
) -> Result<Settings, String> {
    let result = services::settings_update(&mut *connection(&state)?, input)?;
    settings_changed(&app);
    timer_changed(&app, &state);
    Ok(result)
}

#[tauri::command]
pub fn data_export(
    state: State<'_, AppState>,
    format: String,
    range: RangeInput,
) -> Result<ExportResult, String> {
    let path = services::export_data(&*connection(&state)?, &state.data_dir, &format, range)?;
    Ok(ExportResult {
        path: path.display().to_string(),
        format,
    })
}
#[tauri::command]
pub fn data_backup(state: State<'_, AppState>) -> Result<ExportResult, String> {
    let path = services::backup_database(&state.data_dir)?;
    Ok(ExportResult {
        path: path.display().to_string(),
        format: "sqlite".into(),
    })
}

#[tauri::command]
pub fn show_main_window(app: AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}
