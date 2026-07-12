use std::{
    sync::Mutex,
    thread,
    time::{Duration, Instant},
};

use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, Monitor, PhysicalPosition,
};

use crate::panel_position::{self, Rect, Size};

const TRAY_ID: &str = "eggclip-tray";
const RECENT_BLUR_DURATION: Duration = Duration::from_millis(350);
const TRAY_STATUS_REFRESH_INTERVAL: Duration = Duration::from_secs(1);

pub struct TrayStatusState {
    status_item: MenuItem<tauri::Wry>,
    toggle_sync_item: MenuItem<tauri::Wry>,
}

#[derive(Default)]
struct PanelStateInner {
    last_blur_hide: Option<Instant>,
    last_tray_press: Option<Instant>,
}

#[derive(Default)]
pub struct PanelState {
    inner: Mutex<PanelStateInner>,
}

impl PanelState {
    pub fn handle_blur(&self) -> bool {
        let Ok(mut inner) = self.inner.lock() else {
            return true;
        };
        inner.last_blur_hide = Some(Instant::now());
        true
    }

    fn mark_tray_press(&self) {
        if let Ok(mut inner) = self.inner.lock() {
            inner.last_tray_press = Some(Instant::now());
        }
    }

    fn consume_matching_blur(&self) -> bool {
        let Ok(mut inner) = self.inner.lock() else {
            return false;
        };
        let now = Instant::now();
        let should_suppress = match (inner.last_blur_hide, inner.last_tray_press) {
            (Some(blur), Some(press)) => {
                now.saturating_duration_since(blur) < RECENT_BLUR_DURATION
                    && press <= blur
                    && blur.saturating_duration_since(press) < RECENT_BLUR_DURATION
            }
            _ => false,
        };
        inner.last_blur_hide = None;
        inner.last_tray_press = None;
        should_suppress
    }

    fn clear_toggle_history(&self) {
        if let Ok(mut inner) = self.inner.lock() {
            inner.last_blur_hide = None;
            inner.last_tray_press = None;
        }
    }
}

pub fn create_tray(app: &AppHandle) -> tauri::Result<(TrayIcon, TrayStatusState)> {
    let open_item = MenuItem::with_id(app, "open", "打开 EggClip", true, None::<&str>)?;
    let status_item = MenuItem::with_id(app, "status", "0 台可信设备在线", false, None::<&str>)?;
    let toggle_sync_item = MenuItem::with_id(app, "toggle-sync", "暂停同步", true, None::<&str>)?;
    let manage_devices_item =
        MenuItem::with_id(app, "manage-devices", "管理设备", true, None::<&str>)?;
    let about_item = MenuItem::with_id(app, "about", "关于 EggClip", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit_item = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[
            &open_item,
            &status_item,
            &toggle_sync_item,
            &manage_devices_item,
            &separator,
            &about_item,
            &quit_item,
        ],
    )?;
    let icon = app
        .default_window_icon()
        .cloned()
        .expect("EggClip application icon is missing");

    let tray = TrayIconBuilder::with_id(TRAY_ID)
        .icon(icon)
        .tooltip("蛋定 Clip · 等待配对")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" | "about" => show_panel(app, None),
            "toggle-sync" => toggle_sync(app),
            "manage-devices" => {
                show_panel(app, None);
                let _ = app.emit("tray://open-devices", ());
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| match event {
            TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Down,
                ..
            } => tray.app_handle().state::<PanelState>().mark_tray_press(),
            TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                rect,
                ..
            } => {
                let position = rect.position.to_physical::<f64>(1.0);
                let size = rect.size.to_physical::<f64>(1.0);
                toggle_panel(
                    tray.app_handle(),
                    Some(Rect {
                        x: position.x,
                        y: position.y,
                        width: size.width,
                        height: size.height,
                    }),
                );
            }
            _ => {}
        })
        .build(app)?;
    Ok((
        tray,
        TrayStatusState {
            status_item,
            toggle_sync_item,
        },
    ))
}

pub fn start_status_task(app: AppHandle) {
    let _ = thread::Builder::new()
        .name("eggclip-tray-status".to_owned())
        .spawn(move || loop {
            refresh_status(&app);
            thread::sleep(TRAY_STATUS_REFRESH_INTERVAL);
        });
}

pub fn refresh_status(app: &AppHandle) {
    let settings = crate::settings::load_app_settings(app.clone()).unwrap_or_default();
    let online_count = crate::transport::authenticated_device_peers(app).len();
    let labels = tray_status_labels(settings.sync_enabled, online_count);
    let state = app.state::<TrayStatusState>();
    let _ = state.status_item.set_text(labels.status);
    let _ = state.toggle_sync_item.set_text(labels.toggle_sync);
    if let Some(tray) = app.tray_by_id(TRAY_ID) {
        let _ = tray.set_tooltip(Some(labels.tooltip));
    }
}

