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
