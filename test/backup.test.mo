import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import {test; suite; skip} "mo:test/async";

import Backup "../src";

await suite("backup", func() : async () {
	let backupState = Backup.init(null);
	let backupManager = Backup.BackupManager(backupState);

	// execution error, actor class configuration unsupported in interpreter
	// execution error, Value.prim: cyclesBalance
	// execution error, Value.prim: stableMemorySize
	await skip("new backup", func() : async () {
		let backup = backupManager.NewBackup("v1");
		await backup.startBackup();
		await backup.uploadChunk(to_candid(#users([1, 2])));
		await backup.uploadChunk(to_candid(#files(["file1", "file2"])));
		await backup.finishBackup();
	});
});