extends Node

# ============================================================
# DATABASE — JSON file persistence
# One file per player saved to: user://players/<username>.json
# Runs server-side only. Swap for SQLite later if needed.
# ============================================================

const SAVE_DIR = "user://players/"

func _ready() -> void:
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	print("[DB] Save directory: %s" % ProjectSettings.globalize_path(SAVE_DIR))

func load_player(username: String) -> Dictionary:
	var path = _path(username)
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			file.close()
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				# Deserialize Vector2 position from saved array
				if parsed.has("position") and parsed["position"] is Array:
					var p = parsed["position"]
					parsed["position"] = Vector2(p[0], p[1])
				# Deserialize Color tint values in equipped items
				if parsed.has("equipped") and parsed["equipped"] is Dictionary:
					for slot in parsed["equipped"]:
						var item = parsed["equipped"][slot]
						if item is Dictionary and item.has("tint") and item["tint"] is Array:
							var c = item["tint"]
							item["tint"] = Color(c[0], c[1], c[2], c[3])
				print("[DB] Loaded player: %s" % username)
				return parsed
	# New player defaults
	print("[DB] New player: %s" % username)
	return {
		"username":    username,
		"level":       1,
		"exp":         0,
		"stat_hp":     5,
		"stat_chakra": 5,
		"stat_str":    5,
		"stat_dex":    5,
		"stat_int":    5,
		"stat_points": 0,
		"position":    Vector2.ZERO,
		"zone":        "village",
		"kills":       0,
		"deaths":      0
	}

func save_player(username: String, data: Dictionary) -> void:
	var path  = _path(username)
	var saved = data.duplicate(true)
	# Serialize Vector2 to array for JSON
	if saved.has("position") and saved["position"] is Vector2:
		var p = saved["position"]
		saved["position"] = [p.x, p.y]
	# Serialize Color tint values in equipped items
	if saved.has("equipped") and saved["equipped"] is Dictionary:
		for slot in saved["equipped"]:
			var item = saved["equipped"][slot]
			if item is Dictionary and item.has("tint") and item["tint"] is Color:
				var c: Color = item["tint"]
				item["tint"] = [c.r, c.g, c.b, c.a]
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(saved, "\t"))
		file.close()
		print("[DB] Saved player: %s" % username)
	else:
		push_error("[DB] Failed to save player: %s — error: %d" % [username, FileAccess.get_open_error()])

func _path(username: String) -> String:
	# Sanitize username to safe filename
	var safe = username.replace("/", "_").replace("\\", "_").replace("..", "_")
	return SAVE_DIR + safe + ".json"
