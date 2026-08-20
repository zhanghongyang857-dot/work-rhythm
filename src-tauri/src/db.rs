use std::{
    fs,
    path::PathBuf,
    sync::{mpsc, Arc, Mutex},
    thread,
    time::Duration,
};

use rusqlite::Connection;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_notification::NotificationExt;

use crate::services;

pub struct AppState {
    pub conn: Arc<Mutex<Connection>>,
    pub data_dir: PathBuf,
    pub reminder_tx: mpsc::Sender<()>,
}

pub fn open_app_state(app: &AppHandle) -> Result<AppState, Box<dyn std::error::Error>> {
    let data_dir = app.path().app_data_dir()?;
    fs::create_dir_all(&data_dir)?;
    let database_path = data_dir.join("work-rhythm.sqlite3");
    let conn = Connection::open(database_path)?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    migrate(&conn)?;
    let conn = Arc::new(Mutex::new(conn));
    let (reminder_tx, reminder_rx) = mpsc::channel();
    spawn_reminder_worker(app.clone(), conn.clone(), reminder_rx);
    Ok(AppState {
        conn,
        data_dir,
        reminder_tx,
    })
}

fn spawn_reminder_worker(
    app: AppHandle,
    conn: Arc<Mutex<Connection>>,
    receiver: mpsc::Receiver<()>,
) {
    thread::spawn(move || loop {
        let timeout = conn
            .lock()
            .ok()
            .and_then(|database| services::reminder_wait_ms(&database).ok().flatten())
            .map(Duration::from_millis);
        match timeout {
            Some(wait) => match receiver.recv_timeout(wait) {
                Ok(_) => continue,
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    let _ = app
                        .notification()
                        .builder()
                        .title("Work Rhythm")
                        .body("一个专注周期已完成，该休息一下了。")
                        .show();
                    let _ = app.emit("timer:changed", ());
                    // One reminder is emitted for each calculated deadline. The next user action
                    // (start, defer, skip, or complete) wakes the worker with a new deadline.
                    let _ = receiver.recv();
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            },
            None => {
                if receiver.recv().is_err() {
                    break;
                }
            }
        }
    });
}

pub(crate) fn migrate(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at_utc INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS activities (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL COLLATE NOCASE,
          color TEXT NOT NULL,
          icon TEXT,
          category TEXT,
          is_archived INTEGER NOT NULL DEFAULT 0,
          created_at_utc INTEGER NOT NULL,
          updated_at_utc INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS time_entries (
          id TEXT PRIMARY KEY,
          activity_id TEXT REFERENCES activities(id),
          started_at_utc INTEGER NOT NULL,
          ended_at_utc INTEGER,
          status TEXT NOT NULL CHECK(status IN ('running', 'paused', 'completed')),
          source TEXT NOT NULL DEFAULT 'timer',
          note TEXT
        );
        CREATE UNIQUE INDEX IF NOT EXISTS one_open_time_entry
          ON time_entries((1)) WHERE ended_at_utc IS NULL;
        CREATE INDEX IF NOT EXISTS time_entries_started_at_idx ON time_entries(started_at_utc);
        CREATE INDEX IF NOT EXISTS time_entries_activity_started_idx ON time_entries(activity_id, started_at_utc);
        CREATE TABLE IF NOT EXISTS entry_pauses (
          id TEXT PRIMARY KEY,
          time_entry_id TEXT NOT NULL REFERENCES time_entries(id) ON DELETE CASCADE,
          started_at_utc INTEGER NOT NULL,
          ended_at_utc INTEGER
        );
        CREATE UNIQUE INDEX IF NOT EXISTS one_open_pause_per_entry
          ON entry_pauses(time_entry_id) WHERE ended_at_utc IS NULL;
        CREATE TABLE IF NOT EXISTS break_entries (
          id TEXT PRIMARY KEY,
          started_at_utc INTEGER NOT NULL,
          ended_at_utc INTEGER,
          trigger TEXT NOT NULL,
          status TEXT NOT NULL CHECK(status IN ('running', 'completed', 'skipped'))
        );
        CREATE INDEX IF NOT EXISTS break_entries_started_at_idx ON break_entries(started_at_utc);
        CREATE UNIQUE INDEX IF NOT EXISTS one_open_break_entry
          ON break_entries((1)) WHERE ended_at_utc IS NULL;
        CREATE TABLE IF NOT EXISTS reminder_rules (
          id TEXT PRIMARY KEY,
          focus_minutes INTEGER NOT NULL,
          break_minutes INTEGER NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          do_not_disturb_start TEXT,
          do_not_disturb_end TEXT,
          updated_at_utc INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value_json TEXT NOT NULL,
          updated_at_utc INTEGER NOT NULL
        );
        ",
    )?;
    let now = chrono::Utc::now().timestamp_millis();
    let timezone = iana_time_zone::get_timezone().unwrap_or_else(|_| "UTC".to_string());
    let timezone_json = format!("\"{timezone}\"");
    conn.execute(
        "INSERT OR IGNORE INTO reminder_rules (id, focus_minutes, break_minutes, is_enabled, updated_at_utc)
         VALUES ('global', 50, 5, 1, ?1)",
        [now],
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO settings (key, value_json, updated_at_utc) VALUES ('timezone', ?1, ?2)",
        rusqlite::params![timezone_json, now],
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO schema_migrations (version, applied_at_utc) VALUES (1, ?1)",
        [now],
    )?;
    Ok(())
}
