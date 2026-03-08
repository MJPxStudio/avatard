extends CanvasLayer

# ============================================================
# DUNGEON HUD (client-side)
# Shows wave progress, objective text, boss phase, victory/fail.
# Visible only while inside a dungeon.
# ============================================================

var _wave_panel:     Panel  = null
var _wave_lbl:       Label  = null
var _obj_lbl:        Label  = null
var _boss_bar_root:  Control = null
var _boss_bar_bg:    ColorRect = null
var _boss_bar_fg:    ColorRect = null
var _boss_name_lbl:  Label  = null
var _result_panel:   Panel  = null
var _result_lbl:     Label  = null

const BOSS_BAR_W = 300

func _ready() -> void:
	layer   = 50
	visible = false
	_build_wave_panel()
	_build_boss_bar()
	_build_result_panel()

func _build_wave_panel() -> void:
	_wave_panel = Panel.new()
	_wave_panel.anchor_left  = 0.5
	_wave_panel.anchor_right = 0.5
	_wave_panel.offset_left  = -110
	_wave_panel.offset_right =  110
	_wave_panel.offset_top   = 8
	_wave_panel.offset_bottom = 52
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.04, 0.08, 0.85)
	s.set_corner_radius_all(5)
	s.set_content_margin_all(6)
	_wave_panel.add_theme_stylebox_override("panel", s)
	add_child(_wave_panel)

	_wave_lbl = Label.new()
	_wave_lbl.text = "Wave 1 / 3"
	_wave_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_wave_lbl.offset_top    = 4
	_wave_lbl.offset_bottom = 20
	_wave_lbl.add_theme_font_size_override("font_size", 10)
	_wave_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	_wave_panel.add_child(_wave_lbl)

	_obj_lbl = Label.new()
	_obj_lbl.text = "Defeat all enemies"
	_obj_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_obj_lbl.offset_top    = -18
	_obj_lbl.offset_bottom = -4
	_obj_lbl.add_theme_font_size_override("font_size", 8)
	_obj_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	_wave_panel.add_child(_obj_lbl)

func _build_boss_bar() -> void:
	_boss_bar_root = Control.new()
	_boss_bar_root.anchor_left   = 0.5
	_boss_bar_root.anchor_right  = 0.5
	_boss_bar_root.anchor_top    = 1.0
	_boss_bar_root.anchor_bottom = 1.0
	_boss_bar_root.offset_left   = -BOSS_BAR_W / 2
	_boss_bar_root.offset_right  =  BOSS_BAR_W / 2
	_boss_bar_root.offset_top    = -54
	_boss_bar_root.offset_bottom = -14
	_boss_bar_root.visible = false
	add_child(_boss_bar_root)

	var bg_panel = Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.05, 0.08, 0.9)
	ps.set_corner_radius_all(4)
	bg_panel.add_theme_stylebox_override("panel", ps)
	_boss_bar_root.add_child(bg_panel)

	_boss_name_lbl = Label.new()
	_boss_name_lbl.text = "Cave Troll"
	_boss_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_lbl.anchor_left  = 0.0; _boss_name_lbl.anchor_right = 1.0
	_boss_name_lbl.offset_top   = 4;   _boss_name_lbl.offset_bottom = 16
	_boss_name_lbl.add_theme_font_size_override("font_size", 8)
	_boss_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	_boss_bar_root.add_child(_boss_name_lbl)

	_boss_bar_bg = ColorRect.new()
	_boss_bar_bg.color    = Color(0.12, 0.05, 0.05)
	_boss_bar_bg.position = Vector2(8, 20)
	_boss_bar_bg.size     = Vector2(BOSS_BAR_W - 16, 10)
	_boss_bar_root.add_child(_boss_bar_bg)

	_boss_bar_fg = ColorRect.new()
	_boss_bar_fg.color    = Color(0.8, 0.1, 0.1)
	_boss_bar_fg.position = Vector2(8, 20)
	_boss_bar_fg.size     = Vector2(BOSS_BAR_W - 16, 10)
	_boss_bar_root.add_child(_boss_bar_fg)

func _build_result_panel() -> void:
	_result_panel = Panel.new()
	_result_panel.anchor_left   = 0.5
	_result_panel.anchor_right  = 0.5
	_result_panel.anchor_top    = 0.5
	_result_panel.anchor_bottom = 0.5
	_result_panel.offset_left   = -120
	_result_panel.offset_right  =  120
	_result_panel.offset_top    = -40
	_result_panel.offset_bottom =  40
	_result_panel.visible = false
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.04, 0.08, 0.92)
	s.set_corner_radius_all(8)
	_result_panel.add_theme_stylebox_override("panel", s)
	add_child(_result_panel)

	_result_lbl = Label.new()
	_result_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_result_lbl.add_theme_font_size_override("font_size", 16)
	_result_panel.add_child(_result_lbl)

# ── PUBLIC API ─────────────────────────────────────────────

func show_dungeon() -> void:
	visible = true
	_boss_bar_root.visible = false
	_result_panel.visible  = false

func hide_dungeon() -> void:
	visible = false

func on_wave_start(wave: int, total: int, objective: String) -> void:
	visible = true
	_wave_lbl.text = "Wave %d / %d" % [wave, total]
	_obj_lbl.text  = objective
	var tween = create_tween()
	tween.tween_property(_wave_lbl, "modulate", Color(1.5, 1.5, 0.3, 1.0), 0.15)
	tween.tween_property(_wave_lbl, "modulate", Color(1, 1, 1, 1.0), 0.5)

func on_boss_phase(boss_name: String, _phase: int, msg: String) -> void:
	_boss_bar_root.visible = true
	_boss_name_lbl.text    = "%s — %s" % [boss_name, msg]
	_boss_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	var tween = create_tween()
	tween.tween_property(_boss_bar_fg, "color", Color(1.0, 0.3, 0.3), 0.1)
	tween.tween_property(_boss_bar_fg, "color", Color(0.8, 0.1, 0.1), 0.3)

func update_boss_hp(hp: int, max_hp: int) -> void:
	_boss_bar_root.visible = true
	var pct = float(hp) / float(max(max_hp, 1))
	_boss_bar_fg.size.x = (BOSS_BAR_W - 16) * pct

func on_dungeon_complete() -> void:
	_result_panel.visible = true
	_result_lbl.text      = "✓ DUNGEON CLEAR"
	_result_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	await get_tree().create_timer(4.0).timeout
	_result_panel.visible = false

func on_dungeon_failed() -> void:
	_result_panel.visible = true
	_result_lbl.text      = "✗ PARTY WIPED"
	_result_lbl.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
