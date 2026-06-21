use tauri::AppHandle;

use crate::clipboard::{self, ClipboardText};

/// Only authenticated online ITEM_LIVE events may enter this policy boundary.
/// The unauthenticated POC transport and historical/batch events must never call it.
pub fn apply_authenticated_live_item(app: &AppHandle, item: &ClipboardText) -> Result<(), String> {
    clipboard::write_remote_clipboard_text(app, item)
}
