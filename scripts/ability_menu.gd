extends CanvasLayer

# ============================================================
# ABILITY MENU — shows all unlocked abilities, lets you
# assign them to hotbar slots.
#
# Usage:
#   - Open with K (or whatever action "ability_menu" is bound to)
#   - Click an ability card to select it (highlighted in gold)
#   - Click a hotbar slot button (1-10) to assign it there
#   - Click an occupied slot button again to clear it
#   - Right-click an ability card to remove it from whatever slot it's in
# ============================================================

const C_BG      := Color(0.07, 0.05, 0.04, 0.97)
const C_PANEL   := Color(0.12, 0.09, 0.07, 1.0)
const C_BORDER  := Color("ffd700")
const C_TEXT    := Color("e8e0d0")
const C_DIM     := Color("888070")
const C_GOLD    := Color("ffd700")
const C_SEL     := Color("ffd700")
const C_EMPTY   := Color(0.2, 0.18, 0.15, 1.0)

var player_ref:  Node   = null
var hotbar_ref:  Node   = null
var _root:       Control
var _ability_list: VBoxContainer
var _slot_btns:  Array  = []
var _detail_lbl: Label
var _selected_id: String = ""   # ability id currently selected

func _ready() -> void:
	visible = false
	_build_ui()

func set_player(p: Node) -> void:
	player_ref = p
	hotbar_ref = p.get("hotbar")

func toggle() -> void:
	visible = !visible
	if visible:
		_refresh()

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Backdrop — semi-transparent, does not block input to game
	var win_style = StyleBoxFlat.new()
	win_style.bg_color = C_BG
	win_style.set_border_width_all(2)
	win_style.border_color = C_BORDER
	win_style.set_corner_radius_all(4)

	var win = Panel.new()
	win.add_theme_stylebox_override("panel", win_style)
	win.size     = Vector2(580, 440)
	win.position = Vector2(190, 50)
	_root.add_child(win)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + s, 12)
	win.add_child(margin)

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)

	# Title row
	var title_row = HBoxContainer.new()
	outer.add_child(title_row)
	var title = Label.new()
	title.text = "ABILITY MENU"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var hint = Label.new()
	hint.text = "[K] close"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", C_DIM)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(hint)

	outer.add_child(HSeparator.new())

	# Main row
	var main_row = HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 10)
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(main_row)

	# Left: ability list
	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(290, 0)
	left.add_theme_constant_override("separation", 4)
	main_row.add_child(left)

	var list_title = Label.new()
	list_title.text = "UNLOCKED ABILITIES"
	list_title.add_theme_font_size_override("font_size", 9)
	list_title.add_theme_color_override("font_color", C_DIM)
	left.add_child(list_title)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	_ability_list = VBoxContainer.new()
	_ability_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ability_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_ability_list)

	# Right: detail + slot assignment
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	main_row.add_child(right)

	var detail_title = Label.new()
	detail_title.text = "DETAILS"
	detail_title.add_theme_font_size_override("font_size", 9)
	detail_title.add_theme_color_override("font_color", C_DIM)
	right.add_child(detail_title)

	_detail_lbl = Label.new()
	_detail_lbl.text = "Select an ability to see details."
	_detail_lbl.add_theme_font_size_override("font_size", 10)
	_detail_lbl.add_theme_color_override("font_color", C_TEXT)
	_detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_detail_lbl)

	right.add_child(HSeparator.new())

	# Hotbar slot buttons
	var slot_title = Label.new()
	slot_title.text = "ASSIGN TO SLOT"
	slot_title.add_theme_font_size_override("font_size", 9)
	slot_title.add_theme_color_override("font_color", C_DIM)
	right.add_child(slot_title)

	var slot_grid = GridContainer.new()
	slot_grid.columns = 5
	slot_grid.add_theme_constant_override("h_separation", 4)
	slot_grid.add_theme_constant_override("v_separation", 4)
	right.add_child(slot_grid)

	for i in range(10):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(44, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 9)
		var idx = i
		btn.pressed.connect(func(): _assign_to_slot(idx))
		slot_grid.add_child(btn)
		_slot_btns.append(btn)

	var clear_btn = Button.new()
	clear_btn.text = "Clear Selected Slot"
	clear_btn.add_theme_font_size_override("font_size", 9)
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_clear_selected_from_slots)
	right.add_child(clear_btn)

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if player_ref == null:
		return
	hotbar_ref = player_ref.get("hotbar")
	_rebuild_ability_list()
	_refresh_slot_buttons()

