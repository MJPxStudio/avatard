extends CanvasLayer

# ============================================================
# HUD — Leaf Village themed, fully drawn in code
# ============================================================

const HUD_PAD  = 8
const PANEL_W  = 200
const PANEL_H  = 110
const BAR_W    = 106
const BAR_H    = 10
const BAR_X    = 84   # x offset of bars inside panel
const CIRCLE_D = 44   # diameter of level circle

const PIP_W   = 16
const PIP_H   = 4
const PIP_GAP = 3

var hp_bar:        ColorRect = null
var chakra_bar:    ColorRect = null
var exp_bar:       ColorRect = null
var hp_label:      Label     = null
var chakra_label:  Label     = null
var level_label:   Label     = null
var rank_label:    Label     = null
var gold_label:    Label     = null
var run_indicator: Label     = null
var _dash_pips:    Array     = []
var _dash_charges:  int       = 2
var _dash_timer:    float     = 0.0
var _exp_tooltip:  Panel     = null
var _exp_lbl:      Label     = null
var _exp_cur:      int       = 0
var _exp_max:      int       = 100

func _ready() -> void:
	layer = 10
	_build_hud()
	_build_quest_hud()

func _build_quest_hud() -> void:
	var qhud = Control.new()
	qhud.set_script(load("res://scripts/quest_hud.gd"))
	qhud.name = "QuestHUD"
	qhud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	qhud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(qhud)

func _make_stylebox(bg: Color, border: Color, radius: int = 3, bw: int = 1) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color    = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s

