extends Node

# ══════════════════════════════════════════════════════════════════════════════
# ItemDB — single source of truth for every item in the game.
#
# HOW TO ADD A NEW ITEM:
#   1. Add an entry to _ITEMS below.
#   2. That's it. Inventory, equip panel, hotbar, transmog, server sync,
#      and save/load all read from this registry automatically.
#
# REQUIRED fields for every item:
#   id          String   — unique snake_case identifier
#   name        String   — display name
#   stackable   bool
#   quantity    int      — starting stack size (usually 1)
#
# OPTIONAL fields (omit = sensible default):
#   icon_path   String   — res:// path to icon texture (idle_down frame works well)
#   icon_offset Vector2  — pixel nudge for inventory display (default ZERO)
#   equip_slot  String   — "weapon"|"head"|"chest"|"legs"|"shoes"|"accessory"
#                          omit for non-equippable items
#   sprite_folder String — res:// folder containing walk/idle animation frames
#                          omit if item has no body layer (e.g. consumables)
#   stat_bonuses Dict    — {hp, str, dex, int, chakra} all default 0 if omitted
#   min_rank    String   — "Genin"|"Chunin"|"Special Jonin"|"Jonin"|"ANBU"|"Kage"
#                          omit or "" for no rank requirement
#   tint        Color    — runtime tint applied by transmog; DO NOT set here,
#                          it is written by the tailor and persisted in save data
#
# TINT PERSISTENCE RULES (handled automatically, do not touch):
#   - Saved as [r,g,b,a] array in JSON by database.gd
#   - Loaded back as Color by database.gd
#   - Applied to equip layers by equip_panel._apply_equip_visuals()
#   - Applied to icons by inventory._refresh_slot(), equip_panel._refresh_slot(),
#     hotbar._refresh_slot(), and tailor_npc picker
# ══════════════════════════════════════════════════════════════════════════════

