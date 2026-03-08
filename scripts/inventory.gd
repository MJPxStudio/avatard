extends CanvasLayer

# ============================================================
# INVENTORY — Draggable window, 42 slots, sprite-based
# ============================================================

const SPRITE_SIZE  = Vector2(194, 212)
const SLOT_SIZE    = Vector2(18, 18)
const SCALE        = 1.0

# Slot positions in sprite space (x, y) — 7 rows x 6 cols
const SLOT_POSITIONS = [
	# Row 0
	Vector2(14, 36),  Vector2(42, 36),  Vector2(70, 36),
	Vector2(106, 36), Vector2(134, 36), Vector2(162, 36),
	# Row 1
	Vector2(14, 60),  Vector2(42, 60),  Vector2(70, 60),
	Vector2(106, 60), Vector2(134, 60), Vector2(162, 60),
	# Row 2
	Vector2(14, 84),  Vector2(42, 84),  Vector2(70, 84),
	Vector2(106, 84), Vector2(134, 84), Vector2(162, 84),
	# Row 3
	Vector2(14, 108), Vector2(42, 108), Vector2(70, 108),
	Vector2(106, 108),Vector2(134, 108),Vector2(162, 108),
	# Row 4
	Vector2(14, 132), Vector2(42, 132), Vector2(70, 132),
	Vector2(106, 132),Vector2(134, 132),Vector2(162, 132),
	# Row 5
	Vector2(14, 156), Vector2(42, 156), Vector2(70, 156),
	Vector2(106, 156),Vector2(134, 156),Vector2(162, 156),
	# Row 6
	Vector2(14, 180), Vector2(42, 180), Vector2(70, 180),
	Vector2(106, 180),Vector2(134, 180),Vector2(162, 180),
]

const MAX_STACK = 999

# Inventory data — array of {id, name, quantity, stackable, icon_path}
# null = empty slot
var slots: Array = []

# UI nodes
var window_root:  Control
var drag_bar:     Control
var bg_texture:   TextureRect
var slot_buttons: Array = []

var equip_panel_ref: Node = null

# Drag state
var is_dragging:    bool    = false
var drag_offset:    Vector2 = Vector2.ZERO

# Item being dragged between slots
var held_item:      Dictionary = {}
var held_from_slot: int = -1
var held_label:     Label

func _ready() -> void:
	# Init empty slots
	slots.resize(42)
	slots.fill(null)

	_build_ui()
	visible = false

	# Test items
	add_item({"id": "potion",     "name": "Potion",     "quantity": 5,  "stackable": true,  "icon_path": ""})
	add_item({"id": "kunai",      "name": "Kunai",      "quantity": 10, "stackable": true,  "icon_path": ""})
	add_item({"id": "iron_sword", "name": "Iron Sword", "quantity": 1,  "stackable": false, "icon_path": "",
		"equip_slot": "weapon", "stat_bonuses": {"strength": 5, "dex": 2}})
	add_item({"id": "leather_helm", "name": "Leather Helm", "quantity": 1, "stackable": false, "icon_path": "",
		"equip_slot": "head", "stat_bonuses": {"hp": 3}})

func _build_ui() -> void:
	# Root control — draggable window
	window_root = Control.new()
	window_root.size = SPRITE_SIZE * SCALE
	window_root.position = Vector2(76, 60)
	add_child(window_root)

	# Background sprite
	bg_texture = TextureRect.new()
	bg_texture.texture = load("res://sprites/inventory/inventory.png")
	bg_texture.size = SPRITE_SIZE * SCALE
	bg_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_texture.stretch_mode = TextureRect.STRETCH_SCALE
	window_root.add_child(bg_texture)

	# Drag bar — top strip of the window
	drag_bar = Control.new()
	drag_bar.size = Vector2(SPRITE_SIZE.x * SCALE, 30)
	drag_bar.position = Vector2.ZERO
	drag_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	window_root.add_child(drag_bar)

	# Slot buttons
	for i in range(42):
		var sp = SLOT_POSITIONS[i]
		var btn = Button.new()
		btn.position = sp * SCALE
		btn.size = SLOT_SIZE * SCALE
		btn.flat = false
		btn.focus_mode = Control.FOCUS_NONE
		# Normal style — transparent
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override("normal", style_normal)
		# Hover style
		var style_hover = StyleBoxFlat.new()
		style_hover.bg_color = Color(1, 1, 1, 0.2)
		btn.add_theme_stylebox_override("hover", style_hover)
		# Pressed style
		var style_pressed = StyleBoxFlat.new()
		style_pressed.bg_color = Color(1, 1, 0, 0.3)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		# Focus style — also transparent
		btn.add_theme_stylebox_override("focus", style_normal)

		# Stack count label
		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.position = Vector2(2, btn.size.y - 12)
		lbl.size = Vector2(btn.size.x - 2, 12)
		lbl.text = ""
		btn.add_child(lbl)

		var slot_index = i
		btn.pressed.connect(func(): _on_slot_clicked(slot_index))
		btn.gui_input.connect(func(event): _on_slot_input(slot_index, event))

		window_root.add_child(btn)
		slot_buttons.append(btn)

	# Held item label (floats with cursor)
	held_label = Label.new()
	held_label.add_theme_font_size_override("font_size", 9)
	held_label.add_theme_color_override("font_color", Color.YELLOW)
	held_label.visible = false
	add_child(held_label)

	# Drag input for window title bar
	drag_bar.gui_input.connect(_on_drag_input)

