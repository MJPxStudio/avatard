extends CanvasLayer

# ============================================================
# CAST BAR
# Thin progress bar that appears below the player during cast.
# Fills left to right over cast_time seconds.
# Cancelled by knockback, root, or stun.
# ============================================================

var _bar_bg:    ColorRect = null
var _bar_fg:    ColorRect = null
var _label:     Label     = null
var _player:    Node      = null

const BAR_W = 48
const BAR_H = 4
const BAR_Y_OFFSET = 14   # pixels below player center

var _casting:       bool  = false
var _cast_progress: float = 0.0
var _cast_duration: float = 0.0
var _on_complete:   Callable
var _on_cancel:     Callable

func _ready() -> void:
	layer   = 25
	visible = false
	_build()

func _build() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_bar_bg          = ColorRect.new()
	_bar_bg.color    = Color(0.1, 0.1, 0.1, 0.75)
	_bar_bg.size     = Vector2(BAR_W, BAR_H)
	root.add_child(_bar_bg)

	_bar_fg          = ColorRect.new()
	_bar_fg.color    = Color(0.9, 0.75, 0.2, 1.0)
	_bar_fg.size     = Vector2(0, BAR_H)
	_bar_bg.add_child(_bar_fg)

	_label           = Label.new()
	_label.size      = Vector2(BAR_W, 10)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 7)
	_label.add_theme_color_override("font_color", Color("ffffff"))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(_label)

func begin_cast(player: Node, duration: float, ability_name: String, on_complete: Callable, on_cancel: Callable = Callable()) -> void:
	_player       = player
	_cast_duration = duration
	_cast_progress = 0.0
	_on_complete  = on_complete
	_on_cancel    = on_cancel
	_casting      = true
	visible       = true
	_label.text   = ability_name
	_bar_fg.size.x = 0

func cancel() -> void:
	if not _casting:
		return
	_casting = false
	visible  = false
	if _on_cancel.is_valid():
		_on_cancel.call()

func _process(delta: float) -> void:
	if not _casting or not _player or not is_instance_valid(_player):
		return

	# Check cancel conditions
	if _player.get("is_rooted") or _player.get("is_dead"):
		cancel()
		return

	# Position bar below player in screen space
	var cam = _player.get_viewport().get_camera_2d()
	if cam:
		var screen_pos = _player.get_viewport().get_canvas_transform() * _player.global_position
		_bar_bg.global_position = screen_pos + Vector2(-BAR_W / 2.0, BAR_Y_OFFSET)
		_label.global_position  = screen_pos + Vector2(-BAR_W / 2.0, BAR_Y_OFFSET + BAR_H + 1)

	_cast_progress += delta
	var ratio = clamp(_cast_progress / _cast_duration, 0.0, 1.0)
	_bar_fg.size.x = BAR_W * ratio

	if _cast_progress >= _cast_duration:
		_casting = false
		visible  = false
		_on_complete.call()
