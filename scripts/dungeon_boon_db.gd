extends RefCounted

# ============================================================
# DUNGEON BOON DATABASE
# Clay Clan — all rarities
# Boons last for the duration of a dungeon run only.
# ============================================================

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES = {
	Rarity.COMMON:    "Common",
	Rarity.UNCOMMON:  "Uncommon",
	Rarity.RARE:      "Rare",
	Rarity.EPIC:      "Epic",
	Rarity.LEGENDARY: "Legendary",
}

const RARITY_COLORS = {
	Rarity.COMMON:    Color(0.75, 0.75, 0.75),  # grey
	Rarity.UNCOMMON:  Color(0.30, 0.85, 0.30),  # green
	Rarity.RARE:      Color(0.20, 0.50, 1.00),  # blue
	Rarity.EPIC:      Color(0.65, 0.20, 0.90),  # purple
	Rarity.LEGENDARY: Color(1.00, 0.65, 0.10),  # orange-gold
}

# Rarity weights per dungeon min_level
# Format: { min_level: { rarity: weight } }
const RARITY_WEIGHTS_BY_LEVEL = {
	1:  { Rarity.COMMON: 60, Rarity.UNCOMMON: 28, Rarity.RARE: 10, Rarity.EPIC: 2,  Rarity.LEGENDARY: 0  },
	5:  { Rarity.COMMON: 45, Rarity.UNCOMMON: 28, Rarity.RARE: 18, Rarity.EPIC: 7,  Rarity.LEGENDARY: 2  },
	10: { Rarity.COMMON: 30, Rarity.UNCOMMON: 28, Rarity.RARE: 24, Rarity.EPIC: 13, Rarity.LEGENDARY: 5  },
	20: { Rarity.COMMON: 15, Rarity.UNCOMMON: 25, Rarity.RARE: 28, Rarity.EPIC: 22, Rarity.LEGENDARY: 10 },
}

