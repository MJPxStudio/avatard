extends CanvasLayer

# ============================================================
# DUNGEON HUD
#
# Five distinct display moments:
#   1. Floor entrance  — full-screen overlay on each floor start
#   2. Boss intro      — dramatic banner when boss room entered
#   3. Room clear      — "ROOM CLEAR" flash when room is cleared
#   4. HUD bar         — persistent room pips + floor + boss bar
#   5. Dungeon complete — full-screen clear with 30s countdown
# ============================================================

const DungeonData = preload("res://scripts/dungeon_data.gd")

# ── Colours ──────────────────────────────────────────────────
const C_GOLD   = Color(1.00, 0.88, 0.30)
const C_RED    = Color(0.90, 0.20, 0.20)
const C_GREEN  = Color(0.25, 0.90, 0.40)
const C_DIM    = Color(0.55, 0.55, 0.65)
const C_WHITE  = Color(1.00, 1.00, 1.00)
const C_EASY   = Color(0.25, 0.75, 0.35)
const C_MEDIUM = Color(0.85, 0.68, 0.15)
const C_HARD   = Color(0.85, 0.22, 0.18)

# ── Persistent HUD nodes ─────────────────────────────────────
var _top_bar:         Panel   = null
var _room_label:      Label   = null
var _floor_label:     Label   = null
var _pip_container:   HBoxContainer = null
var _diff_badge:      Label   = null

var _boss_bar_root:   Control = null
var _boss_name_lbl:   Label   = null
var _boss_bar_bg:     ColorRect = null
var _boss_bar_fg:     ColorRect = null

# ── Overlay nodes ─────────────────────────────────────────────
var _floor_intro:     Control = null
var _boss_intro:      Control = null
var _room_clear_flash: Control = null
var _complete_screen: Control = null

# ── State ─────────────────────────────────────────────────────
var _current_floor:   int     = 1
var _total_floors:    int     = 1
var _current_room:    int     = 0
var _total_rooms:     int     = 0
var _dungeon_name:    String  = ""
var _difficulty:      String  = "easy"
var _complete_timer:  float   = 0.0
var _pip_nodes:       Array   = []

const BOSS_BAR_W = 320

# ── Setup ─────────────────────────────────────────────────────

func _ready() -> void:
	layer   = 50
	visible = false
	_build_top_bar()
	_build_boss_bar()
	_build_floor_intro()
	_build_boss_intro()
	_build_room_clear_flash()
	_build_complete_screen()

func _process(delta: float) -> void:
	if _complete_timer > 0.0:
		_complete_timer -= delta
		_update_complete_countdown()

# ── Top bar ───────────────────────────────────────────────────

func _build_top_bar() -> void:
	_top_bar = Panel.new()
	_top_bar.anchor_left   = 0.5
	_top_bar.anchor_right  = 0.5
	_top_bar.offset_left   = -180
	_top_bar.offset_right  =  180
	_top_bar.offset_top    = 8
	_top_bar.offset_bottom = 58
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.03, 0.07, 0.88)
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = Color(0.25, 0.22, 0.38)
	_top_bar.add_theme_stylebox_override("panel", s)
	add_child(_top_bar)

	# Floor label — top-left of bar
	_floor_label = Label.new()
	_floor_label.position = Vector2(10, 4)
	_floor_label.size     = Vector2(80, 18)
	_floor_label.add_theme_font_size_override("font_size", 8)
	_floor_label.add_theme_color_override("font_color", C_DIM)
	_top_bar.add_child(_floor_label)

	# Room pips — centre row
	_pip_container = HBoxContainer.new()
	_pip_container.position = Vector2(0, 8)
	_pip_container.size     = Vector2(360, 16)
	_pip_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_pip_container.add_theme_constant_override("separation", 4)
	_top_bar.add_child(_pip_container)

	# Room label — below pips
	_room_label = Label.new()
	_room_label.anchor_left  = 0.0; _room_label.anchor_right = 1.0
	_room_label.offset_top   = 28;  _room_label.offset_bottom = 46
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.add_theme_font_size_override("font_size", 8)
	_room_label.add_theme_color_override("font_color", C_DIM)
	_top_bar.add_child(_room_label)

	# Difficulty badge — top right of screen
	_diff_badge = Label.new()
	_diff_badge.anchor_left   = 1.0; _diff_badge.anchor_right  = 1.0
	_diff_badge.anchor_top    = 0.0; _diff_badge.anchor_bottom = 0.0
	_diff_badge.offset_left   = -100; _diff_badge.offset_right  = -8
	_diff_badge.offset_top    = 8;    _diff_badge.offset_bottom = 28
	_diff_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_diff_badge.add_theme_font_size_override("font_size", 9)
	add_child(_diff_badge)

