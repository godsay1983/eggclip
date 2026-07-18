import { LanguagePreferenceService, SupportedLocale } from './LanguagePreferenceService';

export class LocalizedFormatter {
  private readonly languagePreference: LanguagePreferenceService;

  constructor(languagePreference?: LanguagePreferenceService) {
    this.languagePreference = languagePreference ?? new LanguagePreferenceService();
  }

  formatTime(milliseconds: number): string {
    return formatLocalizedTime(milliseconds, this.languagePreference.currentLocale());
  }

  formatDateTime(milliseconds: number): string {
    return formatLocalizedDateTime(milliseconds, this.languagePreference.currentLocale());
  }
}

export function formatLocalizedTime(milliseconds: number, locale: SupportedLocale): string {
  return new Intl.DateTimeFormat(locale, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  }).format(new Date(milliseconds));
}

export function formatLocalizedDateTime(milliseconds: number, locale: SupportedLocale): string {
  return new Intl.DateTimeFormat(locale, {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit'
  }).format(new Date(milliseconds));
}
