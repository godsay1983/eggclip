use std::{
    collections::{hash_map::DefaultHasher, VecDeque},
    fmt,
    hash::{Hash, Hasher},
    time::{Duration, Instant},
};

use serde::Serialize;

pub const MAX_TEXT_BYTES: usize = 256 * 1024;
const DEFAULT_SUPPRESSION_TTL: Duration = Duration::from_millis(1500);

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
}