func _rebuild_pips(total: int, current: int) -> void:
	for p in _pip_nodes:
		if is_instance_valid(p):
			p.queue_free()
	_pip_nodes.clear()

	var pip_size = clamp(int(280.0 / max(total, 1)), 6, 14)
	for i in range(total):
		var pip = ColorRect.new()
		pip.custom_minimum_size = Vector2(pip_size, pip_size)
		pip.size = Vector2(pip_size, pip_size)
		if i < current:
			pip.color = C_GOLD
		else:
			pip.color = Color(0.25, 0.22, 0.35)
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(2)
		pip.add_theme_stylebox_override("panel", style)
		_pip_container.add_child(pip)
		_pip_nodes.append(pip)

# ── Boss bar ──────────────────────────────────────────────────

func _build_boss_bar() -> void:
	_boss_bar_root = Control.new()
	_boss_bar_root.anchor_left   = 0.5
	_boss_bar_root.anchor_right  = 0.5
	_boss_bar_root.anchor_top    = 1.0
	_boss_bar_root.anchor_bottom = 1.0
	_boss_bar_root.offset_left   = -BOSS_BAR_W / 2
	_boss_bar_root.offset_right  =  BOSS_BAR_W / 2
	_boss_bar_root.offset_top    = -60
	_boss_bar_root.offset_bottom = -12
	_boss_bar_root.visible = false
	add_child(_boss_bar_root)

	var bg = Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.03, 0.03, 0.92)
	ps.set_corner_radius_all(6)
	ps.set_border_width_all(1)
	ps.border_color = Color(0.45, 0.12, 0.12)
	bg.add_theme_stylebox_override("panel", ps)
	_boss_bar_root.add_child(bg)

	_boss_name_lbl = Label.new()
	_boss_name_lbl.anchor_left  = 0.0; _boss_name_lbl.anchor_right = 1.0
	_boss_name_lbl.offset_top   = 5;   _boss_name_lbl.offset_bottom = 20
	_boss_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_lbl.add_theme_font_size_override("font_size", 9)
	_boss_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	_boss_bar_root.add_child(_boss_name_lbl)

	_boss_bar_bg = ColorRect.new()
	_boss_bar_bg.color    = Color(0.15, 0.05, 0.05)
	_boss_bar_bg.position = Vector2(10, 22)
	_boss_bar_bg.size     = Vector2(BOSS_BAR_W - 20, 12)
	_boss_bar_root.add_child(_boss_bar_bg)

	_boss_bar_fg = ColorRect.new()
	_boss_bar_fg.color    = Color(0.85, 0.12, 0.12)
	_boss_bar_fg.position = Vector2(10, 22)
	_boss_bar_fg.size     = Vector2(BOSS_BAR_W - 20, 12)
	_boss_bar_root.add_child(_boss_bar_fg)

# ── 1. Floor entrance overlay ─────────────────────────────────

func _build_floor_intro() -> void:
	_floor_intro = Control.new()
	_floor_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_floor_intro.visible = false
	_floor_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_floor_intro)

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.name = "bg"
	_floor_intro.add_child(bg)

	# Dungeon name
	var dname = Label.new()
	dname.set_anchors_preset(Control.PRESET_CENTER)
	dname.offset_left = -300; dname.offset_right = 300
	dname.offset_top  = -60;  dname.offset_bottom = -20
	dname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dname.add_theme_font_size_override("font_size", 16)
	dname.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	dname.name = "dungeon_name"
	_floor_intro.add_child(dname)

	# Floor number
	var flbl = Label.new()
	flbl.set_anchors_preset(Control.PRESET_CENTER)
	flbl.offset_left = -300; flbl.offset_right = 300
	flbl.offset_top  = -12;  flbl.offset_bottom = 32
	flbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flbl.add_theme_font_size_override("font_size", 28)
	flbl.add_theme_color_override("font_color", C_GOLD)
	flbl.name = "floor_label"
	_floor_intro.add_child(flbl)

	# Divider line
	var line = ColorRect.new()
	line.set_anchors_preset(Control.PRESET_CENTER)
	line.offset_left = -120; line.offset_right = 120
	line.offset_top  = 38;   line.offset_bottom = 40
	line.color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.4)
	line.name = "divider"
	_floor_intro.add_child(line)

	# Subtitle
	var sub = Label.new()
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.offset_left = -300; sub.offset_right = 300
	sub.offset_top  = 46;   sub.offset_bottom = 68
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", C_DIM)
	sub.name = "subtitle"
	_floor_intro.add_child(sub)