func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			if is_dragging:
				drag_offset = window_root.get_global_mouse_position() - window_root.global_position
	elif event is InputEventMouseMotion and is_dragging:
		window_root.global_position = window_root.get_global_mouse_position() - drag_offset

func _on_slot_clicked(index: int) -> void:
	if held_item.is_empty():
		# Pick up item from slot
		if slots[index] != null:
			held_item = slots[index].duplicate()
			slots[index] = null
			held_from_slot = index
			held_label.text = held_item.name
			held_label.visible = true
			_refresh_slot(index)
	else:
		# Place held item into slot
		var target = slots[index]
		if target == null:
			# Empty slot — place item
			slots[index] = held_item.duplicate()
			held_item = {}
			held_from_slot = -1
			held_label.visible = false
		elif target.id == held_item.id and target.get("stackable", true):
			# Same stackable item — merge
			var total = target.quantity + held_item.quantity
			if total <= MAX_STACK:
				target.quantity = total
				held_item = {}
				held_from_slot = -1
				held_label.visible = false
			else:
				target.quantity = MAX_STACK
				held_item.quantity = total - MAX_STACK
		else:
			# Swap items
			var temp = target.duplicate()
			slots[index] = held_item.duplicate()
			held_item = temp
			held_label.text = held_item.name
		_refresh_slot(index)

func _on_slot_input(index: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not held_item.is_empty():
			# Cancel drag, return to original slot
			if held_from_slot >= 0:
				slots[held_from_slot] = held_item.duplicate()
				_refresh_slot(held_from_slot)
			held_item = {}
			held_from_slot = -1
			held_label.visible = false
		elif slots[index] != null and slots[index].get("equip_slot", "") != "":
			# Right-click equippable item — send to equip panel
			if equip_panel_ref:
				var item = slots[index].duplicate()
				var displaced = equip_panel_ref.equip_item(item)
				slots[index] = null
				_refresh_slot(index)
				# If something was in that slot, put it back in inventory
				if not displaced.is_empty():
					slots[index] = displaced
					_refresh_slot(index)

func _process(_delta: float) -> void:
	if not held_item.is_empty():
		held_label.global_position = get_viewport().get_mouse_position() + Vector2(8, 8)

func _refresh_slot(index: int) -> void:
	var btn = slot_buttons[index]
	var lbl = btn.get_child(0) as Label
	var item = slots[index]
	if item == null:
		lbl.text = ""
		btn.icon = null
		btn.tooltip_text = ""
	else:
		lbl.text = str(item.quantity) if item.get("stackable", true) and item.quantity > 1 else ""
		var tip = item.name
		var bonuses = item.get("stat_bonuses", {})
		for k in bonuses:
			if bonuses[k] != 0:
				tip += "\n  +%d %s" % [bonuses[k], k.capitalize()]
		if item.get("equip_slot", "") != "":
			tip += "\n[Right-click to equip]"
		btn.tooltip_text = tip
		if item.get("icon_path", "") != "":
			btn.icon = load(item.icon_path)

func refresh_all() -> void:
	for i in range(42):
		_refresh_slot(i)

# ── PUBLIC API ───────────────────────────────────────────────

func add_item(item_data: Dictionary) -> bool:
	# Try to stack first
	if item_data.get("stackable", true):
		for i in range(42):
			if slots[i] != null and slots[i].id == item_data.id:
				var space = MAX_STACK - slots[i].quantity
				if space > 0:
					slots[i].quantity += min(item_data.quantity, space)
					_refresh_slot(i)
					return true

	# Find empty slot
	for i in range(42):
		if slots[i] == null:
			slots[i] = item_data.duplicate()
			_refresh_slot(i)
			return true

	return false  # Inventory full

func remove_item(item_id: String, quantity: int = 1) -> bool:
	for i in range(42):
		if slots[i] != null and slots[i].id == item_id:
			slots[i].quantity -= quantity
			if slots[i].quantity <= 0:
				slots[i] = null
			_refresh_slot(i)
			return true
	return false

func has_item(item_id: String, quantity: int = 1) -> bool:
	var total = 0
	for slot in slots:
		if slot != null and slot.id == item_id:
			total += slot.quantity
	return total >= quantity

func toggle() -> void:
	visible = !visible
