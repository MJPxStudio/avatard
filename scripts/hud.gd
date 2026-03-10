extends CanvasLayer

# ============================================================
# HUD — Uses extracted player_hud.dmi sprites
# Frame: 160x52, displayed at 2x scale = 320x104
# Bar positions (in sprite pixel coords):
#   HP:     x=46-151, y=7-18   (w=106, h=12)
#   Chakra: x=46-151, y=22-33  (w=106, h=12)
#   EXP:    x=46-151, y=37-43  (w=106, h=7)
# ============================================================

const SCALE       = 1
const FRAME_W     = 160
const FRAME_H     = 52
const BAR_X       = 46
const BAR_W       = 106
const HP_Y        = 7
const HP_H        = 12
const CK_Y        = 22
const CK_H        = 12
const EXP_Y       = 37
const EXP_H       = 7
const HUD_PAD     = 6   # screen edge padding

# Clip controls (resized to show bar fill %)
var hp_clip:      Control
var chakra_clip:  Control
var exp_clip:     Control
var _exp_tooltip: Panel  = null
var _exp_cur:     int    = 0
var _exp_max:     int    = 100
var _exp_lbl:     Label  = null
var level_label:  Label
var rank_label:   Label
var hp_label:     Label
var chakra_label: Label

func _ready() -> void:
	_build_hud()
	_build_quest_hud()

func _build_quest_hud() -> void:
	var qhud = Control.new()
	qhud.set_script(load("res://scripts/quest_hud.gd"))
	qhud.name = "QuestHUD"
	qhud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	qhud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(qhud)

func _build_hud() -> void:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── HUD frame (background sprite) ──
	var frame_tex = load("res://sprites/hud/hud_frame.png") as Texture2D
	var frame = TextureRect.new()
	frame.texture = frame_tex
	frame.position = Vector2(HUD_PAD, HUD_PAD)
	frame.size = Vector2(FRAME_W * SCALE, FRAME_H * SCALE)
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(frame)

	# ── HP bar ──
	var hp_tex = load("res://sprites/hud/hp_fill.png") as Texture2D
	hp_clip = _make_bar_clip(root, hp_tex, HP_Y, HP_H, BAR_W)
	hp_label = _make_bar_label(root, HP_Y, HP_H, "100/100")

	# ── Chakra bar ──
	var ck_tex = load("res://sprites/hud/chakra_fill.png") as Texture2D
	chakra_clip = _make_bar_clip(root, ck_tex, CK_Y, CK_H, BAR_W)
	chakra_label = _make_bar_label(root, CK_Y, CK_H, "100/100")

	# ── EXP bar ──
	var exp_tex = load("res://sprites/hud/exp_fill.png") as Texture2D
	exp_clip = _make_bar_clip(root, exp_tex, EXP_Y, EXP_H, BAR_W)

	# Exp hover area (transparent Control over the bar, captures mouse)
	var exp_hover = Control.new()
	exp_hover.position = Vector2(HUD_PAD + BAR_X * SCALE, HUD_PAD + EXP_Y * SCALE)
	exp_hover.size = Vector2(BAR_W * SCALE, EXP_H * SCALE + 4)
	exp_hover.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(exp_hover)
	exp_hover.mouse_entered.connect(_on_exp_hover_enter)
	exp_hover.mouse_exited.connect(_on_exp_hover_exit)

	# Tooltip panel (hidden by default)
	_exp_tooltip = Panel.new()
	var ts = StyleBoxFlat.new()
	ts.bg_color = Color(0.1, 0.1, 0.1, 0.92)
	ts.border_color = Color(0.6, 0.6, 0.6, 1.0)
	ts.set_border_width_all(1)
	ts.set_corner_radius_all(4)
	ts.anti_aliasing = true
	_exp_tooltip.add_theme_stylebox_override("panel", ts)
	_exp_tooltip.size = Vector2(80, 18)
	_exp_tooltip.visible = false
	_exp_tooltip.z_index = 20
	root.add_child(_exp_tooltip)
	_exp_lbl = Label.new()
	_exp_lbl.position = Vector2(4, 2)
	_exp_lbl.size = Vector2(72, 14)
	_exp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exp_lbl.add_theme_font_size_override("font_size", 9)
	_exp_lbl.add_theme_color_override("font_color", Color("ffffff"))
	_exp_tooltip.add_child(_exp_lbl)

	# ── Level label (inside circle area on left of frame) ──
	level_label = Label.new()
	level_label.text = "1"
	level_label.position = Vector2(HUD_PAD, HUD_PAD + 16)
	level_label.size = Vector2(BAR_X * SCALE, 20 * SCALE)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 12)
	level_label.add_theme_color_override("font_color", Color("f0c040"))
	level_label.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
	level_label.add_theme_constant_override("shadow_offset_x", 1)
	level_label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(level_label)

	# ── Rank label (below the HUD frame) ──
	rank_label = Label.new()
	rank_label.text = "Academy Student"
	rank_label.position = Vector2(HUD_PAD, HUD_PAD + FRAME_H * SCALE + 2)
	rank_label.size = Vector2(FRAME_W * SCALE, 12)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rank_label.add_theme_font_size_override("font_size", 9)
	rank_label.add_theme_color_override("font_color", Color("aaaaaa"))
	rank_label.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
	rank_label.add_theme_constant_override("shadow_offset_x", 1)
	rank_label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(rank_label)

