# EggClip HarmonyOS data layer

This directory contains ArkData RDB setup, migrations and repository command builders. Pages and components must not access RDB directly.

- `db/Database.ets` opens the cached `RdbStore` and applies migrations.
- `db/MigrationRunner.ets` applies pending schema migrations in version order, one transaction per migration.
- `db/RdbCommandRunner.ets` executes repository commands and command arrays inside an RDB transaction.
- `repositories/RepositoryCommands.ets` only builds SQL commands and validates domain inputs; it does not own UI or network policy.
- `repositories/RdbRepositories.ets` exposes real RDB repositories for Space, Device, Clipboard, SyncHead and Settings records.
- `repositories/LocalIdentityRdbRepository.ets` persists the local `deviceId` and monotonic `originSeq` in `app_metadata`.
