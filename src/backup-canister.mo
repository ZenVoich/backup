import Array "mo:base/Array";
import TrieMap "mo:base/TrieMap";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Int32 "mo:base/Int32";
import Int "mo:base/Int";
import Char "mo:base/Char";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import ExperimentalStableMemory "mo:base/ExperimentalStableMemory";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Prim "mo:prim";

import DateTime "mo:motoko-datetime/DateTime";
import LinkedList "mo:linked-list";
import Map "mo:map/Map";
import HttpTypes "mo:http-types";
import MemoryRegion "mo:memory-region/MemoryRegion";

import Types "./types";

actor class BackupCanister(whitelist : [Principal], config : Types.Config) {
	type BackupId = Nat;
	type Chunk = Blob;

	type Backup = {
		id : BackupId;
		tag : Text;
		startTime : Time.Time;
		endTime : Time.Time;
		size : Nat;
		chunkRefs : [ChunkRef];
		biggestChunk : {
			index : Nat;
			size : Nat;
		};
	};

	type ChunkRef = {
		offset : Nat;
		size : Nat;
	};

	type UploadingBackup = {
		tag : Text;
		startTime : Time.Time;
		chunks : LinkedList.LinkedList<Blob>;
	};

	stable var curBackupId = 0;
	stable var backups = Map.new<BackupId, Backup>();
	stable var memoryRegion = MemoryRegion.new();

	let uploadingBackups = TrieMap.TrieMap<BackupId, UploadingBackup>(Nat.equal, func x = Text.hash(Nat.toText(x)));

	/////////////////////////
	// HELPERS
	/////////////////////////

	func _isWhitelisted(id : Principal) : Bool {
		Array.find<Principal>(whitelist, func(whitelisted) = whitelisted == id) != null;
	};

	func _isAllowed(id : Principal) : Bool {
		_isWhitelisted(id) or Principal.isController(id);
	};

	func _storeChunk(chunk : Blob) : ChunkRef {
		let offset = MemoryRegion.addBlob(memoryRegion, chunk);

		return {
			offset;
			size = chunk.size();
		};
	};

	func _removeExtraBackups() {
		if (Map.size(backups) >= config.maxBackups) {
			let ?(backupId, backup) = Map.popFront(backups, Map.nhash) else return;

			for (chunkRef in backup.chunkRefs.vals()) {
				MemoryRegion.deallocate(memoryRegion, chunkRef.offset, chunkRef.size);
			};
		};
	};

	/////////////////////////
	// BACKUP
	/////////////////////////

	public shared ({caller}) func startBackup(tag : Text) : async BackupId {
		assert(_isAllowed(caller));

		let backupId = curBackupId;
		curBackupId += 1;

		uploadingBackups.put(backupId, {
			tag;
			startTime = Time.now();
			chunks = LinkedList.LinkedList<Blob>();
		});

		_removeExtraBackups();

		backupId;
	};

	public shared ({caller}) func uploadChunk(backupId : BackupId, chunk : Chunk) : async () {
		assert(_isAllowed(caller));

		let ?uploadingBackup = uploadingBackups.get(backupId) else Debug.trap("uploadChunk: Invalid backup id " # Nat.toText(backupId));
		LinkedList.append(uploadingBackup.chunks, chunk);
	};

	public shared ({caller}) func finishBackup(backupId : BackupId) : async () {
		assert(_isAllowed(caller));

		let ?uploadingBackup = uploadingBackups.get(backupId) else Debug.trap("finishBackup: Invalid backup id " # Nat.toText(backupId));

		let chunkRefs = LinkedList.LinkedList<ChunkRef>();
		var size = 0;
		var biggestChunk = {
			index = 0;
			size = 0;
		};

		var i = 0;
		for (chunk in LinkedList.vals(uploadingBackup.chunks)) {
			let chunkRef = _storeChunk(chunk);
			size += chunkRef.size;
			LinkedList.append(chunkRefs, chunkRef);

			if (chunkRef.size > biggestChunk.size) {
				biggestChunk := {
					index = i;
					size = chunkRef.size;
				};
			};

			i += 1;
		};

		Map.set(backups, Map.nhash, backupId, {
			id = backupId;
			tag = uploadingBackup.tag;
			startTime = uploadingBackup.startTime;
			endTime = Time.now();
			size = size;
			chunkRefs = LinkedList.toArray(chunkRefs);
			biggestChunk = biggestChunk;
		});


		uploadingBackups.delete(backupId);
	};

	/////////////////////////
	// RESTORE
	/////////////////////////

	public query ({caller}) func getChunk(backupId : Nat, chunkIndex : Nat) : async (Chunk, Bool) {
		assert(_isAllowed(caller));

		let ?backup = Map.get(backups, Map.nhash, backupId) else Debug.trap("getChunk: Invalid backup id " # Nat.toText(backupId));
		(_chunkFromRef(backup.chunkRefs[chunkIndex]), backup.chunkRefs.size() == chunkIndex + 1);
	};

	func _chunkFromRef(ref : ChunkRef) : Chunk {
		ExperimentalStableMemory.loadBlob(Nat64.fromNat(ref.offset), ref.size);
	};

	/////////////////////////
	// HTTP
	/////////////////////////

	func formatTime(time : Time.Time) : Text {
		let dt = DateTime.DateTime(?Int.abs(time));
		var res = "";
		res #= dt.showYear();
		res #= "-";
		res #= dt.showMonth();
		res #= "-";
		res #= dt.showDay();
		res #= " ";
		res #= dt.showHours();
		res #= ":";
		res #= dt.showMinutes();
		res #= ":";
		res #= dt.showSeconds();
		res;
	};

	func formatDuration(dur : Time.Time) : Text {
		Int.toText(dur / 1_000_000_000) # " s";
	};

	func addGap(text : Text, sizeInTabs : Nat) : Text {
		let suffixSize : Nat = sizeInTabs - Nat.min(sizeInTabs, text.size() / 8);
		text # Text.fromIter(Array.init<Char>(suffixSize, '\t').vals());
	};

	func formatSize(size : Nat, suffixes : [Text]) : Text {
		func _format(div : Nat, suffix : Text) : Text {
			let q = size / div;
			var r = size % div;
			let rText = Nat.toText(r) # "00";
			let rChars = Iter.toArray(rText.chars());
			Nat.toText(q) # "." # Char.toText(rChars[0]) # Char.toText(rChars[1]) # suffix;
		};

		if (size < 1024) {
			Nat.toText(size) # " " #suffixes[0];
		}
		else if (size < 1024 ** 2) {
			_format(1024, " K" # suffixes[1]);
		}
		else if (size < 1024 ** 3) {
			_format(1024 ** 2, " M" # suffixes[1]);
		}
		else if (size < 1024 ** 4) {
			_format(1024 ** 3, " G" # suffixes[1]);
		}
		else {
			_format(1024 ** 4, " T" # suffixes[1]);
		};
	};

	func getTotalSize() : Nat {
		var res = 0;
		for (backup in Map.vals(backups)) {
			res += backup.size;
		};
		res;
	};

	public query func http_request(request : HttpTypes.Request) : async HttpTypes.Response {
		var body = "";
		body #= "Total backups:\t\t" # Nat.toText(Map.size(backups)) # "\n\n";
		body #= "Total size:\t\t" # formatSize(getTotalSize(), ["b", "B"]) # "\n\n";
		body #= "Cycles balance:\t\t" # formatSize(ExperimentalCycles.balance(), ["cycles", "C"]) # "\n\n";
		body #= "\n\n\n";
		body #= addGap("ID", 2) # addGap("Start Time", 4) # addGap("Size", 2) # addGap("Duration", 2) # addGap("Chunks", 2) # addGap("Biggest Chunk", 3) # "Tag\n";
		body #= "----------------------------------------------------------------------------------------------------------------------------------\n";

		for (backup in Map.valsDesc(backups)) {
			body #= addGap(Nat.toText(backup.id), 2)
				# addGap(formatTime(backup.startTime), 4)
				# addGap(formatSize(backup.size, ["b", "B"]), 2)
				# addGap(formatDuration(backup.endTime - backup.startTime), 2)
				# addGap(Nat.toText(backup.chunkRefs.size()), 2)
				# addGap("#" # Nat.toText(backup.biggestChunk.index) # " - " # formatSize(backup.biggestChunk.size, ["b", "B"]), 3)
				# backup.tag
				# "\n";
		};

		{
			status_code = 200;
			headers = [];
			body = Text.encodeUtf8(body);
			streaming_strategy = null;
			upgrade = null;
		};
	};
};