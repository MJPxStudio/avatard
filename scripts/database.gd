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
				# Rebuild equipped items from ItemDB so fields are always current.
				# Only the tint (runtime cosmetic state) is preserved from save data.
				if parsed.has("equipped") and parsed["equipped"] is Dictionary:
					var rebuilt: Dictionary = {}
					for slot in parsed["equipped"]:
						var saved = parsed["equipped"][slot]
						if not saved is Dictionary:
							continue
						var item_id: String = saved.get("id", "")
						if item_id == "" or not ItemDB.exists(item_id):
							continue
						# Fresh definition from DB — stats, paths, etc. always up to date
						var fresh = ItemDB.get_item(item_id)
						# Restore saved tint if present
						if saved.has("tint"):
							fresh = ItemDB.apply_saved_tint(fresh, saved["tint"])
						rebuilt[slot] = fresh
					parsed["equipped"] = rebuilt
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
	# For equipped items: save only id + tint. All other fields are rebuilt
	# from ItemDB on load, so outdated stat/path data never persists.
	if saved.has("equipped") and saved["equipped"] is Dictionary:
		var slim: Dictionary = {}
		for slot in saved["equipped"]:
			var item = saved["equipped"][slot]
			if not item is Dictionary:
				continue
			var entry: Dictionary = {"id": item.get("id", "")}
			if item.has("tint"):
				var t = item["tint"]
				if t is Color:
					entry["tint"] = [t.r, t.g, t.b, t.a]
				elif t is Array:
					entry["tint"] = t  # already serialized
			slim[slot] = entry
		saved["equipped"] = slim
	# Serialize appearance.hair_color Color → array for JSON
	if saved.has("appearance") and saved["appearance"] is Dictionary:
		var app = saved["appearance"].duplicate()
		if app.has("hair_color") and app["hair_color"] is Color:
			var c = app["hair_color"]
			app["hair_color"] = [c.r, c.g, c.b, c.a]
		saved["appearance"] = app
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
