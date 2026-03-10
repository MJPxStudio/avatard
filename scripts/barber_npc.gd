extends Node2D

# ============================================================
# BARBER NPC — Lets the player change their hair color.
# Red square placeholder until art is ready.
# Press F to open color picker, pick a color, click Apply.
# ============================================================

var _in_range:  bool  = false
var _prompt:    Label = null
var _ui:        CanvasLayer = null

func _ready() -> void:
	add_to_group("npc")
	_build_visual()
	_build_proximity()

func _build_visual() -> void:
	# Red square placeholder
	var vis      = ColorRect.new()
	vis.color    = Color("e74c3c")
	vis.size     = Vector2(16, 24)
	vis.position = Vector2(-8, -12)
	vis.z_index  = 1
	add_child(vis)

	# Name label
	var lbl      = Label.new()
	lbl.text     = "Barber"
	lbl.z_index  = 2
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color",        Color(1.0, 1.0, 0.5, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.position = Vector2(-16, -28)
	add_child(lbl)

	# Interact prompt
	_prompt                      = Label.new()
	_prompt.visible              = false
	_prompt.z_index              = 10
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 9)
	_prompt.add_theme_color_override("font_color",        Color(1.0, 1.0, 0.5, 1.0))
	_prompt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_prompt.text     = "[F] Barber"
	_prompt.position = Vector2(-24, -44)
	add_child(_prompt)

func _build_proximity() -> void:
	var area            = Area2D.new()
	area.collision_mask = 1
	area.name           = "ProximityArea"
	var shape           = CollisionShape2D.new()
	var rect            = RectangleShape2D.new()
	rect.size           = Vector2(64, 64)
	shape.shape         = rect
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_proximity_entered)
	area.body_exited.connect(_on_proximity_exited)

func _on_proximity_entered(body: Node) -> void:
	if body is CharacterBody2D and body.is_in_group("local_player"):
		_in_range = true
		if _prompt: _prompt.visible = true

func _on_proximity_exited(body: Node) -> void:
	if body is CharacterBody2D and body.is_in_group("local_player"):
		_in_range = false
		if _prompt: _prompt.visible = false

func _input(event: InputEvent) -> void:
	if not _in_range:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F:
			_open_barber_ui()

func _open_barber_ui() -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	if main.get_node_or_null("BarberUI") != null:
		return

	var player = get_tree().get_first_node_in_group("local_player")
	if player == null:
		return

	_ui = CanvasLayer.new()
	_ui.name  = "BarberUI"
	_ui.layer = 10
	main.add_child(_ui)

	# Background panel
	var panel          = PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 200)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	_ui.add_child(panel)

	var vbox           = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Add some padding
	var margin         = MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    16)
	margin.add_theme_constant_override("margin_bottom", 16)
	vbox.add_child(margin)

	var inner          = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	margin.add_child(inner)

	# Title
	var title          = Label.new()
	title.text         = "Barber — Choose Hair Color"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	inner.add_child(title)

	# Color picker
	var picker         = ColorPickerButton.new()
	picker.color       = player.hair_color if "hair_color" in player else Color("e8c49a")
	picker.custom_minimum_size = Vector2(280, 40)
	inner.add_child(picker)

	# Preset color swatches (common hair colors)
	var presets_label  = Label.new()
	presets_label.text = "Quick Colors:"
	presets_label.add_theme_font_size_override("font_size", 9)
	inner.add_child(presets_label)

	var swatches       = HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 6)
	inner.add_child(swatches)

	var preset_colors  = [
		Color("1a1a1a"),  # black
		Color("3b2314"),  # dark brown
		Color("7b3f00"),  # brown
		Color("c8a96e"),  # blonde
		Color("e8c49a"),  # light blonde
		Color("ffffff"),  # white/silver
		Color("cc3333"),  # red
		Color("3355cc"),  # blue
		Color("44aa44"),  # green
		Color("aa44aa"),  # purple
	]

	for col in preset_colors:
		var swatch            = ColorRect.new()
		swatch.color          = col
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				picker.color = col
		)
		swatches.add_child(swatch)

	# Buttons
	var btn_row        = HBoxContainer.new()
	btn_row.alignment  = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	inner.add_child(btn_row)

	var apply_btn      = Button.new()
	apply_btn.text     = "Apply"
	apply_btn.custom_minimum_size = Vector2(100, 32)
	apply_btn.pressed.connect(func():
		if "set_hair_color" in player:
			player.set_hair_color(picker.color)
		_close_barber_ui()
	)
	btn_row.add_child(apply_btn)

	var cancel_btn     = Button.new()
	cancel_btn.text    = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 32)
	cancel_btn.pressed.connect(_close_barber_ui)
	btn_row.add_child(cancel_btn)

func _close_barber_ui() -> void:
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
		_ui = null
