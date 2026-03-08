extends RefCounted

# ============================================================
# DUNGEON DEFINITIONS
# All dungeon metadata lives here — server and client both load it.
# ============================================================

const DUNGEONS: Dictionary = {
	"cave_of_trials": {
		"display_name": "Cave of Trials",
		"scene":        "res://scenes/cave.tscn",
		"zone_name":    "cave_of_trials",
		"solo_only":    false,
		"min_level":    1,
		"max_players":  4,
		"spawn_pos":    Vector2(0, 200),   # where players appear on entry
		"exit_zone":    "village",
		"exit_scene":   "res://scenes/village.tscn",
		"exit_pos":     Vector2(40, 40),
	},
	"class_trial": {
		"display_name": "Class Trial",
		"scene":        "res://scenes/cave.tscn",   # reuse cave until art is ready
		"zone_name":    "class_trial",
		"solo_only":    true,
		"min_level":    5,
		"max_players":  1,
		"spawn_pos":    Vector2(0, 200),
		"exit_zone":    "village",
		"exit_scene":   "res://scenes/village.tscn",
		"exit_pos":     Vector2(40, 40),
	},
}

static func get_dungeon(id: String) -> Dictionary:
	return DUNGEONS.get(id, {})

static func is_valid(id: String) -> bool:
	return id in DUNGEONS
