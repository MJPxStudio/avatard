extends CanvasLayer

# ============================================================
# DUNGEON BOON STATUS UI
# Tab-toggleable overlay showing all abilities affected by
# currently held boons, with hover tooltips showing
# accumulated stat changes.
# ============================================================

const BoonDB   = preload("res://scripts/dungeon_boon_db.gd")

# Inline ability display data — avoids needing an AbilityDB instance
const ABILITY_DISPLAY = {
	"c1_spiders": { "name": "C1: Clay Spiders", "icon_color": Color("c8a84a"), "short": "C1" },
	"c2_dragon":  { "name": "C2: Clay Dragon",  "icon_color": Color("e0a020"), "short": "C2" },
	"c3_bomb":    { "name": "C3: Giant Bomb",    "icon_color": Color("e86800"), "short": "C3" },
	"c4_karura":  { "name": "C4: Karura",        "icon_color": Color("ff3300"), "short": "C4" },
}

# ── Ability → boon stat mapping ───────────────────────────────
# Maps ability_id → list of stat keys that affect it
const ABILITY_STAT_MAP = {
	"c1_spiders": [
		"c1_damage_flat", "c1_speed_mult", "c1_range_mult",
		"c1_cooldown_flat", "c1_spider_count",
		"clay_dmg_mult", "chakra_cost_mult",
	],
	"c2_dragon": [
		"c2_cooldown_flat", "c2_orbit_duration_flat",
		"c2_drop_interval_mult", "c2_explosion_mult", "c2_owl_count",
		"clay_dmg_mult", "chakra_cost_mult",
	],
	"c3_bomb": [
		"c3_cooldown_flat", "c3_radius_mult",
		"clay_dmg_mult", "chakra_cost_mult",
	],
	"c4_karura": [
		"c4_count_flat", "c4_dmg_mult", "c4_radius_mult",
		"clay_dmg_mult", "chakra_cost_mult",
	],
}

# Human-readable descriptions for each stat key
const STAT_LABELS = {
	"c1_damage_flat":        "Spider damage",
	"c1_speed_mult":         "Spider speed",
	"c1_range_mult":         "Spider range",
	"c1_cooldown_flat":      "Cooldown",
	"c1_spider_count":       "Spiders per cast",
	"c2_cooldown_flat":      "Cooldown",
	"c2_orbit_duration_flat":"Orbit duration",
	"c2_drop_interval_mult": "Spider drop rate",
	"c2_explosion_mult":     "Explosion damage",
	"c2_owl_count":          "Owls per cast",
	"c3_cooldown_flat":      "Cooldown",
	"c3_radius_mult":        "Blast radius",
	"c4_count_flat":         "Projectile count",
	"c4_dmg_mult":           "Particle damage",
	"c4_radius_mult":        "Explosion radius",
	"clay_dmg_mult":         "All clay damage",
	"chakra_cost_mult":      "Chakra cost",
}

# Format value with sign and unit
const STAT_FORMAT = {
	"c1_damage_flat":        [true,  false, ""],      # additive int
	"c1_speed_mult":         [false, true,  ""],      # percent mult
	"c1_range_mult":         [false, true,  ""],
	"c1_cooldown_flat":      [true,  false, "s"],
	"c1_spider_count":       [false, false, ""],      # absolute value
	"c2_cooldown_flat":      [true,  false, "s"],
	"c2_orbit_duration_flat":[true,  false, "s"],
	"c2_drop_interval_mult": [false, true,  ""],
	"c2_explosion_mult":     [false, true,  ""],
	"c2_owl_count":          [false, false, ""],
	"c3_cooldown_flat":      [true,  false, "s"],
	"c3_radius_mult":        [false, true,  ""],
	"c4_count_flat":         [true,  false, ""],
	"c4_dmg_mult":           [false, true,  ""],
	"c4_radius_mult":        [false, true,  ""],
	"clay_dmg_mult":         [false, true,  ""],
	"chakra_cost_mult":      [false, true,  ""],
}

# ── State ─────────────────────────────────────────────────────
var _held_boons:      Array      = []   # boon ids held this run
var _accum_stats:     Dictionary = {}   # stat_key -> accumulated value
var _passives:        Array      = []   # passive ids

var _open:            bool       = false
var _overlay:         ColorRect  = null
var _panel:           Panel      = null
var _icon_nodes:      Array      = []
var _tooltip:         Panel      = null
var _tooltip_lbl:     Label      = null

# ── Setup ─────────────────────────────────────────────────────

func _ready() -> void:
	layer   = 52
	visible = false
	_build_ui()
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		if not net.dungeon_boon_chosen_received.is_connected(_on_boon_chosen):
			net.dungeon_boon_chosen_received.connect(_on_boon_chosen)

