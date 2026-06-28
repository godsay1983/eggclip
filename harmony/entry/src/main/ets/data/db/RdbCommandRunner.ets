import { relationalStore } from '@kit.ArkData';
import { RepositoryCommand, SqlValue } from '../repositories/RepositoryCommands';

export class RdbCommandRunner {
  async execute(store: relationalStore.RdbStore, command: RepositoryCommand): Promise<void> {
    await store.executeSql(command.sql, this.bindArgs(command.args));
  }

  async executeTransaction(store: relationalStore.RdbStore, commands: RepositoryCommand[]): Promise<void> {
    store.beginTransaction();
    try {
      for (const command of commands) {
        await this.execute(store, command);
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw error;
    }
  }

  bindArgs(args: SqlValue[]): relationalStore.ValueType[] {
    const values: relationalStore.ValueType[] = [];
    for (const arg of args) {
      values.push(arg);
    }
    return values;
  }
}
