extends Node

# ══════════════════════════════════════════════════════════════════════════════
# RankDB — Naruto rank system.
#
# Ranks gate equipment and abilities. Level thresholds and colors are defined
# here only. Nothing else needs to change when you adjust thresholds.
#
# HOW TO ADD A NEW RANK:
#   Add an entry to RANKS in level order. Keep "index" values sequential.
#
# HOW TO GATE AN ITEM:
#   Add  "min_rank": "Genin"  to the item's entry in item_db.gd.
#   Omit min_rank (or set "") for unrestricted items.
# ══════════════════════════════════════════════════════════════════════════════

# Ordered from lowest to highest. Index must match position.
const RANKS: Array = [
	{
		"name":      "Academy Student",
		"index":     0,
		"min_level": 1,
		"color":     Color("aaaaaa"),   # grey
		"short":     "Academy",
	},
	{
		"name":      "Genin",
		"index":     1,
		"min_level": 5,
		"color":     Color("55dd55"),   # green
		"short":     "Genin",
	},
	{
		"name":      "Chunin",
		"index":     2,
		"min_level": 15,
		"color":     Color("44aaff"),   # blue
		"short":     "Chunin",
	},
	{
		"name":      "Special Jonin",
		"index":     3,
		"min_level": 30,
		"color":     Color("bb66ff"),   # purple
		"short":     "Spec. Jonin",
	},
	{
		"name":      "Jonin",
		"index":     4,
		"min_level": 50,
		"color":     Color("ffdd00"),   # gold
		"short":     "Jonin",
	},
	{
		"name":      "ANBU",
		"index":     5,
		"min_level": 75,
		"color":     Color("ff4444"),   # red
		"short":     "ANBU",
	},
	{
		"name":      "Kage",
		"index":     6,
		"min_level": 100,
		"color":     Color("ffffff"),   # white
		"short":     "Kage",
	},
]

# ── Public API ────────────────────────────────────────────────────────────────

# Returns the full rank dict for a given level.
func get_rank_for_level(lv: int) -> Dictionary:
	var result: Dictionary = RANKS[0]
	for r in RANKS:
		if lv >= r["min_level"]:
			result = r
	return result

# Returns just the rank name string.
func get_rank_name(lv: int) -> String:
	return get_rank_for_level(lv)["name"]

# Returns the rank color.
func get_rank_color(lv: int) -> Color:
	return get_rank_for_level(lv)["color"]

# Returns the numeric index for a rank name (for comparison).
# Higher index = higher rank. Returns -1 for unknown names.
func rank_index(rank_name: String) -> int:
	for r in RANKS:
		if r["name"] == rank_name:
			return r["index"]
	return -1

# Returns true if player_rank meets the item's min_rank requirement.
# Pass "" or null for min_rank to mean "no requirement".
func meets_rank_requirement(player_rank: String, min_rank: String) -> bool:
	if min_rank == "" or min_rank == null:
		return true
	return rank_index(player_rank) >= rank_index(min_rank)

# Returns true if this level-up crossed a rank boundary.
func is_rank_up(old_level: int, new_level: int) -> bool:
	return get_rank_name(old_level) != get_rank_name(new_level)
