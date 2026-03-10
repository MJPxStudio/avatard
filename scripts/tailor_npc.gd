extends Node2D

# ============================================================
# TAILOR NPC — Shop dialogue with Buy, Sell, and Transmog.
# Transmog: pick any equippable item from inventory, recolor it.
# Buy / Sell: stubs until items are ready.
# ============================================================

var _in_range: bool  = false
var _prompt:   Label = null
var _ui:       CanvasLayer = null

# Transmog state
var _transmog_item:        Dictionary = {}
var _transmog_item_index:  int        = -1
var _transmog_item_source: String     = ""  # "inv" or "equip"

func _ready() -> void:
	add_to_group("npc")
	_build_visual()
	_build_proximity()

func _build_visual() -> void:
	var vis      = ColorRect.new()
	vis.color    = Color("e74c3c")
	vis.size     = Vector2(16, 24)
	vis.position = Vector2(-8, -12)
	vis.z_index  = 1
	add_child(vis)

	var lbl      = Label.new()
	lbl.text     = "Tailor"
	lbl.z_index  = 2
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color",        Color(1.0, 1.0, 0.5, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.position = Vector2(-16, -28)
	add_child(lbl)

	_prompt                      = Label.new()
	_prompt.visible              = false
	_prompt.z_index              = 10
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 9)
	_prompt.add_theme_color_override("font_color",        Color(1.0, 1.0, 0.5, 1.0))
	_prompt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_prompt.text     = "[F] Tailor"
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
			_open_main_menu()

# ── UI helpers ─────────────────────────────────────────────────────────────────

func _make_ui() -> VBoxContainer:
	_close_ui()
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		return null
	_ui       = CanvasLayer.new()
	_ui.name  = "TailorUI"
	_ui.layer = 10
	main.add_child(_ui)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 260)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	panel.position.y -= 210
	_ui.add_child(panel)

	var margin = MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)

	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	margin.add_child(inner)
	return inner

func _make_title(inner: VBoxContainer, text: String) -> void:
	var title = Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	inner.add_child(title)

func _make_separator(inner: VBoxContainer) -> void:
	var sep = HSeparator.new()
	inner.add_child(sep)

func _make_button(label: String, min_w: float, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(min_w, 32)
	btn.pressed.connect(callback)
	return btn

# ── Screen: Main menu ──────────────────────────────────────────────────────────

func _open_main_menu() -> void:
	var player = get_tree().get_first_node_in_group("local_player")
	if player == null:
		return
	var inner = _make_ui()
	if inner == null:
		return

	_make_title(inner, "Welcome to the Tailor!")
	_make_separator(inner)

	var greeting = Label.new()
	greeting.text = "What can I do for you today?"
	greeting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	greeting.add_theme_font_size_override("font_size", 10)
	inner.add_child(greeting)

	var btn_row = VBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	inner.add_child(btn_row)

	btn_row.add_child(_make_button("Buy",     300, func(): _open_stub("Buy")))
	btn_row.add_child(_make_button("Sell",    300, func(): _open_stub("Sell")))
	btn_row.add_child(_make_button("Transmog",300, func(): _open_transmog_picker(player)))
	btn_row.add_child(_make_button("Leave",   300, _close_ui))

# ── Screen: Buy / Sell stubs ───────────────────────────────────────────────────

func _open_stub(mode: String) -> void:
	var inner = _make_ui()
	if inner == null:
		return
	_make_title(inner, "Tailor — %s" % mode)
	_make_separator(inner)
	var lbl = Label.new()
	lbl.text = "Coming soon!"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	inner.add_child(lbl)
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	inner.add_child(spacer)
	inner.add_child(_make_button("← Back", 300, _open_main_menu))

# ── Screen: Transmog item picker ───────────────────────────────────────────────

func _open_transmog_picker(player: Node) -> void:
	var inner = _make_ui()
	if inner == null:
		return
	_make_title(inner, "Transmog — Choose an Item")
	_make_separator(inner)

	var inv          = player.get("inventory")
	var equip_panel  = player.get("equip_panel")

	# Only show items that are currently equipped — transmog on unequipped items
	# has no visible effect since the layer isn't rendering.
	var equippable_slots: Array = []
	if equip_panel != null:
		for i in range(equip_panel.slots.size()):
			var item = equip_panel.slots[i]
			if item != null and item.get("sprite_folder", "") != "" and item.get("transmog", false):
				equippable_slots.append({"source": "equip", "index": i, "item": item})

	if equippable_slots.is_empty():
		var lbl = Label.new()
		lbl.text = "You have no equipped items to transmog."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(lbl)
		inner.add_child(_make_button("← Back", 300, _open_main_menu))
		return

	# Scrollable grid of items
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	for entry in equippable_slots:
		var item: Dictionary = entry.item
		var slot_index: int  = entry.index

		var item_btn = Button.new()
		item_btn.custom_minimum_size = Vector2(48, 48)
		item_btn.tooltip_text        = item.name
		item_btn.expand_icon         = true

		if item.get("icon_path", "") != "":
			item_btn.icon = load(item.icon_path)
			item_btn.add_theme_color_override("icon_normal_color", item.get("tint", Color("ffffff")))

		item_btn.pressed.connect(func():
			_transmog_item        = item
			_transmog_item_index  = entry.index
			_transmog_item_source = entry.source
			_open_transmog_color(player)
		)
		grid.add_child(item_btn)

		var name_lbl = Label.new()
		name_lbl.text = item.name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 8)
		name_lbl.custom_minimum_size = Vector2(48, 0)
		grid.add_child(name_lbl)

	inner.add_child(_make_button("← Back", 300, _open_main_menu))

