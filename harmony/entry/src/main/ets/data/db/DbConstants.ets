import { relationalStore } from '@kit.ArkData';
import { CURRENT_SCHEMA_VERSION, DATABASE_NAME } from '../migrations/SchemaMigrations';

export const DATABASE_VERSION: number = CURRENT_SCHEMA_VERSION;

export const STORE_CONFIG: relationalStore.StoreConfig = {
  name: DATABASE_NAME,
  securityLevel: relationalStore.SecurityLevel.S1
};
