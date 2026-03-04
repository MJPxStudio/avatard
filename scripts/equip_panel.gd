extends CanvasLayer

# ============================================================
# EQUIPMENT PANEL — 6 slots, single column, draggable window
# ============================================================

const SPRITE_SIZE  = Vector2(64, 212)
const SLOT_SIZE    = Vector2(33, 32)
const SCALE        = 1.0

# 6 slots, single column, no gap
const SLOT_POSITIONS = [
	Vector2(15, 9),
	Vector2(15, 41),
	Vector2(15, 73),
	Vector2(15, 105),
	Vector2(15, 137),
	Vector2(15, 169),
]

# Slot names for tooltip context
const SLOT_NAMES = ["Head", "Chest", "Legs", "Feet", "Weapon", "Offhand"]

var slots: Array = []
var slot_buttons: Array = []

# Drag state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var window_root: Control

func _ready() -> void:
	slots.resize(6)
	slots.fill(null)
	_build_ui()
	visible = false

func _build_ui() -> void:
	window_root = Control.new()
	window_root.size = SPRITE_SIZE * SCALE
	window_root.position = Vector2(8, 60)
	add_child(window_root)

	var bg = TextureRect.new()
	bg.texture = load("res://sprites/equip/equip_panel.png")
	bg.size = SPRITE_SIZE * SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	window_root.add_child(bg)

	# Drag bar — full width top strip
	var drag_bar = Control.new()
	drag_bar.size = Vector2(SPRITE_SIZE.x * SCALE, 20)
	drag_bar.position = Vector2.ZERO
	drag_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_bar.gui_input.connect(_on_drag_input)
	window_root.add_child(drag_bar)

	for i in range(6):
		var sp = SLOT_POSITIONS[i]
		var btn = Button.new()
		btn.position = sp * SCALE
		btn.size = SLOT_SIZE * SCALE
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = SLOT_NAMES[i]

		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override("normal", style_normal)

		var style_hover = StyleBoxFlat.new()
		style_hover.bg_color = Color(1, 1, 1, 0.2)
		btn.add_theme_stylebox_override("hover", style_hover)

		var style_pressed = StyleBoxFlat.new()
		style_pressed.bg_color = Color(1, 1, 0, 0.3)
		btn.add_theme_stylebox_override("pressed", style_pressed)

		btn.add_theme_stylebox_override("focus", style_normal)

		var slot_index = i
		btn.pressed.connect(func(): _on_slot_clicked(slot_index))

		window_root.add_child(btn)
		slot_buttons.append(btn)

func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_dragging = event.pressed
		if is_dragging:
			drag_offset = window_root.get_global_mouse_position() - window_root.global_position
	elif event is InputEventMouseMotion and is_dragging:
		window_root.global_position = window_root.get_global_mouse_position() - drag_offset

func _on_slot_clicked(index: int) -> void:
	# Will hook into inventory drag system later
	pass

func _refresh_slot(index: int) -> void:
	var btn = slot_buttons[index]
	var item = slots[index]
	if item == null:
		btn.icon = null
		btn.tooltip_text = SLOT_NAMES[index]
	else:
		btn.tooltip_text = SLOT_NAMES[index] + ": " + item.name
		if item.get("icon_path", "") != "":
			btn.icon = load(item.icon_path)

func equip(index: int, item_data: Dictionary) -> void:
	slots[index] = item_data
	_refresh_slot(index)

func unequip(index: int) -> Dictionary:
	var item = slots[index]
	slots[index] = null
	_refresh_slot(index)
	return item if item != null else {}

func toggle() -> void:
	visible = !visible