struct TrayStatusLabels {
    status: String,
    toggle_sync: &'static str,
    tooltip: String,
}

fn tray_status_labels(sync_enabled: bool, online_count: usize) -> TrayStatusLabels {
    let sync_label = if sync_enabled {
        "同步已开启"
    } else {
        "同步已暂停"
    };
    TrayStatusLabels {
        status: format!("{online_count} 台可信设备在线"),
        toggle_sync: if sync_enabled {
            "暂停同步"
        } else {
            "恢复同步"
        },
        tooltip: format!("蛋定 Clip · {sync_label} · {online_count} 台设备在线"),
    }
}

fn toggle_sync(app: &AppHandle) {
    let Ok(mut settings) = crate::settings::load_app_settings(app.clone()) else {
        return;
    };
    settings.sync_enabled = !settings.sync_enabled;
    let Ok(saved) = crate::settings::save_app_settings(app.clone(), settings) else {
        return;
    };
    let _ = app.emit("settings://changed", saved);
    refresh_status(app);
}

fn toggle_panel(app: &AppHandle, anchor: Option<Rect>) {
    let Some(window) = app.get_webview_window("main") else {
        return;
    };
    if window.is_visible().unwrap_or(false) {
        app.state::<PanelState>().clear_toggle_history();
        let _ = window.hide();
        return;
    }
    if app.state::<PanelState>().consume_matching_blur() {
        return;
    }
    show_panel(app, anchor);
}

pub fn show_panel(app: &AppHandle, anchor: Option<Rect>) {
    let Some(window) = app.get_webview_window("main") else {
        return;
    };
    app.state::<PanelState>().clear_toggle_history();
    match anchor {
        Some(anchor) => place_near_tray(&window, anchor),
        None => place_at_screen_corner(&window),
    }
    let _ = window.show();
    let _ = window.set_focus();
}

fn place_near_tray(window: &tauri::WebviewWindow, anchor: Rect) {
    let Ok(panel_size) = window.outer_size() else {
        return;
    };
    let panel = Size {
        width: f64::from(panel_size.width),
        height: f64::from(panel_size.height),
    };
    let center = anchor.center();
    let monitor = window
        .monitor_from_point(center.x, center.y)
        .ok()
        .flatten()
        .or_else(|| window.current_monitor().ok().flatten())
        .or_else(|| window.primary_monitor().ok().flatten());
    if let Some(monitor) = monitor {
        set_panel_position(
            window,
            panel_position::near_tray(
                anchor,
                monitor_work_area(&monitor),
                panel,
                monitor.scale_factor(),
            ),
        );
    }
}

fn place_at_screen_corner(window: &tauri::WebviewWindow) {
    let (Ok(panel_size), Ok(Some(monitor))) = (window.outer_size(), window.primary_monitor())
    else {
        return;
    };
    let panel = Size {
        width: f64::from(panel_size.width),
        height: f64::from(panel_size.height),
    };
    set_panel_position(
        window,
        panel_position::at_bottom_right(monitor_work_area(&monitor), panel, monitor.scale_factor()),
    );
}

fn monitor_work_area(monitor: &Monitor) -> Rect {
    let area = monitor.work_area();
    Rect {
        x: f64::from(area.position.x),
        y: f64::from(area.position.y),
        width: f64::from(area.size.width),
        height: f64::from(area.size.height),
    }
}

fn set_panel_position(window: &tauri::WebviewWindow, point: panel_position::Point) {
    let _ = window.set_position(PhysicalPosition::new(
        point.x.round() as i32,
        point.y.round() as i32,
    ));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blur_without_a_prior_tray_press_does_not_suppress_reopen() {
        let state = PanelState::default();
        assert!(state.handle_blur());
        state.mark_tray_press();
        assert!(!state.consume_matching_blur());
    }

    #[test]
    fn tray_status_labels_cover_online_count_and_pause_action() {
        let active = tray_status_labels(true, 2);
        assert_eq!(active.status, "2 台可信设备在线");
        assert_eq!(active.toggle_sync, "暂停同步");
        assert!(active.tooltip.contains("同步已开启"));

        let paused = tray_status_labels(false, 0);
        assert_eq!(paused.toggle_sync, "恢复同步");
        assert!(paused.tooltip.contains("同步已暂停"));
    }
}
