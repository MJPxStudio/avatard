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
var level_label:  Label
var hp_label:     Label
var chakra_label: Label

func _ready() -> void:
	_build_hud()

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

func update_exp(current: int, maximum: int) -> void:
	var pct = float(current) / float(maximum)
	exp_clip.size.x = BAR_W * SCALE * pct

func update_level(lv: int) -> void:
	level_label.text = str(lv)
