use crate::sync::LanguageMode;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SupportedLocale {
    ZhCn,
    EnUs,
}

impl SupportedLocale {
    pub const fn language_tag(self) -> &'static str {
        match self {
            Self::ZhCn => "zh-CN",
            Self::EnUs => "en-US",
        }
    }
}

pub fn resolve_effective_locale(
    language_mode: &LanguageMode,
    system_locale: Option<&str>,
) -> SupportedLocale {
    match language_mode {
        LanguageMode::ZhCn => SupportedLocale::ZhCn,
        LanguageMode::EnUs => SupportedLocale::EnUs,
        LanguageMode::System => resolve_system_locale(system_locale),
    }
}

pub fn effective_locale(language_mode: &LanguageMode) -> SupportedLocale {
    let system_locale = windows_user_locale_name();
    resolve_effective_locale(language_mode, system_locale.as_deref())
}

fn resolve_system_locale(value: Option<&str>) -> SupportedLocale {
    let normalized = value.unwrap_or_default().trim().to_ascii_lowercase();
    if normalized == "zh" || normalized.starts_with("zh-") || normalized.starts_with("zh_") {
        SupportedLocale::ZhCn
    } else {
        SupportedLocale::EnUs
    }
}

#[cfg(windows)]
fn windows_user_locale_name() -> Option<String> {
    use windows_sys::Win32::Globalization::GetUserDefaultLocaleName;

    // Windows defines LOCALE_NAME_MAX_LENGTH as 85 including the terminator.
    let mut buffer = [0_u16; 85];
    // SAFETY: `buffer` is writable for the declared length and Windows writes a
    // null-terminated locale name no longer than LOCALE_NAME_MAX_LENGTH.
    let length = unsafe { GetUserDefaultLocaleName(buffer.as_mut_ptr(), buffer.len() as i32) };
    if length <= 1 {
        return None;
    }
    String::from_utf16(&buffer[..length as usize - 1]).ok()
}

#[cfg(not(windows))]
fn windows_user_locale_name() -> Option<String> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explicit_language_mode_overrides_the_system_locale() {
        assert_eq!(
            resolve_effective_locale(&LanguageMode::ZhCn, Some("en-US")),
            SupportedLocale::ZhCn
        );
        assert_eq!(
            resolve_effective_locale(&LanguageMode::EnUs, Some("zh-CN")),
            SupportedLocale::EnUs
        );
    }

    #[test]
    fn system_mode_supports_chinese_and_falls_back_to_english() {
        assert_eq!(
            resolve_effective_locale(&LanguageMode::System, Some("zh-Hans-CN")),
            SupportedLocale::ZhCn
        );
        assert_eq!(
            resolve_effective_locale(&LanguageMode::System, Some("en-GB")),
            SupportedLocale::EnUs
        );
        assert_eq!(
            resolve_effective_locale(&LanguageMode::System, Some("fr-FR")),
            SupportedLocale::EnUs
        );
        assert_eq!(
            resolve_effective_locale(&LanguageMode::System, None),
            SupportedLocale::EnUs
        );
    }
}
