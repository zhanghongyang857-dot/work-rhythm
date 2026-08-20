mod commands;
mod db;
mod domain;
mod services;

use tauri::{
    menu::{MenuBuilder, MenuItemBuilder},
    tray::TrayIconBuilder,
    Manager, WebviewUrl, WebviewWindowBuilder,
};

fn show_window(app: &tauri::AppHandle, label: &str) {
    if let Some(window) = app.get_webview_window(label) {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            app.manage(db::open_app_state(app.handle())?);
            let show_main = MenuItemBuilder::with_id("show-main", "打开 Work Rhythm").build(app)?;
            let show_timer =
                MenuItemBuilder::with_id("show-timer", "显示 Mini Timer").build(app)?;
            let hide_timer =
                MenuItemBuilder::with_id("hide-timer", "隐藏 Mini Timer").build(app)?;
            let quit = MenuItemBuilder::with_id("quit", "退出 Work Rhythm").build(app)?;
            let menu = MenuBuilder::new(app)
                .item(&show_main)
                .item(&show_timer)
                .item(&hide_timer)
                .separator()
                .item(&quit)
                .build()?;

            TrayIconBuilder::with_id("work-rhythm-tray")
                .menu(&menu)
                .tooltip("Work Rhythm")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show-main" => show_window(app, "main"),
                    "show-timer" => show_window(app, "mini-timer"),
                    "hide-timer" => {
                        if let Some(window) = app.get_webview_window("mini-timer") {
                            let _ = window.hide();
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;

            WebviewWindowBuilder::new(app, "mini-timer", WebviewUrl::App("mini-timer.html".into()))
                .title("Work Rhythm")
                .inner_size(390.0, 250.0)
                .min_inner_size(330.0, 220.0)
                .resizable(false)
                .decorations(false)
                .always_on_top(true)
                .skip_taskbar(true)
                .build()?;

            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() == "main" {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::timer_get_current,
            commands::timer_start,
            commands::timer_pause,
            commands::timer_resume,
            commands::timer_stop,
            commands::timer_switch_activity,
            commands::timer_get_today_summary,
            commands::activities_list,
            commands::activities_create,
            commands::activities_update,
            commands::activities_archive,
            commands::entries_list,
            commands::entries_upsert,
            commands::entries_delete,
            commands::breaks_start,
            commands::breaks_complete,
            commands::breaks_defer,
            commands::breaks_skip,
            commands::analytics_get_summary,
            commands::analytics_get_breakdown,
            commands::analytics_get_hourly_activity,
            commands::settings_get,
            commands::settings_update,
            commands::data_export,
            commands::data_backup,
            commands::show_main_window
        ])
        .run(tauri::generate_context!())
        .expect("failed to run Work Rhythm");
}
