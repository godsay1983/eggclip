import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { STORE_CONFIG } from './DbConstants';
import { MigrationRunner } from './MigrationRunner';

let cachedStore: relationalStore.RdbStore | null = null;

export class Database {
  static async getStore(context: common.Context): Promise<relationalStore.RdbStore> {
    if (cachedStore !== null) {
      return cachedStore;
    }

    const store = await relationalStore.getRdbStore(context, STORE_CONFIG);
    await new MigrationRunner().migrate(store);
    cachedStore = store;
    return store;
  }

  static resetCacheForTest(): void {
    cachedStore = null;
  }
}