func _make_bar_clip(parent: Control, tex: Texture2D, sprite_y: int, sprite_h: int, full_w: int) -> Control:
	# Clip container — resize width to control fill %
	var clip = Control.new()
	clip.clip_contents = true
	clip.position = Vector2(HUD_PAD + BAR_X * SCALE, HUD_PAD + sprite_y * SCALE)
	clip.size = Vector2(full_w * SCALE, sprite_h * SCALE)
	parent.add_child(clip)

	# TextureRect inside clip — offset so bar pixels align
	var tr = TextureRect.new()
	tr.texture = tex
	tr.position = Vector2(-BAR_X * SCALE, -sprite_y * SCALE)
	tr.size = Vector2(FRAME_W * SCALE, FRAME_H * SCALE)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(tr)

	return clip

func _make_bar_label(parent: Control, sprite_y: int, sprite_h: int, text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.position = Vector2(HUD_PAD + BAR_X * SCALE, HUD_PAD + sprite_y * SCALE - 6)
	lbl.size = Vector2(BAR_W * SCALE, sprite_h * SCALE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color("ffffff"))
	lbl.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(lbl)
	return lbl

# ── Called by player.gd ──

func update_hp(current: int, maximum: int) -> void:
	var pct = float(current) / float(maximum)
	hp_clip.size.x = BAR_W * SCALE * pct
	hp_label.text = "%d/%d" % [current, maximum]

func update_chakra(current: int, maximum: int) -> void:
	var pct = float(current) / float(maximum)
	chakra_clip.size.x = BAR_W * SCALE * pct
	chakra_label.text = "%d/%d" % [current, maximum]

func _on_exp_hover_enter() -> void:
	if _exp_tooltip == null:
		return
	# Position tooltip just above the bar
	_exp_tooltip.position = Vector2(HUD_PAD + BAR_X * SCALE, HUD_PAD + (EXP_Y - 22) * SCALE)
	if _exp_lbl:
		_exp_lbl.text = "%d / %d XP" % [_exp_cur, _exp_max]
	_exp_tooltip.visible = true

func _on_exp_hover_exit() -> void:
	if _exp_tooltip:
		_exp_tooltip.visible = false

func update_exp(current: int, maximum: int) -> void:
	_exp_cur = current
	_exp_max = maximum
	var pct = float(current) / float(maximum)
	exp_clip.size.x = BAR_W * SCALE * pct
	# Update tooltip text if it's currently visible
	if _exp_tooltip and _exp_tooltip.visible and _exp_lbl:
		_exp_lbl.text = "%d / %d XP" % [current, maximum]

func update_level(lv: int) -> void:
	level_label.text = str(lv)

func update_rank(rank_name: String, rank_color: Color) -> void:
	rank_label.text = rank_name
	rank_label.add_theme_color_override("font_color", rank_color)
