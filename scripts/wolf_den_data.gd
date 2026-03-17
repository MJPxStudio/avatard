extends RefCounted

# ============================================================
# WOLF DEN — Dungeon theme data
# Enemy roster, point costs, boss definitions
# ============================================================

const THEME_NAME  = "Wolf Den"
const THEME_COLOR = Color("8B4513")

# Enemy definitions — script path, point cost, tier
const ENEMIES = {
	"wolf": {
		"script": "res://scripts/enemy_wolf.gd",
		"cost":   4,
		"tier":   "base",
		"label":  "Wolf",
	},
	"wolf_alpha": {
		"script": "res://scripts/enemy_wolf.gd",  # will be enemy_wolf_alpha.gd later
		"cost":   8,
		"tier":   "elite",
		"label":  "Alpha Wolf",
	},
}

# Boss per difficulty tier
const BOSSES = {
	"easy":   { "script": "res://scripts/enemy_wolf.gd", "label": "Pack Leader",    "hp_mult": 3.0, "dmg_mult": 1.5 },
	"medium": { "script": "res://scripts/enemy_wolf.gd", "label": "Alpha Den Lord", "hp_mult": 5.0, "dmg_mult": 2.0 },
	"hard":   { "script": "res://scripts/enemy_wolf.gd", "label": "Great Wolf",     "hp_mult": 8.0, "dmg_mult": 3.0 },
}

# Floors per difficulty
const FLOOR_COUNTS = {
	"easy":   3,
	"medium": 5,
	"hard":   7,
}

# Rooms per floor per difficulty
const ROOMS_PER_FLOOR = {
	"easy":   { "min": 4, "max": 6  },
	"medium": { "min": 6, "max": 9  },
	"hard":   { "min": 8, "max": 12 },
}

# Point budget scaling per floor (floor index 0-based)
const POINT_SCALE_PER_FLOOR = 1.3  # each floor is 30% harder than last

# Enemy stat multipliers per difficulty
# hp_mult, dmg_mult, speed_mult, aggro_mult (attack rate / detection)
const ENEMY_SCALING = {
	"easy":   { "hp": 1.0, "dmg": 1.0, "speed": 1.0,  "aggro": 1.0 },
	"medium": { "hp": 1.8, "dmg": 1.4, "speed": 1.15, "aggro": 1.35 },
	"hard":   { "hp": 3.0, "dmg": 2.0, "speed": 1.30, "aggro": 1.80 },
}

# Additional scaling per floor within a run (stacks with difficulty)
const FLOOR_HP_SCALE    = 1.15   # +15% HP each floor
const FLOOR_DMG_SCALE   = 1.08   # +8% damage each floor

static func get_base_points(difficulty: String) -> int:
	match difficulty:
		"easy":   return 10
		"medium": return 16
		"hard":   return 22
	return 10

static func get_floor_points(difficulty: String, floor_index: int) -> int:
	var base = get_base_points(difficulty)
	return int(base * pow(POINT_SCALE_PER_FLOOR, floor_index))

static func fill_room(points: int, difficulty: String) -> Array:
	# Greedy fill: try to place highest cost enemies first for variety
	var remaining = points
	var spawns    = []
	var attempts  = 0

	# For hard difficulty, mix in elites
	var use_elites = difficulty in ["medium", "hard"] and points >= 12

	while remaining >= 4 and attempts < 20:
		attempts += 1
		if use_elites and remaining >= 8 and randf() < 0.3:
			spawns.append(ENEMIES["wolf_alpha"].duplicate())
			remaining -= 8
		else:
			spawns.append(ENEMIES["wolf"].duplicate())
			remaining -= 4

	return spawns