# ── Screen: Transmog color picker ──────────────────────────────────────────────

func _open_transmog_color(player: Node) -> void:
	var item = _transmog_item
	if item.is_empty():
		_open_transmog_picker(player)
		return

	var inner = _make_ui()
	if inner == null:
		return
	_make_title(inner, "Transmog — %s" % item.name)
	_make_separator(inner)

	var picker = ColorPicker.new()
	picker.color               = item.get("tint", Color("ffffff"))
	picker.picker_shape        = 1  # PickerShapeType.SHAPE_HSV_WHEEL
	picker.edit_alpha          = false
	picker.sliders_visible     = false
	picker.hex_visible         = false
	picker.presets_visible     = false
	picker.color_modes_visible = false
	picker.sampler_visible     = false
	picker.custom_minimum_size = Vector2(240, 140)
	inner.add_child(picker)

	# Apply / Back
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	inner.add_child(btn_row)

	var apply_btn = _make_button("Apply", 140, func():
		var chosen_color: Color = picker.color
		var inv         = player.get("inventory")
		var equip_panel = player.get("equip_panel")

		if _transmog_item_source == "inv" and inv != null and _transmog_item_index >= 0:
			# Item is in inventory — write tint there and refresh icon
			var stored = inv.slots[_transmog_item_index]
			if stored != null:
				stored["tint"] = chosen_color
				inv.refresh_slot(_transmog_item_index)
		elif _transmog_item_source == "equip" and equip_panel != null and _transmog_item_index >= 0:
			# Item is equipped — write tint directly to equip panel slot
			var stored = equip_panel.slots[_transmog_item_index]
			if stored != null:
				stored["tint"] = chosen_color
				equip_panel.refresh_slot(_transmog_item_index)
				# Apply to live sprite layer immediately
				var slot_key: String = stored.get("equip_slot", "")
				if slot_key != "" and player.has_method("set_equip_layer_color"):
					player.set_equip_layer_color(slot_key, chosen_color)
				# Sync to server so other players see the new tint
				if equip_panel.has_method("_send_equip_to_server"):
					equip_panel._send_equip_to_server()
		_close_ui()
	)
	btn_row.add_child(apply_btn)
	btn_row.add_child(_make_button("← Back", 140, func(): _open_transmog_picker(player)))

# ── Close ──────────────────────────────────────────────────────────────────────

func _close_ui() -> void:
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
		_ui = null

