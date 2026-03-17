extends Node

# ══════════════════════════════════════════════════════════════════════════════
# AbilityDB — single source of truth for every learnable ability.
#
# HOW TO ADD A NEW ABILITY:
#   1. Add an entry to _ABILITIES below.
#   2. Add a scroll item in item_db.gd with use_effect: {type:"unlock_ability", ability_id:"your_id"}
#   3. Create the ability script at script_path extending AbilityBase.
#   4. That's it — the unlock system, ability menu, and hotbar all read from here.
#
# REQUIRED fields:
#   id          String  — unique snake_case identifier
#   name        String  — display name
#   source      String  — "clan:<clan_id>" | "element:<element_id>"
#   description String  — shown in ability picker UI
#   chakra_cost int
#   cooldown    float   — seconds
#   script_path String  — res:// path to AbilityBase subclass
#   icon_color  Color   — used in hotbar slot background
#
# OPTIONAL fields:
#   min_rank    String  — rank gate (uses RankDB)
#   activation  String  — "instant" (default) | "targeted"
#   tags        Array   — ["melee","aoe","dot","root","knockback","buff","debuff"]
# ══════════════════════════════════════════════════════════════════════════════

const _ABILITIES: Dictionary = {

	# ── Hyuga ─────────────────────────────────────────────────────────────────
	"gentle_fist": {
		"id":          "gentle_fist",
		"name":        "Gentle Fist",
		"source":      "clan:hyuga",
		"description": "A precise palm strike that disrupts the target's chakra network.",
		"chakra_cost": 15,
		"cooldown":    2.5,
		"script_path": "res://scripts/abilities/hyuga/gentle_fist.gd",
		"icon_color":  Color("c8e6fa"),
		"activation":  "instant",
		"tags":        ["melee"],
	},
	"byakugan": {
		"id":          "byakugan",
		"name":        "Byakugan",
		"source":      "clan:hyuga",
		"description": "Activate the Byakugan — wider vision, extended range, enemy chakra reveal, and empowered palms.",
		"chakra_cost": 10,
		"cooldown":    1.0,
		"script_path": "res://scripts/abilities/hyuga/byakugan.gd",
		"icon_color":  Color("e8f8ff"),
		"activation":  "instant",
		"tags":        ["toggle"],
	},
	"rotation": {
		"id":          "rotation",
		"name":        "Eight Trigrams: Palm Rotation",
		"source":      "clan:hyuga",
		"description": "Spin and release chakra — become immune to damage and harm all nearby enemies.",
		"chakra_cost": 35,
		"cooldown":    15.0,
		"script_path": "res://scripts/abilities/hyuga/rotation.gd",
		"icon_color":  Color("60b8ff"),
		"activation":  "instant",
		"tags":        ["aoe", "immunity"],
	},
	"64_palms": {
		"id":          "64_palms",
		"name":        "Eight Trigrams: 64 Palms",
		"source":      "clan:hyuga",
		"description": "Rapid palm strikes — 64 hits normally, 128 with Byakugan active.",
		"chakra_cost": 50,
		"cooldown":    14.0,
		"script_path": "res://scripts/abilities/hyuga/64_palms.gd",
		"icon_icon":   "res://sprites/Hyuga/64palms.png",
		"icon_color":  Color("2090ee"),
		"activation":  "instant",
		"tags":        ["melee"],
	},
	"air_palm": {
		"id":          "air_palm",
		"name":        "Air Palm",
		"source":      "clan:hyuga",
		"description": "Launch a compressed chakra burst that blasts the enemy backwards.",
		"chakra_cost": 25,
		"cooldown":    6.0,
		"script_path": "res://scripts/abilities/hyuga/air_palm.gd",
		"icon_color":  Color("90d8ff"),
		"activation":  "instant",
		"tags":        ["ranged", "knockback"],
	},

	# ── Nara ──────────────────────────────────────────────────────────────────
	"shadow_possession": {
		"id":          "shadow_possession",
		"name":        "Shadow Possession Jutsu",
		"source":      "clan:nara",
		"description": "Extend your shadow to bind an enemy in place. They cannot move while possessed.",
		"chakra_cost": 25,
		"cooldown":    7.0,
		"script_path": "res://scripts/nara_shadow_possession.gd",
		"icon_color":  Color("4a3060"),
		"activation":  "targeted",
		"tags":        ["root", "debuff"],
	},
	"shadow_strangle": {
		"id":          "shadow_strangle",
		"name":        "Shadow Strangle Jutsu",
		"source":      "clan:nara",
		"description": "Command your shadow to choke a bound enemy, dealing damage over time.",
		"chakra_cost": 20,
		"cooldown":    5.0,
		"script_path": "res://scripts/nara_shadow_strangle.gd",
		"icon_color":  Color("6030a0"),
		"activation":  "targeted",
		"tags":        ["dot", "debuff"],
	},
	"shadow_pull": {
		"id":          "shadow_pull",
		"name":        "Shadow Pull",
		"source":      "clan:nara",
		"description": "Your shadow surges forward and yanks an enemy toward you.",
		"chakra_cost": 20,
		"cooldown":    6.0,
		"script_path": "res://scripts/nara_shadow_pull.gd",
		"icon_color":  Color("7040b0"),
		"activation":  "targeted",
		"tags":        ["debuff"],
	},
	"mass_shadow": {
		"id":          "mass_shadow",
		"name":        "Mass Shadow Possession",
		"source":      "clan:nara",
		"description": "Spread your shadow wide, binding multiple enemies simultaneously.",
		"chakra_cost": 60,
		"cooldown":    18.0,
		"script_path": "res://scripts/nara_mass_shadow.gd",
		"icon_color":  Color("3a2080"),
		"activation":  "instant",
		"min_rank":    "Special Jonin",
		"tags":        ["aoe", "root", "debuff"],
	},

	# ── Aburame ───────────────────────────────────────────────────────────────
	"bug_swarm": {
		"id":          "bug_swarm",
		"name":        "Bug Swarm",
		"source":      "clan:aburame",
		"description": "Release a swarm of kikaichu that fly forward dealing damage over time.",
		"chakra_cost": 20,
		"cooldown":    5.0,
		"script_path": "res://scripts/abilities/aburame/bug_swarm.gd",
		"icon_color":  Color("556b2f"),
		"activation":  "instant",
		"tags":        ["dot"],
	},
	"parasite": {
		"id":          "parasite",
		"name":        "Parasite Insect Jutsu",
		"source":      "clan:aburame",
		"description": "Implant chakra-eating bugs on a target. They drain the enemy's chakra over time.",
		"chakra_cost": 25,
		"cooldown":    8.0,
		"script_path": "res://scripts/abilities/aburame/parasite.gd",
		"icon_color":  Color("3d5a1e"),
		"activation":  "targeted",
		"tags":        ["dot", "debuff"],
	},
	"insect_cocoon": {
		"id":          "insect_cocoon",
		"name":        "Insect Cocoon",
		"source":      "clan:aburame",
		"description": "Wrap an enemy in a cocoon of bugs, slowing their movement and dealing damage.",
		"chakra_cost": 30,
		"cooldown":    10.0,
		"script_path": "res://scripts/abilities/aburame/insect_cocoon.gd",
		"icon_color":  Color("4e6b28"),
		"activation":  "targeted",
		"tags":        ["dot", "debuff"],
	},
	"hive_burst": {
		"id":          "hive_burst",
		"name":        "Hive Burst",
		"source":      "clan:aburame",
		"description": "Detonate a swarm of bugs in an explosion of chitinous fury. AoE damage around you.",
		"chakra_cost": 45,
		"cooldown":    12.0,
		"script_path": "res://scripts/abilities/aburame/hive_burst.gd",
		"icon_color":  Color("6a7a30"),
		"activation":  "instant",
		"min_rank":    "Chunin",
		"tags":        ["aoe"],
	},
	"bug_cloak": {
		"id":          "bug_cloak",
		"name":        "Bug Cloak",
		"source":      "clan:aburame",
		"description": "Cover yourself in a defensive layer of bugs. Reduces damage taken and drains attackers' chakra.",
		"chakra_cost": 35,
		"cooldown":    16.0,
		"script_path": "res://scripts/abilities/aburame/bug_cloak.gd",
		"icon_color":  Color("5a7a25"),
		"activation":  "instant",
		"tags":        ["buff"],
	},

	# ── Clay Specialty ────────────────────────────────────────────────────────
	"c1_spiders": {
		"id":          "c1_spiders",
		"name":        "C1: Clay Spiders",
		"source":      "clan:clay",
		"description": "Mold small clay spiders that crawl toward the nearest enemy and explode.",
		"chakra_cost": 20,
		"cooldown":    4.0,
		"script_path": "res://scripts/abilities/clay/c1_spiders.gd",
		"icon_color":  Color("c8a84a"),
		"activation":  "instant",
		"tags":        ["dot"],
	},
	"c2_dragon": {
		"id":          "c2_dragon",
		"name":        "C2: Clay Dragon",
		"source":      "clan:clay",
		"description": "Summon a clay dragon that flies toward enemies and detonates on impact.",
		"chakra_cost": 45,
		"cooldown":    14.0,
		"script_path": "res://scripts/abilities/clay/c2_owl.gd",
		"icon_color":  Color("e0a020"),
		"activation":  "instant",
		"min_rank":    "Chunin",
		"tags":        ["aoe"],
	},
	"c3_bomb": {
		"id":          "c3_bomb",
		"name":        "C3: Giant Bomb",
		"source":      "clan:clay",
		"description": "Drop a massive clay bomb that detonates after a short delay. Massive AoE.",
		"chakra_cost": 65,
		"cooldown":    20.0,
		"script_path": "res://scripts/abilities/clay/c3_bomb.gd",
		"icon_color":  Color("e86800"),
		"activation":  "instant",
		"min_rank":    "Special Jonin",
		"tags":        ["aoe"],
	},
	"c4_karura": {
		"id":          "c4_karura",
		"name":        "C4: Karura",
		"source":      "clan:clay",
		"description": "Release microscopic clay into the air. Enemies who breathe it detonate from within.",
		"chakra_cost": 90,
		"cooldown":    30.0,
		"script_path": "res://scripts/abilities/clay/c4_karura.gd",
		"icon_color":  Color("ff3300"),
		"activation":  "instant",
		"min_rank":    "Jonin",
		"tags":        ["aoe"],
	},
	"katsu": {
		"id":          "katsu",
		"name":        "Katsu",
		"source":      "clan:clay",
		"description": "Detonate all active clay simultaneously in a chain of explosions.",
		"chakra_cost": 10,
		"cooldown":    3.0,
		"script_path": "res://scripts/abilities/clay/katsu.gd",
		"icon_color":  Color("ff6600"),
		"activation":  "instant",
		"tags":        ["aoe"],
	},

	# ── Fire Element ──────────────────────────────────────────────────────────
	"fireball": {
		"id":          "fireball",
		"name":        "Great Fireball Jutsu",
		"source":      "element:fire",
		"description": "Exhale a massive fireball that burns everything it touches.",
		"chakra_cost": 30,
		"cooldown":    5.0,
		"script_path": "res://scripts/abilities/elements/fire/fireball.gd",
		"icon_color":  Color("e74c3c"),
		"activation":  "instant",
		"tags":        ["dot"],
	},
	"phoenix_flower": {
		"id":          "phoenix_flower",
		"name":        "Phoenix Sage Fire",
		"source":      "element:fire",
		"description": "Launch a volley of small fireballs in a spread. Each burns on contact.",
		"chakra_cost": 25,
		"cooldown":    6.0,
		"script_path": "res://scripts/abilities/elements/fire/phoenix_flower.gd",
		"icon_color":  Color("ff6b3d"),
		"activation":  "instant",
		"tags":        ["dot"],
	},
	"fire_wall": {
		"id":          "fire_wall",
		"name":        "Fire Wall",
		"source":      "element:fire",
		"description": "Summon a wall of flames that burns enemies who pass through it.",
		"chakra_cost": 50,
		"cooldown":    15.0,
		"script_path": "res://scripts/abilities/elements/fire/fire_wall.gd",
		"icon_color":  Color("cc2200"),
		"activation":  "instant",
		"min_rank":    "Chunin",
		"tags":        ["aoe", "dot"],
	},

	# ── Lightning Element ─────────────────────────────────────────────────────
	"lightning_bolt": {
		"id":          "lightning_bolt",
		"name":        "Lightning Bolt",
		"source":      "element:lightning",
		"description": "Hurl a crackling bolt of lightning at the target.",
		"chakra_cost": 25,
		"cooldown":    4.0,
		"script_path": "res://scripts/abilities/elements/lightning/lightning_bolt.gd",
		"icon_color":  Color("f1c40f"),
		"activation":  "instant",
		"tags":        ["debuff"],
	},
	"chidori": {
		"id":          "chidori",
		"name":        "Chidori",
		"source":      "element:lightning",
		"description": "Concentrate lightning chakra into your hand and charge forward. High single-target damage.",
		"chakra_cost": 50,
		"cooldown":    12.0,
		"script_path": "res://scripts/abilities/elements/lightning/chidori.gd",
		"icon_color":  Color("e8d820"),
		"activation":  "instant",
		"min_rank":    "Chunin",
		"tags":        ["melee"],
	},
	"lightning_field": {
		"id":          "lightning_field",
		"name":        "Lightning Field",
		"source":      "element:lightning",
		"description": "Electrify the ground around you. Nearby enemies take damage and are paralyzed briefly.",
		"chakra_cost": 55,
		"cooldown":    18.0,
		"script_path": "res://scripts/abilities/elements/lightning/lightning_field.gd",
		"icon_color":  Color("ffe000"),
		"activation":  "instant",
		"min_rank":    "Special Jonin",
		"tags":        ["aoe", "debuff"],
	},

	# ── Earth Element ─────────────────────────────────────────────────────────
	"earth_wall": {
		"id":          "earth_wall",
		"name":        "Earth Wall",
		"source":      "element:earth",
		"description": "Raise a wall of stone that blocks enemy movement and projectiles.",
		"chakra_cost": 30,
		"cooldown":    10.0,
		"script_path": "res://scripts/abilities/elements/earth/earth_wall.gd",
		"icon_color":  Color("8b6914"),
		"activation":  "instant",
		"tags":        ["buff"],
	},
	"mud_river": {
		"id":          "mud_river",
		"name":        "Mud River",
		"source":      "element:earth",
		"description": "Churn the ground into a river of mud, slowing all enemies in the area.",
		"chakra_cost": 30,
		"cooldown":    9.0,
		"script_path": "res://scripts/abilities/elements/earth/mud_river.gd",
		"icon_color":  Color("a0782a"),
		"activation":  "instant",
		"tags":        ["aoe", "debuff"],
	},
	"earth_spikes": {
		"id":          "earth_spikes",
		"name":        "Earth Spikes",
		"source":      "element:earth",
		"description": "Erupt spikes of stone from the ground in a line, impaling enemies.",
		"chakra_cost": 40,
		"cooldown":    11.0,
		"script_path": "res://scripts/abilities/elements/earth/earth_spikes.gd",
		"icon_color":  Color("b07020"),
		"activation":  "instant",
		"min_rank":    "Chunin",
		"tags":        ["aoe"],
	},
}

