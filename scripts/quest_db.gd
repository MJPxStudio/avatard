extends Node

# ============================================================
# QUEST DB — Static quest definitions.
# Shared by client and server. Pure data — no Node logic.
#
# Types:
#   talk      — talk to completer NPC
#   kill      — kill N of target enemy
#   training  — special multi-objective (see training_grounds.gd)
#   escort    — auto-triggered, completes when escort ends
# ============================================================

const QUESTS: Dictionary = {

	# ── Intro Chain ───────────────────────────────────────────────────────────

	"q_meet_the_jonin": {
		"id":          "q_meet_the_jonin",
		"title":       "A New Arrival",
		"description": "Follow the guard to the Kage House and speak with the Jonin.",
		"giver":       "__escort__",   # auto-assigned — not from NPC dialogue
		"completer":   "Jonin",
		"type":        "talk",
		"target":      "Jonin",
		"required":    1,
		"reward_xp":   100,
		"reward_gold": 0,
		"prereq":      "",
		"chain":       "intro",
		"offer_pages": [],
		"complete_pages": [
			"So, you're the new arrival. Welcome to the village.",
			"I'm Jonin Takeda. I'll be overseeing your early training.\nFollow me — let's see what you're made of.",
		],
	},
	"q_basic_training": {
		"id":          "q_basic_training",
		"title":       "Basic Training",
		"description": "Complete the training exercises with Jonin Takeda.",
		"giver":       "Jonin",
		"completer":   "Jonin",
		"type":        "training",
		"required":    1,
		"reward_xp":   300,
		"reward_gold": 0,
		"prereq":      "q_meet_the_jonin",
		"chain":       "intro",
		"offer_pages": [
			"Before we proceed, I need to assess your fundamentals.",
			"Head to the training grounds to the east.\nComplete the exercises — movement, striking, evasion.",
			"Return to me when you're done.",
		],
		"complete_pages": [
			"Not bad. You've got the basics down.",
			"There's one more thing to do before I can recommend you.\nHead to the Academy and speak with the instructor there.",
		],
	},
	"q_enroll_academy": {
		"id":          "q_enroll_academy",
		"title":       "Report to the Academy",
		"description": "Speak with the Academy Instructor.",
		"giver":       "Jonin",
		"completer":   "Academy Instructor",
		"type":        "talk",
		"target":      "Academy Instructor",
		"required":    1,
		"reward_xp":   100,
		"reward_gold": 0,
		"prereq":      "q_basic_training",
		"chain":       "intro",
		"offer_pages": [],  # given automatically after q_basic_training completes
		"complete_pages": [
			"Ah, sent by Jonin Takeda? Then you've passed the basic assessment.",
			"I'm officially enrolling you as a Genin of the Hidden Leaf.\nWear that title with pride — it means you're ready for real missions.",
			"Jonin Takeda has one final instruction for you.\nHead back to the Kage House.",
		],
	},
	"q_report_to_missions": {
		"id":          "q_report_to_missions",
		"title":       "Your First Assignment",
		"description": "Speak with the Mission Assignment Jonin at the Kage House.",
		"giver":       "Academy Instructor",
		"completer":   "Mission Assignment Jonin",
		"type":        "talk",
		"target":      "Mission Assignment Jonin",
		"required":    1,
		"reward_xp":   500,
		"reward_gold": 50,
		"prereq":      "q_enroll_academy",
		"chain":       "intro",
		"offer_pages": [],  # given automatically after q_enroll_academy completes
		"complete_pages": [
			"Welcome, Genin. I'm the one who hands out missions around here.",
			"The mission board is right here — it's updated regularly with tasks\nthat need doing. D-rank is where you start.",
			"Complete missions to build your reputation and earn your keep.\nAs your rank grows, harder — and more rewarding — work becomes available.",
			"That's all you need to know. The board is yours.\nGet to work.",
		],
	},

	# ── Post-intro (old quests, kept for continuity) ──────────────────────────

	"wolf_problem": {
		"id":          "wolf_problem",
		"title":       "Wolf Problem",
		"description": "Defeat 3 wolves in the open world.",
		"giver":       "Mission Assignment Jonin",
		"completer":   "Mission Assignment Jonin",
		"type":        "kill",
		"target":      "Wolf",
		"required":    3,
		"reward_xp":   150,
		"reward_gold": 15,
		"prereq":      "q_report_to_missions",
		"chain":       "",
		"offer_pages": [
			"We've got a wolf situation near the south road.",
			"Take three of them out and report back.",
		],
		"complete_pages": [
			"Good work. The road is safer.",
			"Keep it up — there's always more work to be done.",
		],
	},
	"rogue_threat": {
		"id":          "rogue_threat",
		"title":       "Rogue Threat",
		"description": "Defeat 2 rogue ninjas.",
		"giver":       "Mission Assignment Jonin",
		"completer":   "Mission Assignment Jonin",
		"type":        "kill",
		"target":      "Rogue Ninja",
		"required":    2,
		"reward_xp":   300,
		"reward_gold": 25,
		"prereq":      "wolf_problem",
		"chain":       "",
		"offer_pages": [
			"Rogue ninja spotted near the cliffs. More dangerous than wolves.",
			"Take out two of them. Don't get sloppy.",
		],
		"complete_pages": [
			"Impressive. Rogue ninja aren't easy targets.",
			"You're growing into a proper shinobi.",
		],
	},
}

static func get_quest(id: String) -> Dictionary:
	if not QUESTS.has(id):
		return {}
	return QUESTS[id].duplicate(true)

static func quests_for_giver(npc_name: String) -> Array:
	var result: Array = []
	for qid in QUESTS:
		if QUESTS[qid]["giver"] == npc_name:
			result.append(QUESTS[qid])
	return result

static func quests_for_completer(npc_name: String) -> Array:
	var result: Array = []
	for qid in QUESTS:
		if QUESTS[qid]["completer"] == npc_name:
			result.append(QUESTS[qid])
	return result

static func get_quest_context(npc_name: String, quest_state: Dictionary) -> Dictionary:
	# Priority 1: completable quest
	for qdef in quests_for_completer(npc_name):
		var qid = qdef["id"]
		var qs  = quest_state.get(qid, {})
		if qs.get("status") != "active":
			continue
		var ready = false
		match qdef["type"]:
			"talk", "escort":
				ready = true
			"kill":
				ready = qs.get("progress", 0) >= qdef["required"]
			"training":
				ready = qs.get("progress", 0) >= 1
		if ready:
			return {"id": qid, "action": "complete", "pages": qdef["complete_pages"]}

	# Priority 2: available quest
	for qdef in quests_for_giver(npc_name):
		var qid = qdef["id"]
		if qdef.get("offer_pages", []).is_empty():
			continue  # auto-assigned quests — not offered through dialogue
		var qs = quest_state.get(qid, {})
		if qs.has("status"):
			continue
		var prereq = qdef.get("prereq", "")
		if prereq != "":
			if quest_state.get(prereq, {}).get("status", "") != "turned_in":
				continue
		return {"id": qid, "action": "offer", "pages": qdef["offer_pages"]}

	return {}

# Auto-assign next intro chain quest after one completes (no dialogue needed)
static func get_auto_followup(completed_id: String) -> String:
	match completed_id:
		"q_basic_training":  return "q_enroll_academy"
		"q_enroll_academy":  return "q_report_to_missions"
	return ""