func _build_hud() -> void:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Main panel ────────────────────────────────────────────
	var panel_style = _make_stylebox(
		UITheme.color("panel_bg"), UITheme.color("panel_border"), 5, 2)
	panel_style.shadow_color  = Color(0, 0, 0, 0.5)
	panel_style.shadow_size   = 6
	panel_style.shadow_offset = Vector2(2, 2)
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.position = Vector2(HUD_PAD, HUD_PAD)
	panel.size     = Vector2(PANEL_W, PANEL_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	# Gold top accent line
	var accent = ColorRect.new()
	accent.color    = UITheme.color("panel_accent")
	accent.size     = Vector2(PANEL_W - 4, 1)
	accent.position = Vector2(2, 2)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(accent)

	# ── Level circle ─────────────────────────────────────────
	var circle_style = _make_stylebox(
		UITheme.color("panel_border"), UITheme.color("panel_accent"), CIRCLE_D / 2, 2)
	var circle = PanelContainer.new()
	circle.add_theme_stylebox_override("panel", circle_style)
	circle.size     = Vector2(CIRCLE_D, CIRCLE_D)
	circle.position = Vector2(HUD_PAD + 7, HUD_PAD + 7)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(circle)

	level_label = Label.new()
	level_label.text = "1"
	level_label.size = Vector2(CIRCLE_D, CIRCLE_D)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_color", UITheme.color("level_color"))
	level_label.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
	level_label.add_theme_constant_override("shadow_offset_x", 1)
	level_label.add_theme_constant_override("shadow_offset_y", 1)
	circle.add_child(level_label)

	# ── Bars — positioned absolutely inside root ──────────────
	var bar_start_x = HUD_PAD + BAR_X
	var bar_start_y = HUD_PAD + 8

	# HP
	_add_tag(root, "HP", bar_start_x - 24, bar_start_y - 6)
	var hp_bg = _make_bar_bg(root, bar_start_x, bar_start_y)
	hp_bar    = _make_bar_fill(hp_bg, UITheme.color("hp_fill"))
	hp_label  = _make_value_label(root, bar_start_x, bar_start_y)
	hp_label.text = "100/100"

	# Chakra
	var ck_y = bar_start_y + BAR_H + 8
	_add_tag(root, "CK", bar_start_x - 24, ck_y - 6)
	var ck_bg  = _make_bar_bg(root, bar_start_x, ck_y)
	chakra_bar = _make_bar_fill(ck_bg, UITheme.color("chakra_fill"))
	chakra_label = _make_value_label(root, bar_start_x, ck_y)
	chakra_label.text = "100/100"

	# EXP (thinner)
	var xp_y = ck_y + BAR_H + 8
	_add_tag(root, "XP", bar_start_x - 24, xp_y - 9)
	var xp_bg = _make_bar_bg(root, bar_start_x, xp_y, 6)
	exp_bar   = _make_bar_fill(xp_bg, UITheme.color("exp_fill"), 6)

	# EXP hover — only over the XP bar itself
	var exp_hover = Control.new()
	exp_hover.position = Vector2(bar_start_x, xp_y)
	exp_hover.size     = Vector2(BAR_W, 6)
	exp_hover.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(exp_hover)
	exp_hover.mouse_entered.connect(_on_exp_hover_enter)
	exp_hover.mouse_exited.connect(_on_exp_hover_exit)

	# EXP tooltip
	_exp_tooltip = Panel.new()
	_exp_tooltip.add_theme_stylebox_override("panel",
		_make_stylebox(UITheme.color("tooltip_bg"), UITheme.color("panel_accent"), 3, 1))
	_exp_tooltip.size    = Vector2(100, 18)
	_exp_tooltip.visible = false
	_exp_tooltip.z_index = 20
	root.add_child(_exp_tooltip)
	_exp_lbl = Label.new()
	_exp_lbl.position = Vector2(4, 2)
	_exp_lbl.size     = Vector2(92, 14)
	_exp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exp_lbl.add_theme_font_size_override("font_size", 9)
	_exp_lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	_exp_tooltip.add_child(_exp_lbl)

	# ── Divider ───────────────────────────────────────────────
	var divider = ColorRect.new()
	divider.color    = UITheme.color("panel_border")
	divider.size     = Vector2(PANEL_W - 16, 1)
	divider.position = Vector2(HUD_PAD + 8, HUD_PAD + xp_y - HUD_PAD + 16)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(divider)

	# ── Rank label (inside panel) ─────────────────────────────
	rank_label = Label.new()
	rank_label.text     = "Academy Student"
	rank_label.position = Vector2(HUD_PAD + 8, HUD_PAD + xp_y - HUD_PAD + 20)
	rank_label.size     = Vector2(PANEL_W - 16, 12)
	rank_label.add_theme_font_size_override("font_size", 9)
	rank_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	rank_label.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
	rank_label.add_theme_constant_override("shadow_offset_x", 1)
	rank_label.add_theme_constant_override("shadow_offset_y", 1)
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rank_label)

	# ── Gold label (inside panel) ─────────────────────────────
	gold_label = Label.new()
	gold_label.text     = "0 ¥"
	gold_label.position = Vector2(HUD_PAD + 8, HUD_PAD + xp_y - HUD_PAD + 34)
	gold_label.size     = Vector2(PANEL_W - 16, 12)
	gold_label.add_theme_font_size_override("font_size", 9)
	gold_label.add_theme_color_override("font_color", UITheme.color("gold_color"))
	gold_label.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
	gold_label.add_theme_constant_override("shadow_offset_x", 1)
	gold_label.add_theme_constant_override("shadow_offset_y", 1)
	gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gold_label)



	# ── Dash pips ─────────────────────────────────────────────
	var pip_y = HUD_PAD + PANEL_H + 4
	for i in range(2):
		var pip_bg = PanelContainer.new()
		pip_bg.add_theme_stylebox_override("panel",
			_make_stylebox(UITheme.color("bar_bg"), UITheme.color("panel_border"), 2, 1))
		pip_bg.size       = Vector2(PIP_W, PIP_H)
		pip_bg.position   = Vector2(HUD_PAD + i * (PIP_W + PIP_GAP), pip_y)
		pip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(pip_bg)
		var pip_fill = ColorRect.new()
		pip_fill.color    = UITheme.color("dash_fill")
		pip_fill.size     = Vector2(PIP_W, PIP_H)
		pip_bg.add_child(pip_fill)
		_dash_pips.append([pip_bg, pip_fill])

# ── Helpers ───────────────────────────────────────────────────

func _make_tag(parent: Control, text: String, x: float, y: float) -> void:
	var lbl = Label.new()
	lbl.text     = text
	lbl.position = Vector2(x, y)
	lbl.size     = Vector2(26, 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)

func _add_tag(parent: Control, text: String, x: float, y: float) -> void:
	var lbl = Label.new()
	lbl.text     = text
	lbl.position = Vector2(x, y)
	lbl.size     = Vector2(22, BAR_H)
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)

