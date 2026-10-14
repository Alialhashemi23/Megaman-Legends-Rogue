extends RefCounted
class_name DiverPaths

# Where profiles, settings and checkpoints live. Desktop builds keep their
# portable save/ folder next to the game. Web builds (IndexedDB) and Android
# (an installed APK is read-only) must use Godot's per-app user:// storage.

static func sandboxed() -> bool:
	return OS.has_feature("web") or OS.has_feature("android")

static func pick(portable: String, sandbox: String) -> String:
	return sandbox if sandboxed() else portable
