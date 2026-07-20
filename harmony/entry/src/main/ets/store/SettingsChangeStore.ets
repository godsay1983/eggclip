export type SettingsChangeListener = (revision: number) => void;

export class SettingsChangeStore {
  private readonly listeners: SettingsChangeListener[] = [];
  private currentRevision: number = 0;

  subscribe(listener: SettingsChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: SettingsChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  publish(): number {
    this.currentRevision += 1;
    const listeners = this.listeners.slice();
    for (let index = 0; index < listeners.length; index += 1) {
      try {
        listeners[index](this.currentRevision);
      } catch (_) {
        // A stale page listener must not turn a committed settings save into a
        // visible failure or prevent other mounted pages from refreshing.
      }
    }
    return this.currentRevision;
  }

  revision(): number {
    return this.currentRevision;
  }
}

export const settingsChangeStore: SettingsChangeStore = new SettingsChangeStore();
