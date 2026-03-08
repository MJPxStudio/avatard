extends CanvasLayer

# ============================================================
# SETTINGS MENU — Opened with Escape in-game.
# Options: Return to Login, Exit Game.
# Also sets true fullscreen on first open.
# ============================================================

signal closed

var _root: Control = null

func _ready() -> void:
	layer   = 110   # above everything except fade (128)
	_build()
	# Go fullscreen when game starts
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _build() -> void:
	# Dimmed full-screen backdrop
	var backdrop            = ColorRect.new()
	backdrop.color          = Color(0, 0, 0, 0.65)
	backdrop.anchor_right   = 1.0
	backdrop.anchor_bottom  = 1.0
	backdrop.mouse_filter   = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Centered panel
	_root                   = CenterContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter      = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel               = VBoxContainer.new()
	panel.alignment         = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 12)
	_root.add_child(panel)

	# Title
	var title = Label.new()
	title.text                    = "MENU"
	title.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color",        Color(1.0, 0.85, 0.3, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	panel.add_child(title)

	# Spacer
	var spacer      = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	panel.add_child(spacer)

	# Buttons
	panel.add_child(_make_btn("Return to Game",  _on_resume))
	panel.add_child(_make_btn("Return to Login", _on_logout))
	panel.add_child(_make_btn("Exit Game",       _on_quit))

func _make_btn(label: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text                        = label
	btn.custom_minimum_size         = Vector2(200, 32)
	btn.focus_mode                  = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	var style           = StyleBoxFlat.new()
	style.bg_color      = Color(0.1, 0.1, 0.14, 0.95)
	style.border_color  = Color(0.5, 0.45, 0.3, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", style)
	var style_hover         = StyleBoxFlat.new()
	style_hover.bg_color    = Color(0.2, 0.18, 0.1, 0.95)
	style_hover.border_color = Color(1.0, 0.85, 0.3, 1.0)
	style_hover.set_border_width_all(1)
	style_hover.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.pressed.connect(callback)
	return btn

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_resume()

func _on_resume() -> void:
	closed.emit()
	queue_free()

func _on_logout() -> void:
	# Disconnect from server cleanly then reload main scene (shows login)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		multiplayer.multiplayer_peer = null
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit() -> void:
	get_tree().quit()
