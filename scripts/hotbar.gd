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
signal loadout_changed
var slot_buttons: Array = []
var cooldown_overlays: Array = []
var cooldown_labels:   Array = []
var selected_slot: int = 0
var player_ref:    Node = null
var cast_bar:      Node = null  # set by main.gd after setup
var _casting:      bool = false  # block new casts while one is active

func _ready() -> void:
	slots.resize(10)
	slots.fill(null)
	_build_ui()

func set_player(player: Node) -> void:
	player_ref = player

func _make_slot_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color    = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.anti_aliasing = true
	return s

func _build_ui() -> void:
	const SLOT_W   = 36
	const SLOT_H   = 36
	const SLOT_GAP = 4
	const SLOTS    = 10
	const PAD      = 6
	var total_w = SLOTS * SLOT_W + (SLOTS - 1) * SLOT_GAP + PAD * 2
	var total_h = SLOT_H + PAD * 2

	var root = Control.new()
	root.size     = Vector2(total_w, total_h)
	root.position = Vector2(
		(960 - total_w) / 2.0,
		540 - total_h - 4
	)
	add_child(root)

	# Panel background
	var panel_s = StyleBoxFlat.new()
	panel_s.bg_color      = UITheme.color("panel_bg")
	panel_s.border_color  = UITheme.color("panel_border")
	panel_s.set_border_width_all(2)
	panel_s.set_corner_radius_all(5)
	panel_s.shadow_color  = Color(0, 0, 0, 0.5)
	panel_s.shadow_size   = 5
	panel_s.anti_aliasing = true
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_s)
	panel.size = Vector2(total_w, total_h)
	root.add_child(panel)

	# Gold accent line at top
	var accent = ColorRect.new()
	accent.color    = UITheme.color("panel_accent")
	accent.size     = Vector2(total_w - 4, 1)
	accent.position = Vector2(2, 2)
	root.add_child(accent)

	for i in range(10):
		var slot_x = PAD + i * (SLOT_W + SLOT_GAP)
		var slot_y = PAD

		# Slot background
		var slot_bg = PanelContainer.new()
		slot_bg.add_theme_stylebox_override("panel",
			_make_slot_style(UITheme.color("bar_bg"), UITheme.color("panel_border")))
		slot_bg.size     = Vector2(SLOT_W, SLOT_H)
		slot_bg.position = Vector2(slot_x, slot_y)
		root.add_child(slot_bg)

		var btn = Button.new()
		btn.position   = Vector2(slot_x, slot_y)
		btn.size       = Vector2(SLOT_W, SLOT_H)
		btn.focus_mode = Control.FOCUS_NONE

		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("focus",  style_normal)

		var style_hover = StyleBoxFlat.new()
		style_hover.bg_color    = UITheme.color("hover_bg")
		style_hover.border_color = UITheme.color("panel_accent")
		style_hover.set_border_width_all(1)
		style_hover.set_corner_radius_all(3)
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
		cd.color        = UITheme.color("cooldown_overlay")
		cd.size         = Vector2(0, SLOT_SIZE.y * SCALE)
		cd.position     = Vector2(2, 2)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.z_index      = 5
		btn.add_child(cd)
		cooldown_overlays.append(cd)

		# Cooldown number label (shows seconds remaining)
		var cd_lbl = Label.new()
		cd_lbl.add_theme_font_size_override("font_size", 10)
		cd_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		cd_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		cd_lbl.add_theme_constant_override("shadow_offset_x", 1)
		cd_lbl.add_theme_constant_override("shadow_offset_y", 1)
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.size       = Vector2(SLOT_SIZE.x * SCALE, SLOT_SIZE.y * SCALE)
		cd_lbl.z_index    = 6
		cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(cd_lbl)
		cooldown_labels.append(cd_lbl)

		var slot_index = i
		btn.pressed.connect(func(): _on_slot_clicked(slot_index))
		root.add_child(btn)
		slot_buttons.append(btn)

	_highlight_selected()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		for i in range(10):
			var key = KEY_1 + i if i < 9 else KEY_0
			if event.keycode == key:
				if event.pressed and not event.echo:
					selected_slot = i
					_highlight_selected()
					_use_selected_slot()
					return
				elif not event.pressed:
					# Key released — fire any pending charge on this slot
					if player_ref != null and player_ref.has_method("end_charge"):
						player_ref.end_charge(i)
					return
	if Input.is_action_just_pressed("doujutsu"):
		_activate_tagged("doujutsu")
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
		if cooldown_labels.size() > i:
			var cd_lbl = cooldown_labels[i]
			if slot.current_cooldown > 0.05:
				cd_lbl.text = "%.1f" % slot.current_cooldown
			else:
				cd_lbl.text = ""

func _begin_cast(slot: AbilityBase) -> void:
	print("[CAST] _begin_cast: %s ct=%.2f casting=%s bar=%s" % [slot.ability_name, slot.cast_time if "cast_time" in slot else 0.0, str(_casting), str(cast_bar)])
	if _casting:
		return
	var ct: float = slot.cast_time if "cast_time" in slot else 0.0
	if ct <= 0.0:
		slot.activate(player_ref)
		return
	_casting = true
	var stand_still: bool = slot.cast_stand_still if "cast_stand_still" in slot else false
	if stand_still and player_ref and player_ref.has_method("set_escort_locked"):
		player_ref.set_escort_locked(true)
	var unlock = func():
		if stand_still and player_ref and player_ref.has_method("set_escort_locked"):
			player_ref.set_escort_locked(false)
		_casting = false
	if cast_bar:
		cast_bar.begin_cast(player_ref, ct, slot.ability_name,
			func():
				unlock.call()
				if player_ref and not player_ref.get("is_rooted") and not player_ref.get("is_dead"):
					slot.activate(player_ref),
			unlock
		)
	else:
		unlock.call()
		slot.activate(player_ref)

