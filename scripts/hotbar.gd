extends CanvasLayer

# ============================================================
# HOTBAR — 10 slots, handles both items and abilities
# Abilities show cooldown overlays
# ============================================================

const SPRITE_SIZE  = Vector2(408, 48)
const SLOT_SIZE    = Vector2(36, 37)
const SCALE        = 1.0

const SLOT_POSITIONS = [
	Vector2(6,   6), Vector2(46,  6), Vector2(86,  6), Vector2(126, 6),
	Vector2(166, 6), Vector2(206, 6), Vector2(246, 6), Vector2(286, 6),
	Vector2(326, 6), Vector2(366, 6),
]

var slots:        Array = []
var slot_buttons: Array = []
var cooldown_overlays: Array = []
var selected_slot: int = 0
var player_ref:    Node = null

func _ready() -> void:
	slots.resize(10)
	slots.fill(null)
	_build_ui()

func set_player(player: Node) -> void:
	player_ref = player

func _build_ui() -> void:
	var root = Control.new()
	root.size = SPRITE_SIZE * SCALE
	root.position = Vector2(
		(960 - SPRITE_SIZE.x * SCALE) / 2.0 + 20,
		540 - SPRITE_SIZE.y * SCALE - 4
	)
	add_child(root)

	var bg = TextureRect.new()
	bg.texture = load("res://sprites/hotbar.png")
	bg.size = SPRITE_SIZE * SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(bg)

	for i in range(10):
		var sp  = SLOT_POSITIONS[i]
		var btn = Button.new()
		btn.position   = sp * SCALE
		btn.size       = SLOT_SIZE * SCALE
		btn.focus_mode = Control.FOCUS_NONE

		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override("normal",  style_normal)
		btn.add_theme_stylebox_override("focus",   style_normal)

		var style_hover = StyleBoxFlat.new()
		style_hover.bg_color = Color(1, 1, 1, 0.2)
		btn.add_theme_stylebox_override("hover", style_hover)

		# Stack / name label
		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.position = Vector2(2, btn.size.y - 12)
		lbl.size     = Vector2(btn.size.x - 2, 12)
		btn.add_child(lbl)

		# Slot number label
		var num_lbl = Label.new()
		num_lbl.add_theme_font_size_override("font_size", 7)
		num_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.8))
		num_lbl.position = Vector2(2, 2)
		num_lbl.text     = str((i + 1) % 10)
		btn.add_child(num_lbl)

		# Color rect for ability icon background
		var icon_bg = ColorRect.new()
		icon_bg.name         = "IconBG"
		icon_bg.color        = Color(0, 0, 0, 0)
		icon_bg.size         = SLOT_SIZE * SCALE - Vector2(4, 4)
		icon_bg.position     = Vector2(2, 2)
		icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon_bg)

		# Cooldown overlay (dark rect that shrinks as cooldown expires)
		var cd = ColorRect.new()
		cd.name         = "Cooldown"
		cd.color        = Color(0, 0, 0, 0.65)
		cd.size         = Vector2(0, SLOT_SIZE.y * SCALE)
		cd.position     = Vector2(2, 2)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.z_index      = 5
		btn.add_child(cd)
		cooldown_overlays.append(cd)

		var slot_index = i
		btn.pressed.connect(func(): _on_slot_clicked(slot_index))
		root.add_child(btn)
		slot_buttons.append(btn)

	_highlight_selected()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		for i in range(10):
			var key = KEY_1 + i if i < 9 else KEY_0
			if event.keycode == key:
				selected_slot = i
				_highlight_selected()
				_use_selected_slot()
				return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			selected_slot = (selected_slot - 1 + 10) % 10
			_highlight_selected()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			selected_slot = (selected_slot + 1) % 10
			_highlight_selected()

func _process(_delta: float) -> void:
	# Tick ability cooldowns and update overlays
	for i in range(10):
		var slot = slots[i]
		if slot == null or not slot is AbilityBase:
			continue
		slot.tick(_delta)
		var pct = slot.get_cooldown_percent()
		var cd  = cooldown_overlays[i]
		cd.size.x = (SLOT_SIZE.x * SCALE - 4) * pct

func _use_selected_slot() -> void:
	var slot = slots[selected_slot]
	if slot == null:
		return
	if slot is AbilityBase:
		if player_ref != null:
			slot.activate(player_ref)

func _on_slot_clicked(index: int) -> void:
	selected_slot = index
	_highlight_selected()
	_use_selected_slot()

func _highlight_selected() -> void:
	for i in range(10):
		var btn   = slot_buttons[i]
		var style = StyleBoxFlat.new()
		if i == selected_slot:
			style.bg_color         = Color(1, 0.85, 0, 0.35)
			style.border_width_top    = 1
			style.border_width_bottom = 1
			style.border_width_left   = 1
			style.border_width_right  = 1
			style.border_color     = Color(1, 0.9, 0.2, 0.9)
		else:
			style.bg_color = Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override("normal", style)

func _refresh_slot(index: int) -> void:
	var btn    = slot_buttons[index]
	var lbl    = btn.get_child(0) as Label
	var icon_bg = btn.get_node("IconBG") as ColorRect
	var slot   = slots[index]

	if slot == null:
		lbl.text        = ""
		btn.icon        = null
		btn.tooltip_text = ""
		icon_bg.color   = Color(0, 0, 0, 0)
	elif slot is AbilityBase:
		# Ability slot
		lbl.text         = ""
		btn.tooltip_text = "%s\nChakra: %d  CD: %.1fs\n%s" % [
			slot.ability_name, slot.chakra_cost, slot.cooldown,
			slot.description]
		icon_bg.color    = slot.icon_color.darkened(0.3)
		# Ability name abbreviated
		var short = slot.ability_name.left(4)
		lbl.text  = short
	else:
		# Item slot
		lbl.text = str(slot.quantity) if slot.get("stackable", true) and slot.quantity > 1 else ""
		btn.tooltip_text = slot.name
		icon_bg.color    = Color(0, 0, 0, 0)
		if slot.get("icon_path", "") != "":
			btn.icon = load(slot.icon_path)

func get_selected_item() -> Dictionary:
	var slot = slots[selected_slot]
	if slot == null or slot is AbilityBase:
		return {}
	return slot

func set_slot(index: int, item_data) -> void:
	slots[index] = item_data
	_refresh_slot(index)

func set_ability(index: int, ability: AbilityBase) -> void:
	slots[index] = ability
	_refresh_slot(index)
