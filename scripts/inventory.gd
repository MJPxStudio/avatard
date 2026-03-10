extends CanvasLayer

# ============================================================
# INVENTORY — Draggable window, 42 slots
# Left click + drag  — move items between slots
# Double left click  — smart action (use / equip)
# Right click        — context menu (Use / Equip / Drop)
# ============================================================

const SPRITE_SIZE  = Vector2(194, 212)
const SLOT_SIZE    = Vector2(18, 18)
const SCALE        = 1.0
const MAX_STACK    = 999
const DRAG_THRESHOLD = 4.0   # pixels of movement before drag starts

const SLOT_POSITIONS = [
	Vector2(14, 36),  Vector2(42, 36),  Vector2(70, 36),
	Vector2(106, 36), Vector2(134, 36), Vector2(162, 36),
	Vector2(14, 60),  Vector2(42, 60),  Vector2(70, 60),
	Vector2(106, 60), Vector2(134, 60), Vector2(162, 60),
	Vector2(14, 84),  Vector2(42, 84),  Vector2(70, 84),
	Vector2(106, 84), Vector2(134, 84), Vector2(162, 84),
	Vector2(14, 108), Vector2(42, 108), Vector2(70, 108),
	Vector2(106, 108),Vector2(134, 108),Vector2(162, 108),
	Vector2(14, 132), Vector2(42, 132), Vector2(70, 132),
	Vector2(106, 132),Vector2(134, 132),Vector2(162, 132),
	Vector2(14, 156), Vector2(42, 156), Vector2(70, 156),
	Vector2(106, 156),Vector2(134, 156),Vector2(162, 156),
	Vector2(14, 180), Vector2(42, 180), Vector2(70, 180),
	Vector2(106, 180),Vector2(134, 180),Vector2(162, 180),
]

var slots:        Array = []
var slot_buttons: Array = []
var window_root:  Control
var drag_bar:     Control
var equip_panel_ref: Node = null

# Window drag
var win_dragging: bool    = false
var win_drag_offset: Vector2 = Vector2.ZERO

# Item drag state
var held_item:       Dictionary = {}
var held_from_slot:  int        = -1
var held_label:      Label
var press_slot:      int        = -1   # slot where mouse went down
var press_pos:       Vector2    = Vector2.ZERO
var drag_active:     bool       = false  # true once past threshold

# Context menu
var _context_menu: Control = null

func _ready() -> void:
	slots.resize(42)
	slots.fill(null)
	_build_ui()
	visible = false
	for item_id in ["shirt1", "pants1", "kunai1", "hp_potion", "hp_potion", "antidote"]:
		var item = ItemDB.get_item(item_id)
		if not item.is_empty():
			add_item(item)

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	window_root = Control.new()
	window_root.size = SPRITE_SIZE * SCALE
	window_root.position = Vector2(76, 60)
	add_child(window_root)

	var bg = TextureRect.new()
	bg.texture = load("res://sprites/inventory/inventory.png")
	bg.size = SPRITE_SIZE * SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	window_root.add_child(bg)

	drag_bar = Control.new()
	drag_bar.size = Vector2(SPRITE_SIZE.x * SCALE, 30)
	drag_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_bar.gui_input.connect(_on_drag_input)
	window_root.add_child(drag_bar)

	for i in range(42):
		var btn = Button.new()
		btn.position = SLOT_POSITIONS[i] * SCALE
		btn.size = SLOT_SIZE * SCALE
		btn.flat = false
		btn.focus_mode = Control.FOCUS_NONE
		var sn = StyleBoxFlat.new(); sn.bg_color = Color(0,0,0,0)
		var sh = StyleBoxFlat.new(); sh.bg_color = Color(1,1,1,0.2)
		var sp = StyleBoxFlat.new(); sp.bg_color = Color(1,1,0,0.3)
		btn.add_theme_stylebox_override("normal",  sn)
		btn.add_theme_stylebox_override("hover",   sh)
		btn.add_theme_stylebox_override("pressed", sp)
		btn.add_theme_stylebox_override("focus",   sn)

		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.position = Vector2(2, btn.size.y - 12)
		lbl.size = Vector2(btn.size.x - 2, 12)

		var icon_rect = TextureRect.new()
		icon_rect.name           = "IconRect"
		icon_rect.size           = SLOT_SIZE * SCALE
		icon_rect.position       = Vector2.ZERO
		icon_rect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE

		btn.add_child(icon_rect)
		btn.add_child(lbl)
		window_root.add_child(btn)

		var idx = i
		btn.gui_input.connect(func(ev): _on_slot_input(idx, ev))
		slot_buttons.append(btn)

	held_label = Label.new()
	held_label.add_theme_font_size_override("font_size", 9)
	held_label.add_theme_color_override("font_color", Color.YELLOW)
	held_label.visible = false
	add_child(held_label)

# ── Input ─────────────────────────────────────────────────────────────────────