const BOONS: Dictionary = {

	# ── COMMON ───────────────────────────────────────────────────────────────

	"c1_cooldown_a": {
		"name":     "Quick Hands",
		"desc":     "C1 Spider cooldown -0.3s",
		"rarity":   Rarity.COMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c1_cooldown_flat",
		"value":    -0.3,
		"icon_color": Color(0.78, 0.66, 0.43),
	},
	"c1_damage_a": {
		"name":     "Volatile Clay",
		"desc":     "C1 Spider damage +8",
		"rarity":   Rarity.COMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c1_damage_flat",
		"value":    8,
		"icon_color": Color(0.78, 0.66, 0.43),
	},
	"c1_speed_a": {
		"name":     "Eager Spider",
		"desc":     "C1 Spider travel speed +20%",
		"rarity":   Rarity.COMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c1_speed_mult",
		"value":    0.20,
		"icon_color": Color(0.78, 0.66, 0.43),
	},
	"c2_cooldown_a": {
		"name":     "Patient Sculptor",
		"desc":     "C2 Owl cooldown -2s",
		"rarity":   Rarity.COMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c2_cooldown_flat",
		"value":    -2.0,
		"icon_color": Color(0.91, 0.78, 0.59),
	},
	"c3_cooldown_a": {
		"name":     "Rapid Detonation",
		"desc":     "C3 cooldown -5s",
		"rarity":   Rarity.COMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c3_cooldown_flat",
		"value":    -5.0,
		"icon_color": Color(0.78, 0.31, 0.04),
	},
	"chakra_surge": {
		"name":     "Chakra Surge",
		"desc":     "Max Chakra +75",
		"rarity":   Rarity.COMMON,
		"clan":     "any",
		"type":     "stat",
		"stat":     "max_chakra",
		"value":    75,
		"icon_color": Color(0.18, 0.55, 0.48),
	},
	"iron_body": {
		"name":     "Iron Body",
		"desc":     "Max HP +50",
		"rarity":   Rarity.COMMON,
		"clan":     "any",
		"type":     "stat",
		"stat":     "max_hp",
		"value":    50,
		"icon_color": Color(0.80, 0.20, 0.07),
	},

	# ── UNCOMMON ─────────────────────────────────────────────────────────────

	"c1_range_a": {
		"name":     "Long Fuse",
		"desc":     "C1 Spider range +25%",
		"rarity":   Rarity.UNCOMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c1_range_mult",
		"value":    0.25,
		"icon_color": Color(0.78, 0.66, 0.43),
	},
	"c2_orbit_duration": {
		"name":     "Persistent Owl",
		"desc":     "C2 Owl orbits for +2 extra seconds",
		"rarity":   Rarity.UNCOMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c2_orbit_duration_flat",
		"value":    2.0,
		"icon_color": Color(0.91, 0.78, 0.59),
	},
	"c2_drop_rate": {
		"name":     "Eager Nester",
		"desc":     "C2 Owl drops spiders 30% faster",
		"rarity":   Rarity.UNCOMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c2_drop_interval_mult",
		"value":    -0.30,
		"icon_color": Color(0.91, 0.78, 0.59),
	},
	"c4_spread": {
		"name":     "Wide Bloom",
		"desc":     "C4 fires +60 micro-projectiles",
		"rarity":   Rarity.UNCOMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c4_count_flat",
		"value":    60,
		"icon_color": Color(1.00, 0.27, 0.00),
	},
	"all_damage_a": {
		"name":     "Killing Intent",
		"desc":     "All clay damage +12%",
		"rarity":   Rarity.UNCOMMON,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "clay_dmg_mult",
		"value":    0.12,
		"icon_color": Color(0.80, 0.20, 0.07),
	},
	"chakra_efficiency": {
		"name":     "Chakra Efficiency",
		"desc":     "All ability costs -15%",
		"rarity":   Rarity.UNCOMMON,
		"clan":     "any",
		"type":     "stat",
		"stat":     "chakra_cost_mult",
		"value":    -0.15,
		"icon_color": Color(0.18, 0.55, 0.48),
	},

	# ── RARE ─────────────────────────────────────────────────────────────────

	"c1_pierce": {
		"name":     "Burrowing Spider",
		"desc":     "C1 Spiders pass through the first enemy they hit",
		"rarity":   Rarity.RARE,
		"clan":     "clay",
		"type":     "passive",
		"passive":  "c1_pierce",
		"icon_color": Color(0.78, 0.66, 0.43),
	},
	"c2_explosion_dmg": {
		"name":     "Final Screech",
		"desc":     "C2 Owl explosion damage +50%",
		"rarity":   Rarity.RARE,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c2_explosion_mult",
		"value":    0.50,
		"icon_color": Color(0.91, 0.78, 0.59),
	},
	"c3_radius": {
		"name":     "Grand Design",
		"desc":     "C3 explosion radius +40%",
		"rarity":   Rarity.RARE,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c3_radius_mult",
		"value":    0.40,
		"icon_color": Color(0.78, 0.31, 0.04),
	},
	"c1_slow": {
		"name":     "Sticky Clay",
		"desc":     "C1 Spiders apply a 30% slow for 2 seconds on hit",
		"rarity":   Rarity.RARE,
		"clan":     "clay",
		"type":     "passive",
		"passive":  "c1_slow",
		"icon_color": Color(0.78, 0.66, 0.43),
	},
	"c4_damage": {
		"name":     "Volatile Swarm",
		"desc":     "C4 particle damage +25%",
		"rarity":   Rarity.RARE,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c4_dmg_mult",
		"value":    0.25,
		"icon_color": Color(1.00, 0.27, 0.00),
	},
	"undying": {
		"name":     "Undying",
		"desc":     "Once per floor, survive a killing blow at 1 HP",
		"rarity":   Rarity.RARE,
		"clan":     "any",
		"type":     "passive",
		"passive":  "deathsave",
		"icon_color": Color(0.80, 0.20, 0.07),
	},
	"rapid_dash": {
		"name":     "Rapid Dash",
		"desc":     "Gain 1 extra dash charge",
		"rarity":   Rarity.RARE,
		"clan":     "any",
		"type":     "ability",
		"ability":  "dash_charges",
		"value":    1,
		"icon_color": Color(0.27, 0.55, 0.24),
	},

	# ── EPIC ─────────────────────────────────────────────────────────────────

	"c2_homing": {
		"name":     "Predator's Instinct",
		"desc":     "C2 Owl tracks the nearest enemy during its dash phase",
		"rarity":   Rarity.EPIC,
		"clan":     "clay",
		"type":     "passive",
		"passive":  "c2_homing_dash",
		"icon_color": Color(0.91, 0.78, 0.59),
	},
	"c3_double_det": {
		"name":     "Chain Reaction",
		"desc":     "C3 detonates twice — second blast at 60% damage",
		"rarity":   Rarity.EPIC,
		"clan":     "clay",
		"type":     "passive",
		"passive":  "c3_double_det",
		"icon_color": Color(0.78, 0.31, 0.04),
	},
	"c4_radius": {
		"name":     "Blanket the Sky",
		"desc":     "C4 explosion radius +40%",
		"rarity":   Rarity.EPIC,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c4_radius_mult",
		"value":    0.40,
		"icon_color": Color(1.00, 0.27, 0.00),
	},
	"berserker": {
		"name":     "Berserker",
		"desc":     "Below 30% HP: all damage +50%, take +25% damage",
		"rarity":   Rarity.EPIC,
		"clan":     "any",
		"type":     "passive",
		"passive":  "berserker",
		"icon_color": Color(0.80, 0.31, 0.00),
	},
	"cursed_chakra": {
		"name":     "Cursed Chakra",
		"desc":     "Clay damage +40% but chakra costs +20%",
		"rarity":   Rarity.EPIC,
		"clan":     "clay",
		"type":     "double",
		"stats":    [["clay_dmg_mult", 0.40], ["chakra_cost_mult", 0.20]],
		"icon_color": Color(0.55, 0.18, 0.78),
	},

	# ── LEGENDARY ────────────────────────────────────────────────────────────

	"double_owl": {
		"name":     "Twin Sculptors",
		"desc":     "C2 fires 2 Owls simultaneously",
		"rarity":   Rarity.LEGENDARY,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c2_owl_count",
		"value":    2,
		"icon_color": Color(1.00, 0.65, 0.10),
	},
	"spider_cluster": {
		"name":     "Swarm Release",
		"desc":     "C1 fires a cluster of 3 spiders per cast",
		"rarity":   Rarity.LEGENDARY,
		"clan":     "clay",
		"type":     "stat",
		"stat":     "c1_spider_count",
		"value":    3,
		"icon_color": Color(1.00, 0.65, 0.10),
	},
	"c4_double": {
		"name":     "Karura's Wrath",
		"desc":     "C4 detonates twice — annihilate everything",
		"rarity":   Rarity.LEGENDARY,
		"clan":     "clay",
		"type":     "passive",
		"passive":  "c4_double_det",
		"icon_color": Color(1.00, 0.65, 0.10),
	},
	"c3_invisible": {
		"name":     "Phantom Bomb",
		"desc":     "C3 becomes invisible until it detonates",
		"rarity":   Rarity.LEGENDARY,
		"clan":     "clay",
		"type":     "passive",
		"passive":  "c3_invisible",
		"icon_color": Color(1.00, 0.65, 0.10),
	},
}

