use std::{
    sync::Mutex,
    time::{Duration, Instant},
};

use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, Monitor, PhysicalPosition,
};

use crate::panel_position::{self, Rect, Size};

const TRAY_ID: &str = "eggclip-tray";
const RECENT_BLUR_DURATION: Duration = Duration::from_millis(350);

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

pub fn create_tray(app: &AppHandle) -> tauri::Result<TrayIcon> {
    let open_item = MenuItem::with_id(app, "open", "打开 EggClip", true, None::<&str>)?;
    let about_item = MenuItem::with_id(app, "about", "关于 EggClip", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit_item = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open_item, &about_item, &separator, &quit_item])?;
    let icon = app
        .default_window_icon()
        .cloned()
        .expect("EggClip application icon is missing");

    TrayIconBuilder::with_id(TRAY_ID)
        .icon(icon)
        .tooltip("蛋定 Clip · 等待配对")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" | "about" => show_panel(app, None),
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
        .build(app)
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
}