# ── 2. Boss intro overlay ─────────────────────────────────────

func _build_boss_intro() -> void:
	_boss_intro = Control.new()
	_boss_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boss_intro.visible = false
	_boss_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_intro)

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.name = "bg"
	_boss_intro.add_child(bg)

	var banner = Panel.new()
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -280; banner.offset_right  = 280
	banner.offset_top  = -50;  banner.offset_bottom = 50
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.08, 0.03, 0.03, 0.95)
	bs.set_corner_radius_all(6)
	bs.set_border_width_all(2)
	bs.border_color = Color(0.7, 0.15, 0.15)
	banner.add_theme_stylebox_override("panel", bs)
	banner.name = "banner"
	_boss_intro.add_child(banner)

	var prefix = Label.new()
	prefix.set_anchors_preset(Control.PRESET_CENTER)
	prefix.offset_left = -280; prefix.offset_right = 280
	prefix.offset_top  = -42;  prefix.offset_bottom = -16
	prefix.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prefix.text = "⚔  BOSS ENCOUNTER  ⚔"
	prefix.add_theme_font_size_override("font_size", 9)
	prefix.add_theme_color_override("font_color", Color(0.7, 0.15, 0.15))
	prefix.name = "prefix"
	_boss_intro.add_child(prefix)

	var boss_name = Label.new()
	boss_name.set_anchors_preset(Control.PRESET_CENTER)
	boss_name.offset_left = -280; boss_name.offset_right = 280
	boss_name.offset_top  = -14;  boss_name.offset_bottom = 22
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name.add_theme_font_size_override("font_size", 22)
	boss_name.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	boss_name.name = "boss_name"
	_boss_intro.add_child(boss_name)

	var tagline = Label.new()
	tagline.set_anchors_preset(Control.PRESET_CENTER)
	tagline.offset_left = -280; tagline.offset_right = 280
	tagline.offset_top  = 26;   tagline.offset_bottom = 46
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 9)
	tagline.add_theme_color_override("font_color", C_DIM)
	tagline.name = "tagline"
	_boss_intro.add_child(tagline)

# ── 3. Room clear flash ───────────────────────────────────────

func _build_room_clear_flash() -> void:
	_room_clear_flash = Control.new()
	_room_clear_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_clear_flash.visible = false
	_room_clear_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_room_clear_flash)

	var lbl = Label.new()
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = -200; lbl.offset_right  = 200
	lbl.offset_top  = -30;  lbl.offset_bottom = 30
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.text = "ROOM CLEAR"
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", C_GREEN)
	lbl.name = "label"
	_room_clear_flash.add_child(lbl)

# ── 4. Complete screen ────────────────────────────────────────

