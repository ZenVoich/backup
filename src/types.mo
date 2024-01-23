module {
	/// The maximum number of backups to keep.
	/// If the number of backups exceeds this number, the oldest backup will be deleted.
	/// If set to 0, no backups will be deleted.
	public type Config = {
		maxBackups : Nat;
	};
};