func _build_ui() -> void:
	# Darkened overlay
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.72)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	# Main panel
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -300; _panel.offset_right  = 300
	_panel.offset_top    = -200; _panel.offset_bottom = 200
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.03, 0.07, 0.96)
	ps.set_corner_radius_all(10)
	ps.set_border_width_all(1)
	ps.border_color = Color(0.28, 0.20, 0.42)
	_panel.add_theme_stylebox_override("panel", ps)
	add_child(_panel)

	# Title
	var title = Label.new()
	title.text = "Active Boon Effects"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 14; title.offset_bottom = 36
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.40))
	_panel.add_child(title)

	var hint = Label.new()
	hint.text = "Hover an ability icon to see changes  ·  [Tab] to close"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top    = -26; hint.offset_bottom = -8
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.45, 0.42, 0.55))
	_panel.add_child(hint)

	# Tooltip (hidden by default)
	_tooltip = Panel.new()
	_tooltip.visible = false
	_tooltip.z_index = 10
	var ts = StyleBoxFlat.new()
	ts.bg_color = Color(0.06, 0.05, 0.10, 0.97)
	ts.set_corner_radius_all(6)
	ts.set_border_width_all(1)
	ts.border_color = Color(0.40, 0.30, 0.60)
	ts.content_margin_left = 10; ts.content_margin_right  = 10
	ts.content_margin_top  = 8;  ts.content_margin_bottom = 8
	_tooltip.add_theme_stylebox_override("panel", ts)
	add_child(_tooltip)

	_tooltip_lbl = Label.new()
	_tooltip_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tooltip_lbl.add_theme_font_size_override("font_size", 9)
	_tooltip_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92))
	_tooltip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip.add_child(_tooltip_lbl)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle()
			get_viewport().set_input_as_handled()

func _toggle() -> void:
	_open = not _open
	if _open:
		_refresh()
		visible = true
	else:
		visible = false
		_tooltip.visible = false

# ── Data tracking ─────────────────────────────────────────────

func _on_boon_chosen(boon_id: String, _boon_name: String) -> void:
	_held_boons.append(boon_id)
	var boon = BoonDB.get_boon(boon_id)
	if boon.is_empty():
		return
	var type = boon.get("type", "")
	match type:
		"stat":
			_accumulate(boon.get("stat", ""), boon.get("value", 0))
		"ability":
			_accumulate(boon.get("ability", ""), boon.get("value", 0))
		"passive":
			_passives.append(boon.get("passive", ""))
		"double":
			for pair in boon.get("stats", []):
				_accumulate(pair[0], pair[1])

func _accumulate(stat: String, value) -> void:
	if stat == "":
		return
	_accum_stats[stat] = _accum_stats.get(stat, 0) + value

# ── UI rebuild ────────────────────────────────────────────────

func _refresh() -> void:
	# Clear old icons
	for n in _icon_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_icon_nodes.clear()
	_tooltip.visible = false

	# Find which abilities have at least one active boon stat
	var affected: Array = []
	for ability_id in ABILITY_STAT_MAP:
		for stat in ABILITY_STAT_MAP[ability_id]:
			if _accum_stats.has(stat) or stat in _passives:
				if ability_id not in affected:
					affected.append(ability_id)
				break

	if affected.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No boon effects yet.\nChoose a Boon door to get started."
		empty_lbl.set_anchors_preset(Control.PRESET_CENTER)
		empty_lbl.offset_left = -200; empty_lbl.offset_right  = 200
		empty_lbl.offset_top  = -30;  empty_lbl.offset_bottom = 30
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 10)
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.42, 0.55))
		_panel.add_child(empty_lbl)
		_icon_nodes.append(empty_lbl)
		return

	# Lay icons out in a row centred in the panel
	var icon_size  = 64.0
	var gap        = 20.0
	var total_w    = affected.size() * icon_size + (affected.size() - 1) * gap
	var start_x    = -total_w / 2.0
	var icon_y     = -icon_size / 2.0

	for i in range(affected.size()):
		var ability_id = affected[i]
		var disp       = ABILITY_DISPLAY.get(ability_id, {})
		var icon_color = disp.get("icon_color", Color(0.5, 0.5, 0.5))
		var ab_name    = disp.get("name", ability_id)
		var ix = start_x + i * (icon_size + gap)
		_build_ability_icon(_panel, ability_id, ab_name, icon_color, Vector2(ix, icon_y), icon_size)