func _make_bar_bg(parent: Control, x: float, y: float, h: int = BAR_H) -> ColorRect:
	var bg       = ColorRect.new()
	bg.color     = UITheme.color("bar_bg")
	bg.size      = Vector2(BAR_W, h)
	bg.position  = Vector2(x, y)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg

func _make_bar_fill(bg: ColorRect, color: Color, h: int = BAR_H) -> ColorRect:
	var fill      = ColorRect.new()
	fill.color    = color
	fill.size     = Vector2(BAR_W, h)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	# Shine strip
	var shine     = ColorRect.new()
	shine.color   = Color(1, 1, 1, 0.10)
	shine.size    = Vector2(BAR_W, 2)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(shine)
	return fill

func _make_value_label(parent: Control, x: float, y: float) -> Label:
	var lbl = Label.new()
	lbl.position = Vector2(x, y - 6)
	lbl.size     = Vector2(BAR_W, BAR_H + 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	lbl.add_theme_color_override("font_shadow_color", Color(0,0,0,0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)
	return lbl

# ── Update functions ──────────────────────────────────────────

func update_hp(current: int, maximum: int) -> void:
	if hp_bar:   hp_bar.size.x   = BAR_W * (float(current) / float(maximum))
	if hp_label: hp_label.text   = "%d/%d" % [current, maximum]

func update_chakra(current: int, maximum: int) -> void:
	if chakra_bar:   chakra_bar.size.x   = BAR_W * (float(current) / float(maximum))
	if chakra_label: chakra_label.text   = "%d/%d" % [current, maximum]

func update_exp(current: int, maximum: int) -> void:
	_exp_cur = current
	_exp_max = maximum
	if exp_bar: exp_bar.size.x = BAR_W * (float(current) / float(maximum))
	if _exp_tooltip and _exp_tooltip.visible and _exp_lbl:
		_exp_lbl.text = "%d / %d XP" % [current, maximum]

func update_level(lv: int) -> void:
	if level_label: level_label.text = str(lv)

func update_rank(rank_name: String, rank_color: Color) -> void:
	if rank_label:
		rank_label.text = rank_name
		rank_label.add_theme_color_override("font_color", rank_color)

func update_gold(amount: int) -> void:
	if gold_label: gold_label.text = "%d ¥" % amount



func update_dash_charges(charges: int, timer: float) -> void:
	_dash_charges = charges
	_dash_timer   = timer
	for i in range(_dash_pips.size()):
		var pip_fill = _dash_pips[i][1]
		if i < charges:
			pip_fill.size.x = PIP_W
			pip_fill.color  = UITheme.color("dash_fill")
		elif i == charges and timer > 0.0:
			pip_fill.size.x = PIP_W * (1.0 - (timer / 7.0))
			pip_fill.color  = UITheme.color("dash_fill_dim")
		else:
			pip_fill.size.x = 0

func _on_exp_hover_enter() -> void:
	if _exp_tooltip == null: return
	if _exp_lbl: _exp_lbl.text = "%d / %d XP" % [_exp_cur, _exp_max]
	_exp_tooltip.visible = true

func _process(delta: float) -> void:
	if _exp_tooltip and _exp_tooltip.visible:
		var mouse = get_viewport().get_mouse_position()
		_exp_tooltip.position = mouse + Vector2(10, -22)
	# Tick dash timer and redraw pips smoothly
	if _dash_timer > 0.0:
		_dash_timer -= delta
		if _dash_timer < 0.0:
			_dash_timer = 0.0
		_redraw_dash_pips()

func _redraw_dash_pips() -> void:
	for i in range(_dash_pips.size()):
		var pip_fill = _dash_pips[i][1]
		if i < _dash_charges:
			pip_fill.size.x = PIP_W
			pip_fill.color  = UITheme.color("dash_fill")
		elif i == _dash_charges and _dash_timer > 0.0:
			pip_fill.size.x = PIP_W * (1.0 - (_dash_timer / 7.0))
			pip_fill.color  = UITheme.color("dash_fill_dim")
		else:
			pip_fill.size.x = 0

func _on_exp_hover_exit() -> void:
	if _exp_tooltip: _exp_tooltip.visible = false