# ── Public API ────────────────────────────────────────────────────────────────

func get_ability(id: String) -> Dictionary:
	if not _ABILITIES.has(id):
		push_error("[AbilityDB] Unknown ability id: '%s'" % id)
		return {}
	return _ABILITIES[id].duplicate(true)

func get_all_ids() -> Array:
	return _ABILITIES.keys()

func exists(id: String) -> bool:
	return _ABILITIES.has(id)

# Returns all ability ids for a given clan or element.
# source_key: "clan:hyuga" | "element:fire" etc.
func get_pool(source_key: String) -> Array:
	var result: Array = []
	for id in _ABILITIES:
		if _ABILITIES[id].get("source", "") == source_key:
			result.append(id)
	return result

# Returns all ability ids the player can currently use given their rank.
func filter_by_rank(ids: Array, player_rank: String) -> Array:
	return ids.filter(func(id):
		var min_rank = _ABILITIES[id].get("min_rank", "")
		return RankDB.meets_rank_requirement(player_rank, min_rank)
	)

# Returns true if ability belongs to a given clan.
func is_clan_ability(id: String, clan_id: String) -> bool:
	return _ABILITIES.get(id, {}).get("source", "") == "clan:" + clan_id

# Returns true if ability belongs to a given element.
func is_element_ability(id: String, element_id: String) -> bool:
	return _ABILITIES.get(id, {}).get("source", "") == "element:" + element_id

# Creates a live AbilityBase instance for hotbar use.
# Loads the script at script_path if it exists, otherwise builds a stub.
# Stamps _ability_id so the menu can identify which ability is in each slot.
func create_instance(id: String) -> AbilityBase:
	var ab = get_ability(id)
	if ab.is_empty():
		return null
	var instance: AbilityBase = null
	var script_path = ab.get("script_path", "")
	if script_path != "" and ResourceLoader.exists(script_path):
		var scr = load(script_path)
		if scr:
			instance = scr.new()
	# Fallback: stub with DB metadata
	if instance == null:
		instance = AbilityBase.new()
		instance.ability_name = ab.get("name", id)
		instance.description  = ab.get("description", "")
		instance.chakra_cost  = ab.get("chakra_cost", 20)
		instance.cooldown     = ab.get("cooldown", 5.0)
		instance.activation   = ab.get("activation", "instant")
		instance.icon_color   = ab.get("icon_color", Color("ffffff"))
	# Always stamp id so ability_menu and save system can track it
	instance.set_meta("_ability_id", id)
	instance.ability_id = id
	return instance
