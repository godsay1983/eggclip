import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  AppSettings,
  LocalClipboardSyncPolicy,
  SyncPauseReason,
  localClipboardSyncPolicy
} from '../../models/DomainModels';
import { Database } from '../../data/db/Database';
import { RdbCommandRunner } from '../../data/db/RdbCommandRunner';
import {
  ClipboardItemRecord,
  LocalClipboardPersistenceCommands
} from '../../data/repositories/RepositoryCommands';
import { LocalIdentityRdbRepository } from '../../data/repositories/LocalIdentityRdbRepository';

export interface PersistLocalClipboardInput {
  spaceId: string;
  text: string;
  contentDigest: string;
  encryptedContent: Uint8Array;
  settings: AppSettings;
  nowMs: number;
}

export enum LocalClipboardBroadcastStatus {
  SCHEDULED = 'scheduled',
  SKIPPED = 'skipped'
}

export interface PersistLocalClipboardResult {
  record: ClipboardItemRecord;
  policy: LocalClipboardSyncPolicy;
  broadcastStatus: LocalClipboardBroadcastStatus;
  blockedReason?: SyncPauseReason;
}

export class LocalClipboardPersistenceService {
  private readonly context: common.Context;
  private readonly identity: LocalIdentityRdbRepository;
  private readonly commands: LocalClipboardPersistenceCommands = new LocalClipboardPersistenceCommands();
  private readonly runner: RdbCommandRunner = new RdbCommandRunner();

  constructor(context: common.Context) {
    this.context = context;
    this.identity = new LocalIdentityRdbRepository(context);
  }

  async persist(input: PersistLocalClipboardInput): Promise<PersistLocalClipboardResult> {
    const store = await Database.getStore(this.context);
    const originDeviceId = await this.identity.getOrCreateDeviceIdWithStore(store, input.nowMs);
    const originSeq = await this.identity.peekNextOriginSeqWithStore(store);
    const plan = this.commands.build({
      itemId: util.generateRandomUUID(false).toLowerCase(),
      spaceId: input.spaceId,
      originDeviceId,
      originSeq,
      text: input.text,
      contentDigest: input.contentDigest,
      encryptedContent: input.encryptedContent,
      settings: input.settings,
      nowMs: input.nowMs
    });
    if (plan === null) {
      throw new Error('Invalid local clipboard persistence input');
    }

    await this.runner.executeTransaction(store, plan.commands);
    const policy = localClipboardSyncPolicy(input.settings);
    return {
      record: plan.record,
      policy,
      broadcastStatus: policy.broadcastAfterCommit ?
        LocalClipboardBroadcastStatus.SCHEDULED :
        LocalClipboardBroadcastStatus.SKIPPED,
      blockedReason: policy.blockedReason
    };
  }
}