func _build_complete_screen() -> void:
	_complete_screen = Control.new()
	_complete_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_complete_screen.visible = false
	_complete_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_complete_screen)

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_complete_screen.add_child(bg)

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220; panel.offset_right  = 220
	panel.offset_top  = -110; panel.offset_bottom = 110
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.06, 0.04, 0.96)
	ps.set_corner_radius_all(10)
	ps.set_border_width_all(2)
	ps.border_color = Color(0.25, 0.65, 0.30)
	panel.add_theme_stylebox_override("panel", ps)
	panel.name = "panel"
	_complete_screen.add_child(panel)

	var clear_lbl = Label.new()
	clear_lbl.set_anchors_preset(Control.PRESET_CENTER)
	clear_lbl.offset_left = -220; clear_lbl.offset_right  = 220
	clear_lbl.offset_top  = -90;  clear_lbl.offset_bottom = -40
	clear_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clear_lbl.text = "✓  DUNGEON CLEAR"
	clear_lbl.add_theme_font_size_override("font_size", 22)
	clear_lbl.add_theme_color_override("font_color", C_GREEN)
	_complete_screen.add_child(clear_lbl)

	var name_lbl = Label.new()
	name_lbl.set_anchors_preset(Control.PRESET_CENTER)
	name_lbl.offset_left = -220; name_lbl.offset_right  = 220
	name_lbl.offset_top  = -34;  name_lbl.offset_bottom = -6
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	name_lbl.name = "dungeon_name"
	_complete_screen.add_child(name_lbl)

	var divider = ColorRect.new()
	divider.set_anchors_preset(Control.PRESET_CENTER)
	divider.offset_left = -140; divider.offset_right  = 140
	divider.offset_top  = 0;    divider.offset_bottom = 2
	divider.color = Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, 0.35)
	_complete_screen.add_child(divider)

	var countdown_lbl = Label.new()
	countdown_lbl.set_anchors_preset(Control.PRESET_CENTER)
	countdown_lbl.offset_left = -220; countdown_lbl.offset_right  = 220
	countdown_lbl.offset_top  = 14;   countdown_lbl.offset_bottom = 40
	countdown_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_lbl.add_theme_font_size_override("font_size", 11)
	countdown_lbl.add_theme_color_override("font_color", C_DIM)
	countdown_lbl.name = "countdown"
	_complete_screen.add_child(countdown_lbl)

	var floor_summary = Label.new()
	floor_summary.set_anchors_preset(Control.PRESET_CENTER)
	floor_summary.offset_left = -220; floor_summary.offset_right  = 220
	floor_summary.offset_top  = 48;   floor_summary.offset_bottom = 72
	floor_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor_summary.add_theme_font_size_override("font_size", 9)
	floor_summary.add_theme_color_override("font_color", C_DIM)
	floor_summary.name = "floor_summary"
	_complete_screen.add_child(floor_summary)

# ── PUBLIC API ────────────────────────────────────────────────

func show_dungeon() -> void:
	visible = true
	_boss_bar_root.visible  = false
	_complete_screen.visible = false
	_floor_intro.visible    = false
	_boss_intro.visible     = false
	_room_clear_flash.visible = false

func hide_dungeon() -> void:
	visible = false

# Called when a new floor begins
func on_floor_start(floor_num: int, total_floors: int, dungeon_name: String, difficulty: String = "easy") -> void:
	visible = true
	_current_floor  = floor_num
	_total_floors   = total_floors
	_dungeon_name   = dungeon_name
	_difficulty     = difficulty

	_update_floor_label()
	_update_diff_badge()
	_boss_bar_root.visible = false

	# Show floor entrance overlay
	var dname_lbl = _floor_intro.get_node("dungeon_name")
	var floor_lbl = _floor_intro.get_node("floor_label")
	var sub_lbl   = _floor_intro.get_node("subtitle")
	var bg_rect   = _floor_intro.get_node("bg")
	dname_lbl.text = dungeon_name.to_upper() if dungeon_name != "" else "DUNGEON"
	floor_lbl.text = "FLOOR  %d" % floor_num
	sub_lbl.text   = "Floor %d of %d" % [floor_num, total_floors]
	bg_rect.color  = Color(0, 0, 0, 0)

	_floor_intro.modulate = Color(1, 1, 1, 0)
	_floor_intro.visible  = true

	var tween = create_tween()
	# Fade in
	tween.tween_property(_floor_intro, "modulate", Color(1,1,1,1), 0.3)
	tween.tween_property(bg_rect, "color", Color(0, 0, 0, 0.75), 0.1)
	# Hold
	tween.tween_interval(1.8)
	# Fade out
	tween.tween_property(_floor_intro, "modulate", Color(1,1,1,0), 0.4)
	tween.tween_callback(func(): _floor_intro.visible = false)

# Called when a room wave begins
func on_wave_start(wave: int, total: int, objective: String) -> void:
	visible = true
	_current_room = wave
	_total_rooms  = total
	_rebuild_pips(total, wave)
	_room_label.text = objective
	_room_label.add_theme_color_override("font_color", C_DIM)
	_update_floor_label()

	# Flash the pips
	var tween = create_tween()
	tween.tween_property(_pip_container, "modulate", Color(1.4, 1.4, 0.4, 1.0), 0.12)
	tween.tween_property(_pip_container, "modulate", Color(1, 1, 1, 1.0), 0.4)