const BOONS_OFFERED = 3

static func get_boon(id: String) -> Dictionary:
	return BOONS.get(id, {})

static func get_random_boons(count: int, already_held: Array = [], dungeon_level: int = 1) -> Array:
	# Get weight table for this dungeon level (use highest table <= level)
	var weights = RARITY_WEIGHTS_BY_LEVEL[1]
	for lvl in RARITY_WEIGHTS_BY_LEVEL:
		if dungeon_level >= lvl:
			weights = RARITY_WEIGHTS_BY_LEVEL[lvl]

	# Count stacks for cap checking
	var held_counts: Dictionary = {}
	for id in already_held:
		held_counts[id] = held_counts.get(id, 0) + 1

	var pool: Array = []
	for id in BOONS:
		if id in already_held:
			# Allow unlimited stacking for max_hp and max_chakra boons
			var boon = BOONS[id]
			var stat = boon.get("stat", "")
			if stat not in ["max_hp", "max_chakra"]:
				continue  # skip already-held boons (they go in upgrade screen)
			# Fall through for max_hp/max_chakra — always available
		var stack_count = held_counts.get(id, 0)
		var boon = BOONS[id]
		var stat = boon.get("stat", "")
		# Skip boons at max stacks unless they have unlimited stacking
		if stat not in ["max_hp", "max_chakra"] and stack_count >= MAX_BOON_STACKS:
			continue
		var w = weights.get(boon.get("rarity", Rarity.COMMON), 5)
		for _i in range(w):
			pool.append(id)

	pool.shuffle()
	var result: Array = []
	var seen:   Dictionary = {}
	for id in pool:
		if id not in seen:
			seen[id] = true
			result.append(id)
		if result.size() >= count:
			break
	return result

static func rarity_name(r: int) -> String:
	return RARITY_NAMES.get(r, "Common")

static func rarity_color(r: int) -> Color:
	return RARITY_COLORS.get(r, Color(0.75, 0.75, 0.75))

# Returns boons the player already holds, offered for stacking/upgrading.
# Stackable boons grant their bonus again. Returns empty if player holds nothing.
const MAX_BOON_STACKS = 5

static func get_upgrade_boons(count: int, already_held: Array) -> Array:
	if already_held.is_empty():
		return []
	# Count how many times each boon is held
	var held_counts: Dictionary = {}
	for id in already_held:
		held_counts[id] = held_counts.get(id, 0) + 1

	# Only offer stackable boons the player holds that are under the stack cap
	var stackable = []
	for id in held_counts:
		if held_counts[id] >= MAX_BOON_STACKS:
			continue
		var boon = BOONS.get(id, {})
		if boon.get("type", "") in ["stat", "ability", "double"]:
			stackable.append(id)
	if stackable.is_empty():
		return []
	stackable.shuffle()
	var result = []
	var seen   = {}
	for id in stackable:
		if id not in seen:
			seen[id] = true
			result.append(id)
		if result.size() >= count:
			break
	return result
