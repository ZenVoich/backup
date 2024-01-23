# Backup

Automatic and manual backups to make your Motoko canister more reliable.

On the first backup, a new canister will be created to store the backup data.

1TC will be used to created a new canister, make sure your canister has at least 2TC.

## Install
```
mops add backup
```

## Usage
```motoko
import Backup "mo:backup";

var userNames = Buffer.Buffer<Text>(0); // example data

stable let backupState = Backup.init(null);
let backupManager = Backup.BackupManager(backupState, {maxBackups = 10}); // retain only the latest 10 backups (set to 0 to retain all backups)

// customize to your needs...
type BackupChunk = {
  #v1 : {
    #userNames : [Text];
    // more data...
  };
};

public query ({caller}) func getBackupCanisterId() : async Principal {
  assert(Principal.isController(caller));
  backupManager.getCanisterId();
};

// manually trigger a backup
public shared ({caller}) func backup() : async () {
  assert(Principal.isController(caller));
  await _backup();
};

func _backup() : async () {
  let backup = backupManager.NewBackup("v1");
  await backup.startBackup();
  await backup.uploadChunk(to_candid(#v1(#userNames(Buffer.toArray(userNames))) : BackupChunk));
  // upload more chunks...
  await backup.finishBackup();
};

// automatically backup every hour
backupManager.setTimer(#hours(1), _backup); // also add this line to postupgrade

// restore a backup
public shared ({caller}) func restore(backupId : Nat, chunkIndex : Nat) : async () {
  assert(false); // restore disabled. If you want to restore data, remove this line, and re-deploy the canister.
  assert(Principal.isController(caller));

  // reset state here if needed...

  // restore chunks
  await backupManager.restore(backupId, func(blob : Blob) {
    let ?#v1(chunk) : ?BackupChunk = from_candid(blob) else Debug.trap("Failed to restore chunk");
    switch (chunk) {
      case (#userNames(userNamesStable)) {
        userNames := Buffer.fromArray(userNamesStable);
      };
      // more data...
    };
  });
};
```

## Backup data (one-time setup)

1. Deploy your canister
2. Check that backup works without errors `dfx canister call <canister> backup`
3. Get backup canister id `dfx canister call <canister> getBackupCanisterId`
4. Check backup canister dashboard `https://<backup-canister-id>.raw.icp0.io`

## Restore data
1. Open backup canister dashboard and choose backup id that you want to restore
2. Remove `assert(false);` from `restore` method
3. Deploy your canister
4. Call `dfx canister call <canister> restore`
5. Return `assert(false);` to `restore` method
3. Deploy your canister

## Caveats

If you reinstall your canister, new backup canister will be created.

If you want to reinstall your canister and reuse existing backup canister:

replace
```motoko
let backupState = Backup.init(null);
```
with
```motoko
let backupState = Backup.init(?Principal.fromText("<backup-canister-id>"));
```