func _rebuild_ability_list() -> void:
	for c in _ability_list.get_children():
		c.queue_free()

	var unlocked: Array = player_ref.get("unlocked_abilities") if player_ref else []
	if unlocked.is_empty():
		var empty = Label.new()
		empty.text = "No abilities unlocked yet.\nFind ability scrolls in dungeons."
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", C_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_ability_list.add_child(empty)
		return

	# Group by source
	var by_source: Dictionary = {}
	for ab_id in unlocked:
		var ab = AbilityDB.get_ability(ab_id)
		if ab.is_empty():
			continue
		var src = ab.get("source", "other")
		if not by_source.has(src):
			by_source[src] = []
		by_source[src].append(ab)

	for src in by_source:
		# Section header
		var hdr = _make_section_header(src)
		_ability_list.add_child(hdr)
		for ab in by_source[src]:
			_ability_list.add_child(_make_ability_card(ab))

func _make_section_header(source_key: String) -> Label:
	var lbl = Label.new()
	var col := C_DIM
	if source_key.begins_with("clan:"):
		var cid = source_key.substr(5)
		var clan = ClanDB.get_clan(cid)
		lbl.text = clan.get("display_name", cid).to_upper() + " ABILITIES"
		col = clan.get("color", C_DIM)
	elif source_key.begins_with("element:"):
		var eid = source_key.substr(8)
		var el = ClanDB.get_element(eid)
		lbl.text = el.get("name", eid).to_upper() + " ABILITIES"
		col = el.get("color", C_DIM)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", col)
	return lbl

func _make_ability_card(ab: Dictionary) -> Button:
	var ab_id  = ab["id"] as String
	var col    = ab.get("icon_color", C_TEXT) as Color
	var is_sel = (ab_id == _selected_id)

	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size   = Vector2(0, 40)
	btn.focus_mode = Control.FOCUS_NONE

	var sn = _card_style(col, is_sel)
	var sh = _card_style(col, true)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sh)
	btn.add_theme_stylebox_override("focus",   sn)

	var ml = MarginContainer.new()
	ml.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left","right","top","bottom"]:
		ml.add_theme_constant_override("margin_" + s, 5)
	ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(ml)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ml.add_child(vb)

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)

	var name_lbl = Label.new()
	name_lbl.text = ab["name"]
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", col)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	# Show which slot it's in (if any)
	var slot_idx = _find_ability_slot(ab_id)
	if slot_idx >= 0:
		var slot_lbl = Label.new()
		slot_lbl.text = "[Slot %d]" % (slot_idx + 1)
		slot_lbl.add_theme_font_size_override("font_size", 9)
		slot_lbl.add_theme_color_override("font_color", C_GOLD)
		slot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot_lbl)

	var cost_lbl = Label.new()
	cost_lbl.text = "%d chakra  %.1fs cd" % [ab.get("chakra_cost", 0), ab.get("cooldown", 0.0)]
	cost_lbl.add_theme_font_size_override("font_size", 9)
	cost_lbl.add_theme_color_override("font_color", C_DIM)
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(cost_lbl)

	btn.pressed.connect(func(): _select_ability(ab_id, ab))
	btn.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			_clear_ability_from_slots(ab_id)
	)
	return btn

func _card_style(col: Color, selected: bool) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(3)
	s.set_border_width_all(1)
	if selected:
		s.bg_color     = col.darkened(0.4)
		s.border_color = col
	else:
		s.bg_color     = C_PANEL
		s.border_color = col.darkened(0.5)
	return s

# ── Selection & assignment ────────────────────────────────────────────────────

func _select_ability(ab_id: String, ab: Dictionary) -> void:
	_selected_id = ab_id
	_show_detail(ab)
	_rebuild_ability_list()   # re-highlight
	_refresh_slot_buttons()

