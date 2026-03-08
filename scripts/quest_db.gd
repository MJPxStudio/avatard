extends Node

# ============================================================
# QUEST DB — Static quest definitions.
# Shared by client and server. Pure data — no Node logic.
# ============================================================

const QUESTS: Dictionary = {
	"first_steps": {
		"id":          "first_steps",
		"title":       "First Steps",
		"description": "Speak with the Hokage.",
		"giver":       "Guard",
		"completer":   "Hokage",
		"type":        "talk",
		"target":      "Hokage",
		"required":    1,
		"reward_xp":   50,
		"reward_gold": 5,
		"prereq":      "",
		"offer_pages": [
			"Halt — ah, a new face. Welcome to the village.",
			"The Hokage has asked to be introduced to any newcomers.\nHead to the building to the north and speak with him.",
		],
		"complete_pages": [
			"Welcome, young shinobi. I'm glad you came.\nThere is much work to be done in these lands.",
			"Rest here and prepare yourself.\nReturn when you're ready for your first assignment.",
		],
	},
	"wolf_problem": {
		"id":          "wolf_problem",
		"title":       "Wolf Problem",
		"description": "Defeat 3 wolves in the open world.",
		"giver":       "Hokage",
		"completer":   "Hokage",
		"type":        "kill",
		"target":      "Wolf",
		"required":    3,
		"reward_xp":   150,
		"reward_gold": 15,
		"prereq":      "first_steps",
		"offer_pages": [
			"I have a mission for you.\nWolves have been attacking travelers near the southern gate.",
			"Head into the open world and defeat three of them.\nReport back when it's done.",
		],
		"complete_pages": [
			"Excellent. The roads are safer thanks to you.",
			"You're proving yourself to be a capable shinobi.\nTake this as your reward.",
		],
	},
	"rogue_threat": {
		"id":          "rogue_threat",
		"title":       "Rogue Threat",
		"description": "Defeat 2 rogue ninjas.",
		"giver":       "Hokage",
		"completer":   "Hokage",
		"type":        "kill",
		"target":      "Rogue Ninja",
		"required":    2,
		"reward_xp":   300,
		"reward_gold": 25,
		"prereq":      "wolf_problem",
		"offer_pages": [
			"There's a more serious matter I need you to handle.",
			"Rogue ninjas have been spotted near the cliffs.\nThey're dangerous — proceed with caution.",
			"Defeat two of them and return to me.",
		],
		"complete_pages": [
			"Impressive work. Not many shinobi could handle rogue ninja alone.",
			"The village is safer because of your efforts.\nYou have my gratitude.",
		],
	},
}

static func get_quest(id: String) -> Dictionary:
	return QUESTS.get(id, {})

# Returns quests this NPC offers (giver == npc_name)
static func quests_for_giver(npc_name: String) -> Array:
	var result: Array = []
	for qid in QUESTS:
		if QUESTS[qid]["giver"] == npc_name:
			result.append(QUESTS[qid])
	return result

# Returns quests this NPC completes (completer == npc_name)
static func quests_for_completer(npc_name: String) -> Array:
	var result: Array = []
	for qid in QUESTS:
		if QUESTS[qid]["completer"] == npc_name:
			result.append(QUESTS[qid])
	return result

# Given a player's quest_state dict, return the best quest context for this NPC:
# Returns {id, action, pages} or {} if no quest interaction
static func get_quest_context(npc_name: String, quest_state: Dictionary) -> Dictionary:
	# Priority 1: completable quest (active + ready to turn in)
	for qdef in quests_for_completer(npc_name):
		var qid = qdef["id"]
		var qs  = quest_state.get(qid, {})
		if qs.get("status") != "active":
			continue
		var ready = false
		if qdef["type"] == "talk":
			ready = true
		elif qdef["type"] == "kill":
			ready = qs.get("progress", 0) >= qdef["required"]
		if ready:
			return {"id": qid, "action": "complete", "pages": qdef["complete_pages"]}

	# Priority 2: available quest (not started, prereq met)
	for qdef in quests_for_giver(npc_name):
		var qid    = qdef["id"]
		var qs     = quest_state.get(qid, {})
		# Skip if already accepted or done
		if qs.has("status"):
			continue
		# Check prereq
		var prereq = qdef["prereq"]
		if prereq != "":
			var prereq_qs = quest_state.get(prereq, {})
			if prereq_qs.get("status", "") != "turned_in":
				continue
		return {"id": qid, "action": "offer", "pages": qdef["offer_pages"]}

	return {}
