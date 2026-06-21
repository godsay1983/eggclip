use std::{
    collections::{hash_map::DefaultHasher, VecDeque},
    fmt,
    hash::{Hash, Hasher},
    sync::Mutex,
    time::{Duration, Instant},
};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

pub const MAX_TEXT_BYTES: usize = 256 * 1024;
const DEFAULT_SUPPRESSION_TTL: Duration = Duration::from_millis(1500);

#[derive(Default)]
pub struct ClipboardRuntime {
    suppression: Mutex<SuppressionTracker>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ClipboardTextError {
    Empty,
    TooLarge {
        actual_bytes: usize,
        max_bytes: usize,
    },
}

impl fmt::Display for ClipboardTextError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ClipboardTextError::Empty => formatter.write_str("剪贴板为空或不是可同步文本"),
            ClipboardTextError::TooLarge {
                actual_bytes,
                max_bytes,
            } => write!(
                formatter,
                "文本过大：{} 字节，当前上限为 {} 字节",
                actual_bytes, max_bytes
            ),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ClipboardEventSource {
    Local,
    RemoteWriteEcho,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipboardText {
    text: String,
    byte_len: usize,
    digest: u64,
}

impl ClipboardText {
    pub fn parse(text: impl Into<String>) -> Result<Self, ClipboardTextError> {
        let text = text.into();
        let byte_len = text.len();
        if byte_len == 0 {
            return Err(ClipboardTextError::Empty);
        }
        if byte_len > MAX_TEXT_BYTES {
            return Err(ClipboardTextError::TooLarge {
                actual_bytes: byte_len,
                max_bytes: MAX_TEXT_BYTES,
            });
        }
        let digest = digest_text(&text);
        Ok(Self {
            text,
            byte_len,
            digest,
        })
    }

    pub fn as_str(&self) -> &str {
        &self.text
    }

    pub fn byte_len(&self) -> usize {
        self.byte_len
    }

    pub fn digest(&self) -> u64 {
        self.digest
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipboardMonitorEvent {
    item: ClipboardText,
}

#[derive(Debug, Clone)]
struct SuppressionToken {
    digest: u64,
    sequence: Option<u64>,
    expires_at: Instant,
}

#[derive(Debug)]
pub struct SuppressionTracker {
    ttl: Duration,
    tokens: VecDeque<SuppressionToken>,
}

impl Default for SuppressionTracker {
    fn default() -> Self {
        Self::new(DEFAULT_SUPPRESSION_TTL)
    }
}

impl SuppressionTracker {
    pub fn new(ttl: Duration) -> Self {
        Self {
            ttl,
            tokens: VecDeque::new(),
        }
    }

    pub fn remember_remote_write(&mut self, item: &ClipboardText, sequence: Option<u64>) {
        self.prune_expired(Instant::now());
        self.tokens.push_back(SuppressionToken {
            digest: item.digest(),
            sequence,
            expires_at: Instant::now() + self.ttl,
        });
    }

    pub fn classify_update(
        &mut self,
        item: &ClipboardText,
        sequence: Option<u64>,
    ) -> ClipboardEventSource {
        let now = Instant::now();
        self.prune_expired(now);
        let matched_index = self.tokens.iter().position(|token| {
            token.digest == item.digest()
                && match (token.sequence, sequence) {
                    (Some(expected), Some(actual)) => expected == actual,
                    // Some clipboard APIs do not expose a useful sequence for every path.
                    // In that case, the short TTL plus digest is the fallback.
                    (None, _) | (_, None) => true,
                }
        });

        if let Some(index) = matched_index {
            self.tokens.remove(index);
            ClipboardEventSource::RemoteWriteEcho
        } else {
            ClipboardEventSource::Local
        }
    }

    fn prune_expired(&mut self, now: Instant) {
        while self
            .tokens
            .front()
            .is_some_and(|token| token.expires_at <= now)
        {
            self.tokens.pop_front();
        }
    }
}

fn digest_text(text: &str) -> u64 {
    let mut hasher = DefaultHasher::new();
    text.hash(&mut hasher);
    hasher.finish()
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipboardReadResult {
    item: Option<ClipboardText>,
    error: Option<ClipboardTextError>,
}

impl ClipboardReadResult {
    fn from_parse_result(result: Result<ClipboardText, ClipboardTextError>) -> Self {
        match result {
            Ok(item) => Self {
                item: Some(item),
                error: None,
            },
            Err(error) => Self {
                item: None,
                error: Some(error),
            },
        }
    }
}

#[tauri::command]
pub fn read_clipboard_text() -> Result<ClipboardReadResult, String> {
    let mut clipboard =
        arboard::Clipboard::new().map_err(|error| format!("无法访问系统剪贴板：{error}"))?;
    let text = clipboard
        .get_text()
        .map_err(|error| format!("无法读取系统剪贴板文本：{error}"))?;
    Ok(ClipboardReadResult::from_parse_result(
        ClipboardText::parse(text),
    ))
}

#[tauri::command]
pub fn write_clipboard_text(text: String) -> Result<(), String> {
    let item = ClipboardText::parse(text).map_err(|error| error.to_string())?;
    let mut clipboard =
        arboard::Clipboard::new().map_err(|error| format!("无法访问系统剪贴板：{error}"))?;
    clipboard
        .set_text(item.as_str().to_owned())
        .map_err(|error| format!("无法写入系统剪贴板：{error}"))
}

pub fn write_remote_clipboard_text(app: &AppHandle, item: &ClipboardText) -> Result<(), String> {
    let runtime = app.state::<ClipboardRuntime>();
    let mut suppression = runtime
        .suppression
        .lock()
        .map_err(|_| "剪贴板回环抑制状态锁已损坏".to_owned())?;
    let mut clipboard =
        arboard::Clipboard::new().map_err(|error| format!("无法访问系统剪贴板：{error}"))?;
    clipboard
        .set_text(item.as_str().to_owned())
        .map_err(|error| format!("无法写入系统剪贴板：{error}"))?;
    suppression.remember_remote_write(item, clipboard_sequence());
    Ok(())
}

#[cfg(target_os = "windows")]
pub fn start_clipboard_monitor(app: AppHandle) {
    let monitor_app = app.clone();
    let spawn_result = std::thread::Builder::new()
        .name("eggclip-clipboard-monitor".to_owned())
        .spawn(move || {
            let mut monitor = match clipboard_win::monitor::Monitor::new() {
                Ok(monitor) => monitor,
                Err(error) => {
                    let _ = monitor_app.emit(
                        "clipboard://monitor-error",
                        format!("无法启动 Windows 剪贴板监听：{error}"),
                    );
                    return;
                }
            };
            loop {
                match monitor.recv() {
                    Ok(true) => {
                        let item = match read_clipboard_text_for_monitor() {
                            Ok(item) => item,
                            Err(_) => continue,
                        };

                        let source = match classify_monitored_update(&monitor_app, &item) {
                            Ok(source) => source,
                            Err(error) => {
                                let _ = monitor_app.emit("clipboard://monitor-error", error);
                                continue;
                            }
                        };
                        if source == ClipboardEventSource::RemoteWriteEcho {
                            continue;
                        }

                        let _ = monitor_app.emit(
                            "clipboard://local-text",
                            ClipboardMonitorEvent { item: item.clone() },
                        );
                    }
                    Ok(false) => break,
                    Err(error) => {
                        let _ = monitor_app.emit(
                            "clipboard://monitor-error",
                            format!("Windows 剪贴板监听已停止：{error}"),
                        );
                        break;
                    }
                }
            }
        });

    if let Err(error) = spawn_result {
        let _ = app.emit(
            "clipboard://monitor-error",
            format!("无法创建剪贴板监听线程：{error}"),
        );
    }
}

#[cfg(target_os = "windows")]
fn classify_monitored_update(
    app: &AppHandle,
    item: &ClipboardText,
) -> Result<ClipboardEventSource, String> {
    let runtime = app.state::<ClipboardRuntime>();
    let mut suppression = runtime
        .suppression
        .lock()
        .map_err(|_| "剪贴板回环抑制状态锁已损坏".to_owned())?;
    Ok(suppression.classify_update(item, clipboard_sequence()))
}

#[cfg(target_os = "windows")]
fn clipboard_sequence() -> Option<u64> {
    clipboard_win::seq_num().map(|sequence| u64::from(sequence.get()))
}

#[cfg(not(target_os = "windows"))]
fn clipboard_sequence() -> Option<u64> {
    None
}

#[cfg(not(target_os = "windows"))]
pub fn start_clipboard_monitor(app: AppHandle) {
    let _ = app.emit(
        "clipboard://monitor-error",
        "当前版本只支持 Windows 剪贴板事件监听",
    );
}

#[cfg(target_os = "windows")]
fn read_clipboard_text_for_monitor() -> Result<ClipboardText, String> {
    let mut clipboard =
        arboard::Clipboard::new().map_err(|error| format!("无法访问系统剪贴板：{error}"))?;
    let text = clipboard
        .get_text()
        .map_err(|error| format!("无法读取系统剪贴板文本：{error}"))?;
    ClipboardText::parse(text).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;

    #[test]
    fn rejects_empty_text() {
        assert_eq!(
            ClipboardText::parse("").unwrap_err(),
            ClipboardTextError::Empty
        );
    }

    #[test]
    fn counts_utf8_bytes_not_characters() {
        let item = ClipboardText::parse("蛋定🥚").expect("valid clipboard text");

        assert_eq!(item.as_str(), "蛋定🥚");
        assert_eq!(item.byte_len(), "蛋定🥚".len());
        assert_eq!(item.byte_len(), 10);
    }

    #[test]
    fn accepts_exactly_256_kib() {
        let text = "a".repeat(MAX_TEXT_BYTES);
        let item = ClipboardText::parse(text).expect("boundary text should be accepted");

        assert_eq!(item.byte_len(), MAX_TEXT_BYTES);
    }

    #[test]
    fn rejects_text_over_256_kib() {
        let text = "a".repeat(MAX_TEXT_BYTES + 1);
        assert_eq!(
            ClipboardText::parse(text).unwrap_err(),
            ClipboardTextError::TooLarge {
                actual_bytes: MAX_TEXT_BYTES + 1,
                max_bytes: MAX_TEXT_BYTES,
            },
        );
    }

    #[test]
    fn suppresses_a_remote_write_echo_once() {
        let item = ClipboardText::parse("from desktop peer").expect("valid clipboard text");
        let mut tracker = SuppressionTracker::default();

        tracker.remember_remote_write(&item, Some(42));

        assert_eq!(
            tracker.classify_update(&item, Some(42)),
            ClipboardEventSource::RemoteWriteEcho,
        );
        assert_eq!(
            tracker.classify_update(&item, Some(42)),
            ClipboardEventSource::Local,
        );
    }

    #[test]
    fn allows_same_text_after_suppression_expires() {
        let item = ClipboardText::parse("repeat later").expect("valid clipboard text");
        let mut tracker = SuppressionTracker::new(Duration::from_millis(1));

        tracker.remember_remote_write(&item, None);
        thread::sleep(Duration::from_millis(5));

        assert_eq!(
            tracker.classify_update(&item, None),
            ClipboardEventSource::Local
        );
    }

    #[test]
    fn allows_same_text_with_a_different_clipboard_sequence() {
        let item = ClipboardText::parse("same text, new copy").expect("valid clipboard text");
        let mut tracker = SuppressionTracker::default();

        tracker.remember_remote_write(&item, Some(7));

        assert_eq!(
            tracker.classify_update(&item, Some(8)),
            ClipboardEventSource::Local
        );
        assert_eq!(
            tracker.classify_update(&item, Some(7)),
            ClipboardEventSource::RemoteWriteEcho
        );
    }
}
