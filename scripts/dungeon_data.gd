extends RefCounted

# ============================================================
# DUNGEON DEFINITIONS
# ============================================================

const DUNGEONS: Dictionary = {
	"wolf_den": {
		"display_name":  "Wolf Den",
		"description":   "A labyrinth of earthen tunnels beneath the forest. Wolves hunt in packs — stay alert.",
		"enemy_types":   ["Wolves", "Alpha Wolves"],
		"accent_color":  Color(0.55, 0.28, 0.07),
		"icon":          "res://sprites/dungeon/wolf_den_icon.png",
		"card_bg":       "res://sprites/dungeon/card_wolf_den.png",
		"scene":         "res://scenes/dungeon_world.tscn",
		"theme":         "wolf",
		"theme_script":  "res://scripts/wolf_den_data.gd",
		"zone_name":     "wolf_den",
		"solo_only":     false,
		"min_level":     1,
		"max_players":   4,
		"spawn_pos":     Vector2(0, 200),
		"exit_zone":     "village",
		"exit_scene":    "res://scenes/village.tscn",
		"exit_pos":      Vector2(40, 40),
		"difficulties":  ["easy", "medium", "hard"],
	},
	"cave_of_trials": {
		"display_name":  "Cave of Trials",
		"description":   "Ancient stone halls carved by forgotten hands. Darkness and danger lurk around every turn.",
		"enemy_types":   ["Wolves", "Alpha Wolves"],
		"accent_color":  Color(0.20, 0.25, 0.45),
		"icon":          "res://sprites/dungeon/cave_of_trials_icon.png",
		"card_bg":       "res://sprites/dungeon/card_cave_of_trials.png",
		"scene":         "res://scenes/dungeon_world.tscn",
		"theme":         "cave",
		"theme_script":  "res://scripts/wolf_den_data.gd",
		"zone_name":     "cave_of_trials",
		"solo_only":     false,
		"min_level":     1,
		"max_players":   4,
		"spawn_pos":     Vector2(0, 200),
		"exit_zone":     "village",
		"exit_scene":    "res://scenes/village.tscn",
		"exit_pos":      Vector2(40, 40),
		"difficulties":  ["easy", "medium", "hard"],
	},
}

static func get_dungeon(id: String) -> Dictionary:
	return DUNGEONS.get(id, {})

static func is_valid(id: String) -> bool:
	return id in DUNGEONS