const _ITEMS: Dictionary = {

	# ── Shirts ────────────────────────────────────────────────────────────────
	"shirt1": {
		"id":           "shirt1",
		"name":         "Shirt1",
		"stackable":    false,
		"quantity":     1,
		"icon_path":    "res://sprites/player/Shirts/Shirt1/idle_down.png",
		"icon_offset":  Vector2(0, 0),
		"equip_slot":   "chest",
		"transmog":     true,
		"sprite_folder":"res://sprites/player/Shirts/Shirt1/",
		"stat_bonuses": {},
	},

	# ── Pants ─────────────────────────────────────────────────────────────────
	"pants1": {
		"id":           "pants1",
		"name":         "Pants1",
		"stackable":    false,
		"quantity":     1,
		"icon_path":    "res://sprites/player/Pants/Pants1/idle_down_0.png",
		"icon_offset":  Vector2(0, -8),
		"equip_slot":   "legs",
		"transmog":     true,
		"sprite_folder":"res://sprites/player/Pants/Pants1/",
		"stat_bonuses": {},
	},

	# ── Weapons ───────────────────────────────────────────────────────────────
	# "kunai1": {
	"kunai1": {
		"id":           "kunai1",
		"name":         "Kunai",
		"stackable":    false,
		"quantity":     1,
		"icon_path":    "res://sprites/player/Weapons/Kunai/idle_down_0.png",
		"icon_offset":  Vector2(0, 0),
		"equip_slot":   "weapon",
		"transmog":     false,
		"sprite_folder":"res://sprites/player/Weapons/Kunai/",
		"stat_bonuses": {"strength": 3},
		"min_rank":     "Academy Student",
	},

	# ── Head ──────────────────────────────────────────────────────────────────
	# "headband1": {
	# 	"id":           "headband1",
	# 	"name":         "Headband",
	# 	"stackable":    false,
	# 	"quantity":     1,
	# 	"icon_path":    "res://sprites/player/Hats/Headband1/idle_down.png",
	# 	"icon_offset":  Vector2(0, 4),
	# 	"equip_slot":   "head",
	# 	"sprite_folder":"res://sprites/player/Hats/Headband1/",
	# 	"stat_bonuses": {},
	# },

	# ── Shoes ─────────────────────────────────────────────────────────────────
	# ── Accessories ───────────────────────────────────────────────────────────
	# ── Crafting Materials / Mission Items ────────────────────────────────────
	"wolf_fang": {
		"id":           "wolf_fang",
		"name":         "Wolf Fang",
		"stackable":    true,
		"quantity":     1,
		"icon_path":    "res://sprites/icons/wolf_fang.png",
		"icon_offset":  Vector2(0, 0),
		"use_effect":   {},
	},
	"wolf_pelt": {
		"id":           "wolf_pelt",
		"name":         "Wolf Pelt",
		"stackable":    true,
		"quantity":     1,
		"icon_path":    "res://sprites/icons/wolf_pelt.png",
		"icon_offset":  Vector2(0, 0),
		"use_effect":   {},
	},
	"mission_letter": {
		"id":           "mission_letter",
		"name":         "Mission Letter",
		"stackable":    false,
		"quantity":     1,
		"icon_path":    "res://sprites/icons/letter.png",
		"icon_offset":  Vector2(0, 0),
		"use_effect":   {},
	},
	# ── Consumables (no equip_slot) ───────────────────────────────────────────
	# use_effect keys:
	#   type: "heal_hp" | "cure_poison" (more added later)
	#   amount: int (for heal effects)
	"hp_potion": {
		"id":           "hp_potion",
		"name":         "HP Potion",
		"stackable":    true,
		"quantity":     1,
		"icon_path":    "res://sprites/player/Items/hp_potion_small.png",
		"icon_offset":  Vector2(0, 0),
		"icon_scale":   0.7,
		"use_effect":   {"type": "heal_hp", "amount": 50},
		"min_rank":     "Academy Student",
	},
	"antidote": {
		"id":           "antidote",
		"name":         "Antidote",
		"stackable":    true,
		"quantity":     1,
		"icon_path":    "res://sprites/icons/antidote.png",
		"icon_offset":  Vector2(0, 0),
		"use_effect":   {"type": "cure_poison"},
		"min_rank":     "Academy Student",
	},
	# ── Ability Scrolls (Hyuga) ───────────────────────────────────────────────
	# Dropped by dungeons — teach the player an ability permanently on use.
	"scroll_gentle_fist": {
		"id": "scroll_gentle_fist", "name": "Gentle Fist Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_taijutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "gentle_fist"},
		"min_rank": "Academy Student",
	},
	"scroll_byakugan": {
		"id": "scroll_byakugan", "name": "Byakugan Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "byakugan"},
	},
	"scroll_rotation": {
		"id": "scroll_rotation", "name": "Rotation Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "rotation"},
		"min_rank": "Genin",
	},
	"scroll_64_palms": {
		"id": "scroll_64_palms", "name": "64 Palms Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "64_palms"},
		"min_rank": "Chunin",
	},
	"scroll_air_palm": {
		"id": "scroll_air_palm", "name": "Air Palm Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "air_palm"},
	},

	# ── Ability Scrolls (Nara) ────────────────────────────────────────────────
	"scroll_shadow_possession": {
		"id": "scroll_shadow_possession", "name": "Shadow Possession Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "shadow_possession"},
		"min_rank": "Academy Student",
	},
	"scroll_shadow_strangle": {
		"id": "scroll_shadow_strangle", "name": "Shadow Strangle Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "shadow_strangle"},
		"min_rank": "Academy Student",
	},
	"scroll_shadow_pull": {
		"id": "scroll_shadow_pull", "name": "Shadow Pull Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "shadow_pull"},
		"min_rank": "Genin",
	},
	"scroll_mass_shadow": {
		"id": "scroll_mass_shadow", "name": "Mass Shadow Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "mass_shadow"},
		"min_rank": "Special Jonin",
	},

	# ── Ability Scrolls (Aburame) ─────────────────────────────────────────────
	"scroll_bug_swarm": {
		"id": "scroll_bug_swarm", "name": "Bug Swarm Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "bug_swarm"},
		"min_rank": "Academy Student",
	},
	"scroll_parasite": {
		"id": "scroll_parasite", "name": "Parasite Insect Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "parasite"},
		"min_rank": "Genin",
	},
	"scroll_insect_cocoon": {
		"id": "scroll_insect_cocoon", "name": "Insect Cocoon Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "insect_cocoon"},
		"min_rank": "Genin",
	},
	"scroll_hive_burst": {
		"id": "scroll_hive_burst", "name": "Hive Burst Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "hive_burst"},
		"min_rank": "Chunin",
	},
	"scroll_bug_cloak": {
		"id": "scroll_bug_cloak", "name": "Bug Cloak Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "bug_cloak"},
		"min_rank": "Chunin",
	},

	# ── Ability Scrolls (Clay) ────────────────────────────────────────────────
	"scroll_c1_spiders": {
		"id": "scroll_c1_spiders", "name": "C1 Clay Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "c1_spiders"},
		"min_rank": "Academy Student",
	},
	"scroll_c2_dragon": {
		"id": "scroll_c2_dragon", "name": "C2 Clay Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "c2_dragon"},
		"min_rank": "Chunin",
	},
	"scroll_c3_bomb": {
		"id": "scroll_c3_bomb", "name": "C3 Clay Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "c3_bomb"},
		"min_rank": "Special Jonin",
	},
	"scroll_c4_karura": {
		"id": "scroll_c4_karura", "name": "C4 Karura Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "c4_karura"},
		"min_rank": "Jonin",
	},
	"scroll_katsu": {
		"id": "scroll_katsu", "name": "Katsu Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_ninjutsu.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "katsu"},
		"min_rank": "Academy Student",
	},

	# ── Ability Scrolls (Fire) ────────────────────────────────────────────────
	"scroll_fireball": {
		"id": "scroll_fireball", "name": "Fireball Jutsu Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_fire.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "fireball"},
		"min_rank": "Academy Student",
	},
	"scroll_phoenix_flower": {
		"id": "scroll_phoenix_flower", "name": "Phoenix Flower Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_fire.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "phoenix_flower"},
		"min_rank": "Genin",
	},
	"scroll_fire_wall": {
		"id": "scroll_fire_wall", "name": "Fire Wall Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_fire.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "fire_wall"},
		"min_rank": "Chunin",
	},

	# ── Ability Scrolls (Lightning) ───────────────────────────────────────────
	"scroll_lightning_bolt": {
		"id": "scroll_lightning_bolt", "name": "Lightning Bolt Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_lightning.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "lightning_bolt"},
		"min_rank": "Academy Student",
	},
	"scroll_chidori": {
		"id": "scroll_chidori", "name": "Chidori Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_lightning.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "chidori"},
		"min_rank": "Chunin",
	},
	"scroll_lightning_field": {
		"id": "scroll_lightning_field", "name": "Lightning Field Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_lightning.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "lightning_field"},
		"min_rank": "Special Jonin",
	},

	# ── Ability Scrolls (Earth) ───────────────────────────────────────────────
	"scroll_earth_wall": {
		"id": "scroll_earth_wall", "name": "Earth Wall Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_earth.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "earth_wall"},
		"min_rank": "Academy Student",
	},
	"scroll_mud_river": {
		"id": "scroll_mud_river", "name": "Mud River Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_earth.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "mud_river"},
		"min_rank": "Genin",
	},
	"scroll_earth_spikes": {
		"id": "scroll_earth_spikes", "name": "Earth Spikes Scroll",
		"stackable": false, "quantity": 1,
		"icon_path": "res://sprites/player/Items/scroll_earth.png",
		"use_effect": {"type": "unlock_ability", "ability_id": "earth_spikes"},
		"min_rank": "Chunin",
	},

}

# ── Public API ────────────────────────────────────────────────────────────────

func get_item(id: String) -> Dictionary:
	# Returns a fresh copy of the item definition.
	# "tint" is intentionally NOT in the definition — it is runtime state
	# set by the tailor and stored in save data only.
	if not _ITEMS.has(id):
		push_error("[ItemDB] Unknown item id: '%s'" % id)
		return {}
	return _ITEMS[id].duplicate(true)

func get_all_ids() -> Array:
	return _ITEMS.keys()

func exists(id: String) -> bool:
	return _ITEMS.has(id)

# Restore runtime tint onto a freshly-fetched item from save data.
# Call this when loading equipped or inventory items from a save file.
func apply_saved_tint(item: Dictionary, saved_tint) -> Dictionary:
	if saved_tint is Color:
		item["tint"] = saved_tint
	elif saved_tint is Array and saved_tint.size() == 4:
		item["tint"] = Color(saved_tint[0], saved_tint[1], saved_tint[2], saved_tint[3])
	return item
