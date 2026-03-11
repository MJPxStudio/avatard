extends Node

# ══════════════════════════════════════════════════════════════════════════════
# ClanDB — defines all playable clans and the Clay specialty.
#
# HOW TO ADD A CLAN:
#   1. Add an entry to _CLANS below.
#   2. Add its abilities to ability_db.gd with source: "clan:<id>".
#   3. Add ability scroll items to item_db.gd.
#   4. Implement the passive in player.gd under apply_clan_passive().
#
# PASSIVE EFFECTS (applied in player.gd on login):
#   Defined as a dict — player.gd reads this and applies the values.
#   Keys: hp_bonus, chakra_bonus, vision_bonus, poison_immune,
#         heal_bonus_pct, explosion_radius_bonus_pct
#   Add new keys as passives are implemented.
#
# ELEMENT AFFINITY:
#   null     = player picks freely from Fire/Lightning/Earth
#   "earth"  = Clay specialty locks to Earth as primary
# ══════════════════════════════════════════════════════════════════════════════

const _CLANS: Dictionary = {

	"hyuga": {
		"id":            "hyuga",
		"name":          "Hyuga",
		"display_name":  "Hyuga Clan",
		"lore":          "Masters of the Gentle Fist taijutsu style and wielders of the Byakugan — " +
						 "an all-seeing eye that perceives chakra flow in all directions. " +
						 "Hyuga fighters strike with surgical precision, targeting the enemy's " +
						 "chakra network directly.",
		"passive_name":  "Byakugan",
		"passive_desc":  "Your all-seeing eye expands your vision range, reveals enemy HP at distance, " +
						 "and shows enemy positions through terrain on the minimap.",
		"passive":       {
			"vision_bonus":     64,    # extra pixel radius on detection/aggro range display
			"show_hp_at_range": true,  # enemy HP bars visible without being in melee range
			"minimap_reveal":   true,  # enemies show on minimap at all times
		},
		"ability_pool":  ["gentle_fist", "palm_thrust", "rotation", "64_palms", "128_palms"],
		"element_affinity": null,   # player picks freely
		"color":         Color("c8e6fa"),
	},

	"nara": {
		"id":            "nara",
		"name":          "Nara",
		"display_name":  "Nara Clan",
		"lore":          "The Nara are geniuses who manipulate shadows as weapons. Lazy by reputation " +
						 "but devastatingly effective in battle, they use their shadow techniques to " +
						 "control and punish enemies from a safe distance.",
		"passive_name":  "Shadow Affinity",
		"passive_desc":  "Your shadow techniques are enhanced. All slow and root effects you apply " +
						 "last 25% longer. Your chakra regenerates faster when standing still.",
		"passive":       {
			"slow_duration_bonus_pct": 25,   # % bonus to duration of slow/root effects
			"idle_chakra_regen_bonus": 3,    # extra chakra/sec when not moving
		},
		"ability_pool":  ["shadow_possession", "shadow_strangle", "shadow_pull", "mass_shadow"],
		"element_affinity": null,
		"color":         Color("7040b0"),
	},

	"aburame": {
		"id":            "aburame",
		"name":          "Aburame",
		"display_name":  "Aburame Clan",
		"lore":          "At birth, the Aburame offer their body as a hive for kikaichu insects, " +
						 "which feed on chakra and act as weapons and scouts. They are silent, " +
						 "methodical fighters who wear down enemies through persistent pressure.",
		"passive_name":  "Kikaichu Host",
		"passive_desc":  "Parasitic insects inside you passively drain a small amount of chakra " +
						 "from nearby enemies. You are completely immune to poison.",
		"passive":       {
			"aura_chakra_drain":  2,     # chakra drained per second from enemies within range
			"aura_drain_range":   80,    # pixel radius for passive chakra drain
			"poison_immune":      true,
		},
		"ability_pool":  ["bug_swarm", "parasite", "insect_cocoon", "hive_burst", "bug_cloak"],
		"element_affinity": null,
		"color":         Color("6a8a30"),
	},

	"clay": {
		"id":            "clay",
		"name":          "Clay",
		"display_name":  "Clay Specialty",
		"lore":          "Not a bloodline — a mastered art. Clay specialists have devoted their " +
						 "shinobi career to explosive clay sculpting, imbuing chakra into molded " +
						 "forms and detonating them with devastating precision. Unpredictable and " +
						 "relentless, they are feared on any battlefield.",
		"passive_name":  "Explosive Artistry",
		"passive_desc":  "Your explosion abilities have a 20% wider blast radius. " +
						 "Your primary element is locked to Earth — clay is born from the earth.",
		"passive":       {
			"explosion_radius_bonus_pct": 20,
		},
		"ability_pool":  ["c1_spiders", "c2_dragon", "c3_bomb", "c4_karura", "katsu"],
		"element_affinity": "earth",   # locked — Clay users always start with Earth
		"color":         Color("e0a020"),
	},
}