func _show_detail(ab: Dictionary) -> void:
	var col = ab.get("icon_color", C_TEXT) as Color
	var min_rank = ab.get("min_rank", "")
	var rank_line = ("\nRequires: %s" % min_rank) if min_rank != "" and min_rank != "Academy Student" else ""
	var tags = ab.get("tags", [])
	var tag_line = ("\nTags: %s" % ", ".join(tags)) if not tags.is_empty() else ""
	_detail_lbl.add_theme_color_override("font_color", col)
	_detail_lbl.text = "%s\n\n%s\n\nChakra: %d\nCooldown: %.1fs%s%s" % [
		ab["name"], ab.get("description",""),
		ab.get("chakra_cost",0), ab.get("cooldown",0.0),
		rank_line, tag_line
	]

func _assign_to_slot(slot_idx: int) -> void:
	if _selected_id == "" or hotbar_ref == null:
		return
	var ab = AbilityDB.get_ability(_selected_id)
	if ab.is_empty():
		return
	var instance = AbilityDB.create_instance(_selected_id)
	if instance == null:
		return
	hotbar_ref.set_ability(slot_idx, instance)
	_refresh_slot_buttons()
	_rebuild_ability_list()
	_save_hotbar_loadout()

func _clear_selected_from_slots() -> void:
	if _selected_id != "":
		_clear_ability_from_slots(_selected_id)

func _clear_ability_from_slots(ab_id: String) -> void:
	if hotbar_ref == null:
		return
	for i in range(10):
		var slot = hotbar_ref.slots[i]
		if slot is AbilityBase and slot.has_meta("_ability_id") and slot.get_meta("_ability_id") == ab_id:
			hotbar_ref.set_slot(i, null)
	_refresh_slot_buttons()
	_rebuild_ability_list()
	_save_hotbar_loadout()

func _find_ability_slot(ab_id: String) -> int:
	if hotbar_ref == null:
		return -1
	for i in range(10):
		var slot = hotbar_ref.slots[i]
		if slot is AbilityBase and slot.has_meta("_ability_id") and slot.get_meta("_ability_id") == ab_id:
			return i
	return -1

func _refresh_slot_buttons() -> void:
	if hotbar_ref == null:
		return
	for i in range(10):
		var btn = _slot_btns[i]
		var slot = hotbar_ref.slots[i]
		var num  = str((i + 1) % 10)
		if slot == null:
			btn.text = "%s\n—" % num
			var sn = StyleBoxFlat.new()
			sn.bg_color = C_EMPTY
			sn.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", sn)
			btn.add_theme_color_override("font_color", C_DIM)
		elif slot is AbilityBase:
			var ab_id = slot.get_meta("_ability_id") if slot.has_meta("_ability_id") else ""
			var ab = AbilityDB.get_ability(ab_id) if ab_id else {}
			var short = (ab.get("name","?") as String).left(6) if not ab.is_empty() else slot.ability_name.left(6)
			btn.text = "%s\n%s" % [num, short]
			var col = slot.icon_color
			var sn = StyleBoxFlat.new()
			sn.bg_color = col.darkened(0.5)
			sn.set_border_width_all(1)
			sn.border_color = col
			sn.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", sn)
			btn.add_theme_color_override("font_color", col)
		else:
			# Item in slot
			btn.text = "%s\n[item]" % num
			var sn = StyleBoxFlat.new()
			sn.bg_color = C_EMPTY
			sn.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", sn)
			btn.add_theme_color_override("font_color", C_DIM)

# ── Hotbar loadout save/restore ───────────────────────────────────────────────

func _save_hotbar_loadout() -> void:
	if hotbar_ref == null or player_ref == null:
		return
	var loadout: Array = []
	for i in range(10):
		var slot = hotbar_ref.slots[i]
		if slot is AbilityBase:
			loadout.append(slot.get_meta("_ability_id") if slot.has_meta("_ability_id") else "")
		else:
			loadout.append("")
	# Send to server to persist
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.send_hotbar_loadout(loadout)

func restore_loadout(loadout: Array) -> void:
	if hotbar_ref == null:
		return
	for i in range(mini(loadout.size(), 10)):
		var ab_id = loadout[i] as String
		if ab_id == "":
			continue
		var instance = AbilityDB.create_instance(ab_id)
		if instance != null:
			hotbar_ref.set_ability(i, instance)
