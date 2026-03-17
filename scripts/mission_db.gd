extends Node

# ============================================================
# MISSION DB — Repeatable mission definitions.
# Separate from quest_db (story quests).
# Missions are board-assigned, repeatable, rank-gated.
#
# Types:
#   kill        — kill N of enemy_name
#   collect     — have N of item_id in inventory on turn-in
#   deliver     — pick up a letter item, talk to target NPC
#
# Deliver missions rotate through a pool of target NPCs.
# ============================================================

const MISSIONS: Dictionary = {

	# ── D-Rank ──────────────────────────────────────────────

	"d_wolves_20": {
		"id":           "d_wolves_20",
		"rank":         "D",
		"title":        "Wolf Culling",
		"description":  "The wolves near the village have been getting bolder. Thin their numbers.",
		"type":         "kill",
		"enemy_name":   "Wolf",
		"required":     20,
		"reward_xp":    300,
		"reward_gold":  50,
		"min_rank":     "Academy Student",
	},
	"d_wolf_fangs": {
		"id":           "d_wolf_fangs",
		"rank":         "D",
		"title":        "Fang Collection",
		"description":  "A merchant needs wolf fangs for his crafting stock. Collect 10.",
		"type":         "collect",
		"item_id":      "wolf_fang",
		"required":     10,
		"reward_xp":    250,
		"reward_gold":  40,
		"min_rank":     "Academy Student",
	},
	"d_wolf_pelts": {
		"id":           "d_wolf_pelts",
		"rank":         "D",
		"title":        "Pelt Delivery",
		"description":  "The village tailor needs wolf pelts for cold-weather gear. Collect 10.",
		"type":         "collect",
		"item_id":      "wolf_pelt",
		"required":     10,
		"reward_xp":    250,
		"reward_gold":  40,
		"min_rank":     "Academy Student",
	},
	"d_message_a": {
		"id":           "d_message_a",
		"rank":         "D",
		"title":        "Message Delivery",
		"description":  "Deliver an urgent letter to the assigned recipient.",
		"type":         "deliver",
		"letter_item":  "mission_letter",
		"target_pool":  ["Merchant", "Blacksmith", "Elder", "Medic", "Gatekeeper"],
		"reward_xp":    200,
		"reward_gold":  35,
		"min_rank":     "Academy Student",
	},
	"d_message_b": {
		"id":           "d_message_b",
		"rank":         "D",
		"title":        "Confidential Dispatch",
		"description":  "A sealed document must reach its destination quickly and discreetly.",
		"type":         "deliver",
		"letter_item":  "mission_letter",
		"target_pool":  ["Merchant", "Blacksmith", "Elder", "Medic", "Gatekeeper"],
		"reward_xp":    200,
		"reward_gold":  35,
		"min_rank":     "Academy Student",
	},
	"d_ninja_5": {
		"id":           "d_ninja_5",
		"rank":         "D",
		"title":        "Rogue Patrol",
		"description":  "Rogue ninja have been spotted near the village border. Drive them off.",
		"type":         "kill",
		"enemy_name":   "Rogue Ninja",
		"required":     5,
		"reward_xp":    350,
		"reward_gold":  60,
		"min_rank":     "Academy Student",
	},
}

# Missions grouped by rank for board display
const BY_RANK: Dictionary = {
	"D": ["d_wolves_20", "d_wolf_fangs", "d_wolf_pelts", "d_message_a", "d_message_b", "d_ninja_5"],
	"C": [],
	"B": [],
	"A": [],
	"S": [],
}

static func get_mission(id: String) -> Dictionary:
	return MISSIONS.get(id, {}).duplicate(true)

static func get_rank_pool(rank: String) -> Array:
	return BY_RANK.get(rank, []).duplicate()

static func all_ranks() -> Array:
	return ["D", "C", "B", "A", "S"]
