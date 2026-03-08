extends CanvasLayer

# ============================================================
# RESPAWN SCREEN — Shown to local player on death.
# Displays a dark overlay, "YOU DIED" header, and a live
# countdown matching the server's 5-second respawn timer.
# Created by player.gd on death, freed on respawn.
# ============================================================

const RESPAWN_TIME: float = 5.0

var _timer:       float = RESPAWN_TIME
var _count_label: Label = null

func _ready() -> void:
	print("[RESPAWN_SCREEN] _ready() fired — layer=64")
	layer = 64  # above world, below fade overlay (128)
	_build()
	print("[RESPAWN_SCREEN] _build() complete")

func _build() -> void:
	# Dark translucent full-screen background
	var bg              = ColorRect.new()
	bg.color            = Color(0, 0, 0, 0.55)
	bg.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# CenterContainer fills the screen and centers its child automatically
	var center              = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var container           = VBoxContainer.new()
	container.alignment     = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 12)
	center.add_child(container)

	# "YOU DIED" header
	var died_lbl = Label.new()
	died_lbl.text                                  = "YOU DIED"
	died_lbl.horizontal_alignment                  = HORIZONTAL_ALIGNMENT_CENTER
	died_lbl.add_theme_font_size_override("font_size", 36)
	died_lbl.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15, 1.0))
	died_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	died_lbl.add_theme_constant_override("shadow_offset_x", 2)
	died_lbl.add_theme_constant_override("shadow_offset_y", 2)
	container.add_child(died_lbl)

	# Countdown label
	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 18)
	_count_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	_count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_count_label.add_theme_constant_override("shadow_offset_y", 1)
	container.add_child(_count_label)
	_update_label()

func _process(delta: float) -> void:
	_timer -= delta
	if _timer < 0.0:
		_timer = 0.0
	_update_label()

func _update_label() -> void:
	if _count_label == null:
		print("[RESPAWN_SCREEN] WARNING: _count_label is null!")
		return
	var secs = ceili(_timer)
	_count_label.text = "Respawning in %d..." % secs