func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		win_dragging = event.pressed
		if win_dragging:
			win_drag_offset = window_root.get_global_mouse_position() - window_root.global_position
	elif event is InputEventMouseMotion and win_dragging:
		window_root.global_position = window_root.get_global_mouse_position() - win_drag_offset

func _on_slot_input(index: int, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if event.double_click:
				_close_context_menu()
				_cancel_drag()
				_smart_action(index)
				return
			_close_context_menu()
			# Begin press — drag activates once mouse moves past threshold
			press_slot = index
			press_pos  = event.global_position
			drag_active = false

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if drag_active or not held_item.is_empty():
				_cancel_drag()
			else:
				_open_context_menu(index)

	elif event is InputEventMouseMotion:
		if press_slot >= 0 and not drag_active:
			# Check if moved past threshold to start drag
			if event.global_position.distance_to(press_pos) >= DRAG_THRESHOLD:
				_start_drag(press_slot)
				drag_active = true

# ── Drag ─────────────────────────────────────────────────────────────────────

func _start_drag(index: int) -> void:
	if slots[index] == null:
		press_slot = -1
		return
	held_item      = slots[index].duplicate()
	slots[index]   = null
	held_from_slot = index
	held_label.text    = held_item.name
	held_label.visible = false  # cursor shows icon instead
	_refresh_slot(index)
	# Set cursor to item icon
	var icon_path = held_item.get("icon_path", "")
	if icon_path != "":
		var tex = load(icon_path)
		if tex:
			var cursor_size = Vector2(32, 32)
			Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, cursor_size * 0.5)

func _drop_on_slot(index: int) -> void:
	if held_item.is_empty():
		return
	var target = slots[index]
	if target == null:
		slots[index] = held_item.duplicate()
		_clear_held()
	elif target.id == held_item.id and target.get("stackable", true):
		var total = target.quantity + held_item.quantity
		if total <= MAX_STACK:
			target.quantity = total
			_clear_held()
		else:
			target.quantity    = MAX_STACK
			held_item.quantity = total - MAX_STACK
	else:
		var temp     = target.duplicate()
		slots[index] = held_item.duplicate()
		held_item    = temp
		held_label.text = held_item.name
	_refresh_slot(index)

func _cancel_drag() -> void:
	if held_from_slot >= 0 and not held_item.is_empty():
		slots[held_from_slot] = held_item.duplicate()
		_refresh_slot(held_from_slot)
	_clear_held()
	press_slot  = -1
	drag_active = false

func _clear_held() -> void:
	held_item      = {}
	held_from_slot = -1
	held_label.visible = false
	Input.set_custom_mouse_cursor(null)  # restore default cursor

# ── Smart action (double-click) ───────────────────────────────────────────────

func _smart_action(index: int) -> void:
	var item = slots[index]
	if item == null:
		return
	if item.get("use_effect") != null:
		_do_use(index)
	elif item.get("equip_slot", "") != "":
		_do_equip(index)

# ── Context menu ──────────────────────────────────────────────────────────────

func _open_context_menu(index: int) -> void:
	_close_context_menu()
	var item = slots[index]
	if item == null:
		return

	var options: Array = []
	if item.get("use_effect") != null:
		options.append(["Use",   func(): _do_use(index)])
	if item.get("equip_slot", "") != "":
		options.append(["Equip", func(): _do_equip(index)])
	options.append(["Drop", func(): _do_drop(index)])

	_context_menu = _build_context_menu(options)

	# Position: above the slot that was clicked, clamped inside window
	var slot_pos  = SLOT_POSITIONS[index] * SCALE
	var menu_size = Vector2(68, 22 * options.size() + 4)
	var mx = clamp(slot_pos.x, 0, window_root.size.x - menu_size.x)
	var my = clamp(slot_pos.y - menu_size.y - 2, 0, window_root.size.y - menu_size.y)
	_context_menu.position = Vector2(mx, my)
	window_root.add_child(_context_menu)

func _build_context_menu(options: Array) -> Control:
	var BTN_H = 22
	var BTN_W = 68
	var PAD   = 2

	var menu = Control.new()
	menu.z_index = 100

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.06, 0.04, 0.97)
	bg_style.set_border_width_all(1)
	bg_style.border_color = Color("ffd700")
	bg_style.set_corner_radius_all(2)

	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel", bg_style)
	panel.size = Vector2(BTN_W + PAD * 2, BTN_H * options.size() + PAD * 2)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(panel)

	for i in range(options.size()):
		var label_text = options[i][0] as String
		var cb         = options[i][1]

		var btn = Button.new()
		btn.text = label_text
		btn.size = Vector2(BTN_W, BTN_H)
		btn.position = Vector2(PAD, PAD + i * BTN_H)
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_color_override("font_color", Color.WHITE)

		var sn = StyleBoxFlat.new(); sn.bg_color = Color(0,0,0,0)
		var sh = StyleBoxFlat.new()
		sh.bg_color = Color("ffd700")
		sh.set_corner_radius_all(2)
		btn.add_theme_stylebox_override("normal", sn)
		btn.add_theme_stylebox_override("hover",  sh)
		btn.add_theme_color_override("font_hover_color", Color.BLACK)
		# Action: run callback THEN close menu
		btn.pressed.connect(func():
			cb.call()
			_close_context_menu()
		)
		menu.add_child(btn)

	return menu