func _activate_tagged(tag: String) -> void:
	if player_ref == null:
		return
	if player_ref.has_method("is_ability_locked") and player_ref.is_ability_locked():
		return
	for slot in slots:
		if slot is AbilityBase and "tags" in slot and tag in slot.tags:
			_begin_cast(slot)
			return

func _use_selected_slot() -> void:
	var slot = slots[selected_slot]
	if slot == null:
		return
	if slot is AbilityBase:
		if player_ref != null:
			# Block all abilities while locked (rooted, spinning, stunned, etc.)
			if player_ref.has_method("is_ability_locked") and player_ref.is_ability_locked():
				return
			# Hold-to-charge abilities: begin_charge on press, fire on release
			if slot.activation == "hold":
				player_ref.begin_charge(selected_slot, slot)
				return
			_begin_cast(slot)
	elif slot is Dictionary and slot.has("use_effect"):
		# Consumable item
		if player_ref and player_ref.has_method("use_item"):
			player_ref.use_item(slot)
			# Clear slot if item is now gone from inventory
			var inv = player_ref.inventory if player_ref.get("inventory") != null else null
			if inv and not inv.has_item(slot.get("id", ""), 1):
				slots[selected_slot] = null
				_refresh_slot(selected_slot)

func _on_slot_clicked(index: int) -> void:
	selected_slot = index
	_highlight_selected()
	_use_selected_slot()

func _highlight_selected() -> void:
	for i in range(10):
		var btn   = slot_buttons[i]
		var style = StyleBoxFlat.new()
		if i == selected_slot:
			style.bg_color         = UITheme.color("selected_bg")
			style.border_width_top    = 1
			style.border_width_bottom = 1
			style.border_width_left   = 1
			style.border_width_right  = 1
			style.border_color     = UITheme.color("selected_border")
		else:
			style.bg_color = Color(0, 0, 0, 0)
		btn.add_theme_stylebox_override("normal", style)

func refresh_all_slots() -> void:
	for i in range(slots.size()):
		_refresh_slot(i)

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
		# Ability slot — show boon-modified values if in a dungeon
		var display_cost: int   = slot.chakra_cost
		var display_cd:   float = slot.cooldown
		var boon_lines:   Array = []
		if player_ref:
			var cost_mult = player_ref.get("boon_chakra_cost_mult")
			if cost_mult != null and cost_mult != 1.0:
				display_cost = max(1, int(slot.chakra_cost * cost_mult))
				boon_lines.append("  Chakra: %d (%.0f%%)" % [display_cost, cost_mult * 100.0])
			var cd_key = ""
			var aname = slot.ability_name.to_lower()
			if "c1" in aname or "spider" in aname:   cd_key = "boon_c1_cooldown_flat"
			elif "c2" in aname or "owl" in aname:    cd_key = "boon_c2_cooldown_flat"
			elif "c3" in aname or "bomb" in aname:   cd_key = "boon_c3_cooldown_flat"
			elif "c4" in aname or "karura" in aname: cd_key = "boon_c4_cooldown_flat"
			if cd_key != "":
				var cd_bonus = player_ref.get(cd_key)
				if cd_bonus != null and cd_bonus != 0.0:
					display_cd = max(0.2, slot.cooldown + cd_bonus)
					boon_lines.append("  CD: %.1fs (%+.1fs)" % [display_cd, cd_bonus])
		var tip = "%s\nChakra: %d  CD: %.1fs\n%s" % [slot.ability_name, display_cost, display_cd, slot.description]
		if not boon_lines.is_empty():
			tip += "\n[Boon Effects]\n" + "\n".join(boon_lines)
		btn.tooltip_text = tip
		if slot.icon_path != "" and ResourceLoader.exists(slot.icon_path):
			icon_bg.color = Color(0, 0, 0, 0)
			btn.icon      = load(slot.icon_path)
			btn.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 1))
			btn.expand_icon = true
			lbl.text = ""
		else:
			btn.icon      = null
			icon_bg.color = slot.icon_color.darkened(0.3)
			var short = slot.ability_name.left(4)
			lbl.text  = short
	else:
		# Item slot
		lbl.text = str(slot.quantity) if slot.get("stackable", true) and slot.quantity > 1 else ""
		btn.tooltip_text = slot.name
		icon_bg.color    = Color(0, 0, 0, 0)
		if slot.get("icon_path", "") != "":
			btn.icon = load(slot.icon_path)
			btn.add_theme_color_override("icon_normal_color", slot.get("tint", Color("ffffff")))
		else:
			btn.remove_theme_color_override("icon_normal_color")

func get_selected_item() -> Dictionary:
	var slot = slots[selected_slot]
	if slot == null or slot is AbilityBase:
		return {}
	return slot

func get_root_node() -> Control:
	return get_child(0)

func try_accept_drop(item: Dictionary, global_pos: Vector2) -> bool:
	# Only consumables go on hotbar
	if item.get("use_effect") == null:
		return false
	var root = get_root_node()
	if root == null:
		return false
	for i in range(10):
		var btn = slot_buttons[i]
		var rect = Rect2(btn.global_position, btn.size)
		if rect.has_point(global_pos):
			slots[i] = item.duplicate()
			_refresh_slot(i)
			return true
	return false

func set_slot(index: int, item_data) -> void:
	slots[index] = item_data
	_refresh_slot(index)

func set_ability(index: int, ability: AbilityBase) -> void:
	slots[index] = ability
	_refresh_slot(index)
	loadout_changed.emit()
