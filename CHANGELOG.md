## 2.0.1
- Fixed critical bug when restoring from backup

## 2.0.0
- Added support to retain only the latest N backups

**Migration from v1 to v2:**
- v2 canister is not compatible with v1 canister so you need to rename backup state stable variable name in order to deploy v2 canister.
- Add `maxBackups : Nat` to `BackupManager` as a second argument (set to 0 to retain all backups)

Example:
```diff
- stable let backupState = Backup.init(null);
- let backupManager = Backup.BackupManager(backupState);
+ stable let backupStateV2 = Backup.init(null);
+ let backupManager = Backup.BackupManager(backupStateV2, {maxBackups = 10});
```