func _close_context_menu() -> void:
	if _context_menu != null and is_instance_valid(_context_menu):
		_context_menu.queue_free()
	_context_menu = null

# _input fires before any Control — needed so mouse release is never eaten by buttons
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if drag_active or not held_item.is_empty():
			_handle_global_release(event.global_position)

# _unhandled_input for context menu — fires only after Controls, so button presses close it
func _unhandled_input(event: InputEvent) -> void:
	if _context_menu == null:
		return
	if event is InputEventMouseButton and event.pressed:
		_close_context_menu()

func _handle_global_release(global_pos: Vector2) -> void:
	drag_active = false
	press_slot  = -1
	if held_item.is_empty():
		return
	# 1. Check inventory slots
	for i in range(42):
		var btn = slot_buttons[i]
		if Rect2(btn.global_position, btn.size).has_point(global_pos):
			_drop_on_slot(i)
			return
	# 2. Check hotbar
	var hotbar = _get_hotbar()
	if hotbar and hotbar.has_method("try_accept_drop"):
		if hotbar.try_accept_drop(held_item, global_pos):
			# Item copied to hotbar — keep it in inventory, just clear drag
			_put_back_held()
			return
	# 3. Nothing hit — return item to original slot
	_cancel_drag()

func _put_back_held() -> void:
	# Returns held item to its origin slot without treating it as a cancel
	if held_from_slot >= 0 and not held_item.is_empty():
		slots[held_from_slot] = held_item.duplicate()
		_refresh_slot(held_from_slot)
	_clear_held()

func _get_hotbar() -> Node:
	var player = get_tree().get_first_node_in_group("local_player")
	if player == null:
		return null
	return player.get("hotbar")

# ── Actions ───────────────────────────────────────────────────────────────────

func _do_use(index: int) -> void:
	var item = slots[index]
	if item == null:
		return
	var player = get_tree().get_first_node_in_group("local_player")
	if player and player.has_method("use_item"):
		player.use_item(item)
		_refresh_slot(index)

func _do_equip(index: int) -> void:
	var item = slots[index]
	if item == null or equip_panel_ref == null:
		return
	var displaced = equip_panel_ref.equip_item(item)
	slots[index] = null
	_refresh_slot(index)
	if not displaced.is_empty():
		slots[index] = displaced
		_refresh_slot(index)

func _do_drop(index: int) -> void:
	slots[index] = null
	_refresh_slot(index)

# ── Process ───────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not held_item.is_empty():
		held_label.global_position = get_viewport().get_mouse_position() + Vector2(8, 8)

# ── Slot refresh ──────────────────────────────────────────────────────────────

func _refresh_slot(index: int) -> void:
	var btn  = slot_buttons[index]
	var icon = btn.get_node("IconRect") as TextureRect
	var lbl  = btn.get_child(1) as Label
	var item = slots[index]
	if item == null:
		icon.texture = null; lbl.text = ""; btn.tooltip_text = ""
		return
	lbl.text = str(item.quantity) if item.get("stackable", true) and item.quantity > 1 else ""
	var tip = item.name
	for k in item.get("stat_bonuses", {}):
		if item.stat_bonuses[k] != 0:
			tip += "\n  +%d %s" % [item.stat_bonuses[k], k.capitalize()]
	match item.get("use_effect", {}).get("type", ""):
		"heal_hp":     tip += "\nRestores %d HP" % item.use_effect.get("amount", 0)
		"cure_poison": tip += "\nCures poison"
	btn.tooltip_text = tip
	if item.get("icon_path", "") != "":
		icon.texture  = load(item.icon_path)
		icon.modulate = item.get("tint", Color("ffffff"))
		var sf: float = item.get("icon_scale", 1.0)
		var isz = SLOT_SIZE * SCALE * sf
		icon.size     = isz
		icon.position = (SLOT_SIZE * SCALE - isz) * 0.5 + item.get("icon_offset", Vector2.ZERO)

func refresh_slot(index: int) -> void: _refresh_slot(index)
func refresh_all() -> void:
	for i in range(42): _refresh_slot(i)

# ── Public API ────────────────────────────────────────────────────────────────

func add_item(item_data: Dictionary) -> bool:
	if item_data.get("stackable", true):
		for i in range(42):
			if slots[i] != null and slots[i].id == item_data.id:
				var space = MAX_STACK - slots[i].quantity
				if space > 0:
					slots[i].quantity += min(item_data.quantity, space)
					_refresh_slot(i)
					return true
	for i in range(42):
		if slots[i] == null:
			slots[i] = item_data.duplicate()
			_refresh_slot(i)
			return true
	return false

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
	if not visible:
		_close_context_menu()
		_cancel_drag()
