extends Node

# ============================================================
# DATABASE — SQLite player persistence
# Autoload as "Database" in Project Settings
# NOTE: SQLite plugin not yet installed — using in-memory stub
# Replace with full SQLite implementation after installing:
# https://github.com/2shady4u/godot-sqlite
# ============================================================

# In-memory store until SQLite is installed
var _store: Dictionary = {}

func _ready() -> void:
	pass

func load_player(username: String) -> Dictionary:
	if _store.has(username):
		return _store[username].duplicate()
	# New player defaults
	var data = {
		username    = username,
		level       = 1,
		exp         = 0,
		stat_hp     = 5,
		stat_chakra = 5,
		stat_str    = 5,
		stat_dex    = 5,
		stat_int    = 5,
		stat_points = 0,
		position    = Vector2.ZERO,
		zone        = "world"
	}
	_store[username] = data
	return data.duplicate()

func save_player(username: String, data: Dictionary) -> void:
	_store[username] = data.duplicate()
	print("[DB] Saved player: %s" % username)
