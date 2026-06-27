#[cfg(target_os = "windows")]
use clipboard_win::{formats, Setter};

#[cfg(target_os = "windows")]
const SAMPLE_TEXT: &str = "EggClip marker regression sample";
#[cfg(target_os = "windows")]
const EXCLUDE_MONITORING: &str = "ExcludeClipboardContentFromMonitorProcessing";
#[cfg(target_os = "windows")]
const CAN_UPLOAD_TO_CLOUD: &str = "CanUploadToCloudClipboard";

#[cfg(target_os = "windows")]
fn main() -> Result<(), String> {
    let command = std::env::args().nth(1).unwrap_or_else(|| "help".to_owned());

    match command.as_str() {
        "exclude-monitoring" => write_sample(&[(EXCLUDE_MONITORING, 0)])?,
        "cloud-deny" => write_sample(&[(CAN_UPLOAD_TO_CLOUD, 0)])?,
        "both" => write_sample(&[(EXCLUDE_MONITORING, 0), (CAN_UPLOAD_TO_CLOUD, 0)])?,
        "inspect" => inspect_markers()?,
        _ => {
            eprintln!(
                "Usage: cargo run --bin clipboard_marker_sample -- <exclude-monitoring|cloud-deny|both|inspect>"
            );
            return Ok(());
        }
    }

    Ok(())
}

#[cfg(target_os = "windows")]
fn write_sample(markers: &[(&str, u32)]) -> Result<(), String> {
    let _clipboard = clipboard_win::Clipboard::new_attempts(10)
        .map_err(|error| format!("failed to open clipboard: {error}"))?;
    formats::Unicode
        .write_clipboard(&SAMPLE_TEXT)
        .map_err(|error| format!("failed to write sample text: {error}"))?;

    for (name, value) in markers {
        let format = clipboard_win::register_format(name)
            .ok_or_else(|| format!("failed to register clipboard format {name}"))?;
        clipboard_win::raw::set_without_clear(format.get(), &value.to_ne_bytes())
            .map_err(|error| format!("failed to write clipboard marker {name}: {error}"))?;
    }

    println!(
        "wrote sample clipboard item with {} marker(s)",
        markers.len()
    );
    Ok(())
}

#[cfg(target_os = "windows")]
fn inspect_markers() -> Result<(), String> {
    let _clipboard = clipboard_win::Clipboard::new_attempts(10)
        .map_err(|error| format!("failed to open clipboard: {error}"))?;

    for name in [EXCLUDE_MONITORING, CAN_UPLOAD_TO_CLOUD] {
        println!("{name}: {}", format_marker_state(name));
    }

    Ok(())
}

#[cfg(target_os = "windows")]
fn format_marker_state(name: &str) -> String {
    let Some(format) = clipboard_win::register_format(name) else {
        return "unregistered".to_owned();
    };
    if !clipboard_win::is_format_avail(format.get()) {
        return "absent".to_owned();
    }
    let raw_value = clipboard_win::get::<Vec<u8>, _>(formats::RawData(format.get()))
        .ok()
        .and_then(|bytes| decode_dword(&bytes));
    match raw_value {
        Some(value) => format!("present dword={value}"),
        None => "present unreadable-or-malformed".to_owned(),
    }
}

#[cfg(target_os = "windows")]
fn decode_dword(bytes: &[u8]) -> Option<u32> {
    let value: [u8; 4] = bytes.get(..4)?.try_into().ok()?;
    Some(u32::from_ne_bytes(value))
}

#[cfg(not(target_os = "windows"))]
fn main() {
    eprintln!("clipboard_marker_sample is only available on Windows");
}
