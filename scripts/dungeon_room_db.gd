extends RefCounted

# ============================================================
# DUNGEON ROOM DATABASE
# Defines room types, point budgets, and special room configs
# ============================================================

enum RoomType {
	COMBAT,
	ELITE,
	MINIBOSS,
	BOSS,
	SHOP,
	REST,
	START,
	TREASURE,
}

# Room definitions per type
const ROOM_CONFIGS = {
	RoomType.START: {
		"label":       "Entrance",
		"points":       0,
		"weight":       0,    # never randomly selected
		"safe":         true,
	},
	RoomType.COMBAT: {
		"label":       "Combat",
		"points":       12,
		"weight":       60,
		"safe":         false,
	},
	RoomType.ELITE: {
		"label":       "Elite",
		"points":       20,
		"weight":       20,
		"safe":         false,
	},
	RoomType.MINIBOSS: {
		"label":       "Miniboss",
		"points":       0,    # uses fixed spawn
		"weight":       10,
		"safe":         false,
	},
	RoomType.SHOP: {
		"label":       "Shop",
		"points":       0,
		"weight":       8,
		"safe":         true,
	},
	RoomType.REST: {
		"label":       "Rest",
		"points":       0,
		"weight":       8,
		"safe":         true,
	},
	RoomType.BOSS: {
		"label":       "Boss",
		"points":       0,    # fixed boss spawn
		"weight":       0,    # never randomly selected — always last
		"safe":         false,
	},
	RoomType.TREASURE: {
		"label":       "Treasure",
		"points":       0,
		"weight":       0,    # never randomly selected — placed by generator after boss
		"safe":         true,
	},
}

# Point costs per enemy tier — used by generator to fill combat rooms
const ENEMY_COSTS = {
	"base":     4,
	"elite":    8,
	"miniboss": 20,
}

static func get_room_config(type: int) -> Dictionary:
	return ROOM_CONFIGS.get(type, {})

static func weighted_random_type(exclude: Array = []) -> int:
	var pool = []
	for type in ROOM_CONFIGS:
		if type in exclude:
			continue
		var cfg = ROOM_CONFIGS[type]
		if cfg.get("weight", 0) > 0:
			for i in range(cfg["weight"]):
				pool.append(type)
	if pool.is_empty():
		return RoomType.COMBAT
	return pool[randi() % pool.size()]

# ── Door reward types ─────────────────────────────────────────
# Assigned to room connections at generation time.
# The door the player chooses determines the reward in the next room.
enum RewardType {
	BOON,       # 3-card boon selection
	UPGRADE,    # 3-card upgrade selection (improve existing boon)
	REST,       # Heal HP + Chakra
	SHOP,       # Spend currency
	GOLD,       # Gold bag mobs to attack
	RESOURCES,  # Crafting resource mobs to attack
	BOSS,       # Boss room — skull door, no reward
}

const REWARD_LABELS = {
	RewardType.BOON:      "Boon Room",
	RewardType.UPGRADE:   "Upgrade Room",
	RewardType.REST:      "Rest Room",
	RewardType.SHOP:      "Shop Room",
	RewardType.GOLD:      "Treasure Room",
	RewardType.RESOURCES: "Resource Room",
	RewardType.BOSS:      "Boss",
}

# Symbol colors per reward type
const REWARD_COLORS = {
	RewardType.BOON:      Color(0.65, 0.20, 0.90),  # purple
	RewardType.UPGRADE:   Color(0.20, 0.50, 1.00),  # blue
	RewardType.REST:      Color(0.25, 0.90, 0.40),  # green
	RewardType.SHOP:      Color(1.00, 0.88, 0.30),  # gold
	RewardType.GOLD:      Color(1.00, 0.75, 0.10),  # amber
	RewardType.RESOURCES: Color(0.55, 0.75, 0.35),  # olive
	RewardType.BOSS:      Color(0.90, 0.15, 0.15),  # red
}

# Door count ranges per dungeon min_level
static func doors_for_level(min_level: int) -> Array:
	if min_level >= 15:
		return [2, 3]   # 2 or 3 doors
	elif min_level >= 5:
		return [1, 2]   # 1 or 2 doors
	else:
		return [1, 2]   # 1 or 2 doors (level 1 dungeons)

# Weighted random reward type for a given floor position
# Boss always assigned by generator — this is for non-boss rooms only
static func random_reward(rng: RandomNumberGenerator) -> int:
	var pool = [
		RewardType.BOON,      RewardType.BOON,      RewardType.BOON,
		RewardType.UPGRADE,   RewardType.UPGRADE,
		RewardType.REST,      RewardType.REST,
		RewardType.SHOP,
		RewardType.GOLD,      RewardType.GOLD,
		RewardType.RESOURCES,
	]
	return pool[rng.randi() % pool.size()]