# ── Element definitions ───────────────────────────────────────────────────────
# Elements available at launch. Second element unlocks at Chunin.

const ELEMENTS: Dictionary = {
	"fire": {
		"id":           "fire",
		"name":         "Fire Release",
		"short":        "Fire",
		"description":  "High burst damage and burn effects. Excels at melting through defenses.",
		"ability_pool": ["fireball", "phoenix_flower", "fire_wall"],
		"color":        Color("e74c3c"),
	},
	"lightning": {
		"id":           "lightning",
		"name":         "Lightning Release",
		"short":        "Lightning",
		"description":  "Fast, piercing attacks with paralysis effects. Best single-target damage.",
		"ability_pool": ["lightning_bolt", "chidori", "lightning_field"],
		"color":        Color("f1c40f"),
	},
	"earth": {
		"id":           "earth",
		"name":         "Earth Release",
		"short":        "Earth",
		"description":  "Defensive walls and crowd control. Slows and damages whole groups.",
		"ability_pool": ["earth_wall", "mud_river", "earth_spikes"],
		"color":        Color("b07020"),
	},
}

const ELEMENT2_MIN_RANK = "Chunin"

# ── Public API ────────────────────────────────────────────────────────────────

func get_clan(id: String) -> Dictionary:
	if not _CLANS.has(id):
		push_error("[ClanDB] Unknown clan id: '%s'" % id)
		return {}
	return _CLANS[id].duplicate(true)

func get_all_clan_ids() -> Array:
	return _CLANS.keys()

func clan_exists(id: String) -> bool:
	return _CLANS.has(id)

func get_element(id: String) -> Dictionary:
	if not ELEMENTS.has(id):
		push_error("[ClanDB] Unknown element id: '%s'" % id)
		return {}
	return ELEMENTS[id].duplicate(true)

func get_all_element_ids() -> Array:
	return ELEMENTS.keys()

func element_exists(id: String) -> bool:
	return ELEMENTS.has(id)

# Returns the ability pool for a clan or element.
# Also filters by player's current rank.
func get_clan_pool(clan_id: String, player_rank: String = "") -> Array:
	var clan = _CLANS.get(clan_id, {})
	var pool: Array = clan.get("ability_pool", [])
	if player_rank != "":
		return AbilityDB.filter_by_rank(pool, player_rank)
	return pool.duplicate()

func get_element_pool(element_id: String, player_rank: String = "") -> Array:
	var el = ELEMENTS.get(element_id, {})
	var pool: Array = el.get("ability_pool", [])
	if player_rank != "":
		return AbilityDB.filter_by_rank(pool, player_rank)
	return pool.duplicate()

# Returns the passive dict for a clan (safe empty dict if none).
func get_passive(clan_id: String) -> Dictionary:
	return _CLANS.get(clan_id, {}).get("passive", {}).duplicate(true)

# Returns the locked element for a clan, or "" if player chooses freely.
func get_element_affinity(clan_id: String) -> String:
	var val = _CLANS.get(clan_id, {}).get("element_affinity", "")
	return val if val is String else ""

# Returns true if this player can unlock a second element.
func can_unlock_element2(player_rank: String) -> bool:
	return RankDB.meets_rank_requirement(player_rank, ELEMENT2_MIN_RANK)
