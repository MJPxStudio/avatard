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
const SLOT_NAMES   = ["Weapon", "Head", "Chest", "Legs", "Shoes", "Accessory"]
const SLOT_KEYS    = ["weapon", "head", "chest", "legs", "shoes", "accessory"]

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
		btn.gui_input.connect(func(ev): _on_slot_gui_input(slot_index, ev))

		window_root.add_child(btn)
		slot_buttons.append(btn)

func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_dragging = event.pressed
		if is_dragging:
			drag_offset = window_root.get_global_mouse_position() - window_root.global_position
	elif event is InputEventMouseMotion and is_dragging:
		window_root.global_position = window_root.get_global_mouse_position() - drag_offset

var player_ref: Node = null
var _context_menu: Control = null

func set_player(p: Node) -> void:
	player_ref = p

func _on_slot_gui_input(index: int, event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		_do_unequip(index)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_open_context_menu(index)

func _open_context_menu(index: int) -> void:
	_close_context_menu()
	var item = slots[index]
	if item == null:
		return
	var options = [
		["Unequip", func(): _do_unequip(index)],
		["Drop",    func(): _do_drop(index)],
	]
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
	panel.size = Vector2(BTN_W + PAD*2, BTN_H * options.size() + PAD*2)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(panel)
	for i in range(options.size()):
		var lbl_text = options[i][0] as String
		var cb       = options[i][1]
		var btn = Button.new()
		btn.text = lbl_text
		btn.size = Vector2(BTN_W, BTN_H)
		btn.position = Vector2(PAD, PAD + i * BTN_H)
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_color_override("font_color", Color.WHITE)
		var sn = StyleBoxFlat.new(); sn.bg_color = Color(0,0,0,0)
		var sh = StyleBoxFlat.new(); sh.bg_color = Color("ffd700"); sh.set_corner_radius_all(2)
		btn.add_theme_stylebox_override("normal", sn)
		btn.add_theme_stylebox_override("hover",  sh)
		btn.add_theme_color_override("font_hover_color", Color.BLACK)
		btn.pressed.connect(func(): cb.call(); _close_context_menu())
		menu.add_child(btn)
	var slot_pos  = SLOT_POSITIONS[index] * SCALE
	var menu_size = Vector2(BTN_W + PAD*2, BTN_H * options.size() + PAD*2)
	var mx = clamp(slot_pos.x, 0, window_root.size.x - menu_size.x)
	var my = clamp(slot_pos.y - menu_size.y - 2, 0, window_root.size.y - menu_size.y)
	menu.position = Vector2(mx, my)
	window_root.add_child(menu)
	_context_menu = menu

func _close_context_menu() -> void:
	if _context_menu != null and is_instance_valid(_context_menu):
		_context_menu.queue_free()
	_context_menu = null

func _unhandled_input(event: InputEvent) -> void:
	if _context_menu == null: return
	if event is InputEventMouseButton and event.pressed:
		_close_context_menu()

func _do_unequip(index: int) -> void:
	var item = slots[index]
	if item == null: return
	var inv = player_ref.inventory if player_ref and player_ref.get("inventory") else null
	if inv and inv.add_item(item):
		slots[index] = null
		_refresh_slot(index)
		_clear_equip_visuals(SLOT_KEYS[index])
		_send_equip_to_server()

func _do_drop(index: int) -> void:
	slots[index] = null
	_refresh_slot(index)
	_clear_equip_visuals(SLOT_KEYS[index])
	_send_equip_to_server()

func _refresh_slot(index: int) -> void:
	var btn  = slot_buttons[index]
	var item = slots[index]
	if item == null:
		btn.icon = null
		btn.remove_theme_color_override("icon_normal_color")
		btn.tooltip_text = SLOT_NAMES[index] + " (empty)"
	else:
		var bonuses = item.get("stat_bonuses", {})
		var tip = SLOT_NAMES[index] + ": " + item.name
		for k in bonuses:
			if bonuses[k] != 0:
				tip += "\n  +%d %s" % [bonuses[k], k.capitalize()]
		tip += "\n[Right-click to unequip/drop]"
		btn.tooltip_text = tip
		if item.get("icon_path", "") != "":
			btn.icon = load(item.icon_path)
			btn.add_theme_color_override("icon_normal_color", item.get("tint", Color("ffffff")))

func refresh_slot(index: int) -> void:
	_refresh_slot(index)

func _send_equip_to_server() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if not net or not net.is_network_connected():
		return
	var equipped: Dictionary = {}
	for i in range(6):
		if slots[i] != null:
			equipped[SLOT_KEYS[i]] = slots[i]
	net.send_equip_update.rpc_id(1, equipped)

func get_slot_for_item(item: Dictionary) -> int:
	var key = item.get("equip_slot", "")
	for i in range(SLOT_KEYS.size()):
		if SLOT_KEYS[i] == key:
			return i
	return -1

func equip_item(item: Dictionary) -> Dictionary:
	# Equip item, return any displaced item (for inventory to re-add)
	var idx = get_slot_for_item(item)
	if idx == -1:
		return item  # not equippable
	# Check rank requirement
	var min_rank: String = item.get("min_rank", "")
	if min_rank != "" and player_ref != null:
		var player_rank: String = player_ref.get("rank") if player_ref.get("rank") != null else "Academy Student"
		if not RankDB.meets_rank_requirement(player_rank, min_rank):
			# Show feedback in chat if available
			var chat = player_ref.get("chat") if player_ref else null
			if chat and chat.has_method("add_system_message"):
				chat.add_system_message("[Equip] Requires rank: %s" % min_rank)
			return item  # reject — return item so inventory keeps it
	var displaced = slots[idx]
	slots[idx] = item
	_refresh_slot(idx)
	_apply_equip_visuals(SLOT_KEYS[idx], item)
	_send_equip_to_server()
	return displaced if displaced != null else {}

func equip(index: int, item_data: Dictionary) -> void:
	slots[index] = item_data
	_refresh_slot(index)
	_apply_equip_visuals(SLOT_KEYS[index], item_data)
	_send_equip_to_server()

func unequip(index: int) -> Dictionary:
	var item = slots[index]
	slots[index] = null
	_refresh_slot(index)
	_clear_equip_visuals(SLOT_KEYS[index])
	_send_equip_to_server()
	return item if item != null else {}

func _apply_equip_visuals(slot_key: String, item: Dictionary) -> void:
	if player_ref == null or not is_instance_valid(player_ref):
		return
	var folder: String = item.get("sprite_folder", "")
	if folder == "":
		return
	var tint: Color = item.get("tint", Color("ffffff"))
	if player_ref.has_method("set_equip_layer"):
		player_ref.set_equip_layer(slot_key, folder, tint)

func _clear_equip_visuals(slot_key: String) -> void:
	if player_ref == null or not is_instance_valid(player_ref):
		return
	if player_ref.has_method("clear_equip_layer"):
		player_ref.clear_equip_layer(slot_key)

func get_all_equipped() -> Dictionary:
	var out: Dictionary = {}
	for i in range(6):
		if slots[i] != null:
			out[SLOT_KEYS[i]] = slots[i]
	return out

func toggle() -> void:
	visible = !visible