func _build_ability_icon(parent: Control, ability_id: String, ab_name: String, color: Color, pos: Vector2, size: float) -> void:
	var btn = Panel.new()
	btn.set_anchors_preset(Control.PRESET_CENTER)
	btn.offset_left   = pos.x
	btn.offset_right  = pos.x + size
	btn.offset_top    = pos.y
	btn.offset_bottom = pos.y + size

	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.95)
	bs.set_corner_radius_all(8)
	bs.set_border_width_all(2)
	bs.border_color = color
	btn.add_theme_stylebox_override("panel", bs)

	# Coloured circle fill
	var circle = ColorRect.new()
	circle.color = Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, 0.7)
	circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	circle.offset_left = 6; circle.offset_right  = -6
	circle.offset_top  = 6; circle.offset_bottom = -6
	circle.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.add_child(circle)

	# Ability initial letters as stand-in for icon
	var lbl = Label.new()
	lbl.text = _ability_short(ability_id)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.add_child(lbl)

	# Boon count badge
	var count = _count_boons_for_ability(ability_id)
	if count > 0:
		var badge = Label.new()
		badge.text = "+%d" % count
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -28; badge.offset_right  = -2
		badge.offset_top  = -18; badge.offset_bottom = -2
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.add_theme_font_size_override("font_size", 8)
		badge.add_theme_color_override("font_color", Color(1.0, 0.88, 0.30))
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.add_child(badge)

	# Hover tooltip connection
	btn.mouse_entered.connect(func(): _show_tooltip(ability_id, ab_name, color, btn))
	btn.mouse_exited.connect(func():  _tooltip.visible = false)

	parent.add_child(btn)
	_icon_nodes.append(btn)

func _show_tooltip(ability_id: String, ab_name: String, color: Color, icon: Panel) -> void:
	var stats    = ABILITY_STAT_MAP.get(ability_id, [])
	var lines: Array = ["[%s]" % ab_name, ""]

	var has_content = false
	for stat in stats:
		if _accum_stats.has(stat):
			var val   = _accum_stats[stat]
			var label = STAT_LABELS.get(stat, stat)
			var fmt   = STAT_FORMAT.get(stat, [true, false, ""])
			var text  = _format_stat(label, val, fmt[0], fmt[1], fmt[2])
			lines.append(text)
			has_content = true

	# Passives
	for passive in _passives:
		var passive_ability = _passive_ability(passive)
		if passive_ability == ability_id:
			lines.append("✦ " + _passive_label(passive))
			has_content = true

	if not has_content:
		lines.append("No changes yet.")

	_tooltip_lbl.text = "\n".join(lines)

	# Size tooltip to content
	var line_count = lines.size()
	var tw = 220.0
	var th = float(line_count) * 14.0 + 24.0
	_tooltip.size = Vector2(tw, th)
	_tooltip_lbl.size = _tooltip.size

	# Position above the icon, clamped to screen
	var vp_size = get_viewport().get_visible_rect().size
	var icon_global = icon.get_global_rect().position
	var tx = clamp(icon_global.x - tw / 2.0 + 32.0, 8.0, vp_size.x - tw - 8.0)
	var ty = clamp(icon_global.y - th - 10.0, 8.0, vp_size.y - th - 8.0)
	_tooltip.position = Vector2(tx, ty)
	_tooltip.visible  = true

func _format_stat(label: String, val, additive: bool, is_pct: bool, unit: String) -> String:
	if is_pct:
		var pct = val * 100.0
		var sign = "+" if pct >= 0 else ""
		return "  %s:  %s%.0f%%" % [label, sign, pct]
	elif additive:
		var sign = "+" if val >= 0 else ""
		return "  %s:  %s%s%s" % [label, sign, str(val), unit]
	else:
		return "  %s:  %s%s" % [label, str(val), unit]

func _count_boons_for_ability(ability_id: String) -> int:
	var count = 0
	for boon_id in _held_boons:
		var boon = BoonDB.get_boon(boon_id)
		if boon.is_empty(): continue
		var stat = boon.get("stat", boon.get("passive", boon.get("ability", "")))
		if ABILITY_STAT_MAP.get(ability_id, []).has(stat):
			count += 1
		elif boon.get("type") == "double":
			for pair in boon.get("stats", []):
				if ABILITY_STAT_MAP.get(ability_id, []).has(pair[0]):
					count += 1
					break
	return count

func _ability_short(id: String) -> String:
	return ABILITY_DISPLAY.get(id, {}).get("short", id.left(2).to_upper())

func _passive_ability(passive: String) -> String:
	if passive.begins_with("c1"): return "c1_spiders"
	if passive.begins_with("c2"): return "c2_dragon"
	if passive.begins_with("c3"): return "c3_bomb"
	if passive.begins_with("c4"): return "c4_karura"
	return ""

func _passive_label(passive: String) -> String:
	match passive:
		"c1_pierce":       return "Spiders pierce first enemy"
		"c1_slow":         return "Spiders apply 30% slow"
		"c2_homing_dash":  return "Owl tracks during dash"
		"c3_double_det":   return "Double detonation (60% on 2nd)"
		"c3_invisible":    return "Bomb is invisible until detonation"
		"c4_double_det":   return "C4 detonates twice"
		"deathsave":       return "Survive killing blow once/floor"
		"berserker":       return "Below 30% HP: +50% dmg, +25% taken"
	return passive

func reset_for_new_run() -> void:
	_held_boons.clear()
	_accum_stats.clear()
	_passives.clear()
	visible = false
	_open   = false