# Called when a room is cleared
func on_room_cleared() -> void:
	# Update pips to full
	_rebuild_pips(_total_rooms, _current_room)

	# ROOM CLEAR flash
	var lbl = _room_clear_flash.get_node("label")
	lbl.modulate = Color(1, 1, 1, 0)
	_room_clear_flash.visible = true

	var tween = create_tween()
	tween.tween_property(lbl, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(0.6)
	tween.tween_property(lbl, "modulate", Color(1, 1, 1, 0), 0.3)
	tween.tween_callback(func(): _room_clear_flash.visible = false)

# Called when boss room is entered
func on_boss_phase(boss_name: String, _phase: int, _msg: String) -> void:
	_boss_bar_root.visible = true
	_boss_name_lbl.text    = boss_name

	# Brief delay so room transition settles before banner appears
	await get_tree().create_timer(0.4).timeout
	if not is_instance_valid(self):
		return

	# Boss intro banner
	var bname_lbl = _boss_intro.get_node("boss_name")
	var tagline   = _boss_intro.get_node("tagline")
	var bg_rect   = _boss_intro.get_node("bg")
	bname_lbl.text = boss_name.to_upper()
	tagline.text   = "Prepare yourself."
	bg_rect.color  = Color(0, 0, 0, 0)

	_boss_intro.modulate = Color(1, 1, 1, 0)
	_boss_intro.visible  = true

	var tween = create_tween()
	tween.tween_property(_boss_intro,    "modulate", Color(1,1,1,1),    0.25)
	tween.tween_property(bg_rect,        "color",    Color(0,0,0,0.6),  0.1)
	tween.tween_interval(1.6)
	tween.tween_property(_boss_intro,    "modulate", Color(1,1,1,0),    0.35)
	tween.tween_callback(func(): _boss_intro.visible = false)

	# Pulse boss bar border red
	var tween2 = create_tween().set_loops(3)
	tween2.tween_property(_boss_bar_fg, "color", Color(1.0, 0.3, 0.3), 0.15)
	tween2.tween_property(_boss_bar_fg, "color", Color(0.85, 0.12, 0.12), 0.25)

func update_boss_hp(hp: int, max_hp: int) -> void:
	_boss_bar_root.visible = true
	var pct = float(hp) / float(max(max_hp, 1))
	var target_w = (BOSS_BAR_W - 20) * pct
	var tween = create_tween()
	tween.tween_property(_boss_bar_fg, "size:x", target_w, 0.12)

func on_dungeon_complete() -> void:
	_boss_bar_root.visible  = false
	_floor_intro.visible    = false
	_boss_intro.visible     = false
	_room_clear_flash.visible = false

	var cname_lbl  = _complete_screen.get_node("dungeon_name")
	var countdown  = _complete_screen.get_node("countdown")
	var summary    = _complete_screen.get_node("floor_summary")
	cname_lbl.text = _dungeon_name
	summary.text   = "%d Floors Cleared" % _total_floors
	_complete_timer = 30.0
	_update_complete_countdown()

	_complete_screen.modulate = Color(1, 1, 1, 0)
	_complete_screen.visible  = true
	var tween = create_tween()
	tween.tween_property(_complete_screen, "modulate", Color(1,1,1,1), 0.5)

func on_dungeon_failed() -> void:
	_boss_bar_root.visible = false
	_room_label.add_theme_color_override("font_color", C_RED)
	_room_label.text = "Returning to village..."
	var tween = create_tween()
	tween.tween_interval(3.0)
	tween.tween_callback(func():
		_room_label.text = ""
	)

# ── Internal helpers ──────────────────────────────────────────

func _update_floor_label() -> void:
	if _floor_label:
		_floor_label.text = "Floor %d / %d" % [_current_floor, _total_floors]

func _update_diff_badge() -> void:
	if not _diff_badge:
		return
	match _difficulty:
		"easy":
			_diff_badge.text = "EASY"
			_diff_badge.add_theme_color_override("font_color", C_EASY)
		"medium":
			_diff_badge.text = "MEDIUM"
			_diff_badge.add_theme_color_override("font_color", C_MEDIUM)
		"hard":
			_diff_badge.text = "HARD"
			_diff_badge.add_theme_color_override("font_color", C_HARD)

func _update_complete_countdown() -> void:
	var countdown = _complete_screen.get_node_or_null("countdown")
	if countdown:
		var secs = ceili(_complete_timer)
		countdown.text = "Returning to village in %ds..." % max(secs, 0)
