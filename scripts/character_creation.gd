extends CanvasLayer

# ============================================================
# CHARACTER CREATION
# Shown on first login only (when player_data.clan == "").
# Two steps:
#   1. Pick clan   — shows passive + full ability pool
#   2. Pick element — shows element description + ability list
# Emits creation_complete(clan_id, element_id) when confirmed.
# ============================================================

signal creation_complete(clan_id: String, element_id: String)

const SCREEN_SIZE := Vector2(960, 540)

# State
var _step:        int    = 0   # 0 = clan, 1 = element
var _clan_id:     String = ""
var _element_id:  String = ""

# Root control
var _root: Control

# Reused panel areas
var _title_label:   Label
var _cards_row:     HBoxContainer
var _detail_box:    VBoxContainer
var _confirm_btn:   Button
var _status_label:  Label

# Colors
const C_BG      := Color(0.07, 0.05, 0.04, 0.97)
const C_PANEL   := Color(0.12, 0.09, 0.07, 1.0)
const C_BORDER  := Color("ffd700")
const C_TEXT    := Color("e8e0d0")
const C_DIM     := Color("888070")
const C_GOLD    := Color("ffd700")
const C_GREEN   := Color("55dd55")

func start(_player_data: Dictionary) -> void:
	_build_ui()
	_show_clan_step()

# ── UI Shell ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Dark overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.88)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(overlay)

	# Outer window
	var win_style = StyleBoxFlat.new()
	win_style.bg_color = C_BG
	win_style.set_border_width_all(2)
	win_style.border_color = C_BORDER
	win_style.set_corner_radius_all(4)

	var win = Panel.new()
	win.add_theme_stylebox_override("panel", win_style)
	win.size     = Vector2(860, 480)
	win.position = (SCREEN_SIZE - win.size) * 0.5
	_root.add_child(win)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_child(vbox)
	win.add_child(margin)

	# Title
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", C_GOLD)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Main row: cards left, detail right
	var main_row = HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 12)
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(main_row)

	# Cards column
	var cards_col = VBoxContainer.new()
	cards_col.add_theme_constant_override("separation", 6)
	cards_col.custom_minimum_size = Vector2(240, 0)
	main_row.add_child(cards_col)

	var cards_title = Label.new()
	cards_title.text = "SELECT"
	cards_title.add_theme_font_size_override("font_size", 9)
	cards_title.add_theme_color_override("font_color", C_DIM)
	cards_col.add_child(cards_title)

	_cards_row = HBoxContainer.new()
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_cards_row.add_theme_constant_override("separation", 6)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner_col = VBoxContainer.new()
	inner_col.add_theme_constant_override("separation", 6)
	inner_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_col.name = "InnerCol"
	scroll.add_child(inner_col)
	cards_col.add_child(scroll)

	# Detail column
	var detail_scroll = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_row.add_child(detail_scroll)

	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(_detail_box)

	# Bottom bar
	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	vbox.add_child(bottom)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", C_DIM)
	bottom.add_child(_status_label)

	_confirm_btn = Button.new()
	_confirm_btn.text     = "CONFIRM"
	_confirm_btn.disabled = true
	_confirm_btn.custom_minimum_size = Vector2(120, 0)
	_confirm_btn.add_theme_font_size_override("font_size", 12)
	_confirm_btn.pressed.connect(_on_confirm)
	bottom.add_child(_confirm_btn)

# ── Step 1: Clan ──────────────────────────────────────────────────────────────

func _show_clan_step() -> void:
	_step = 0
	_clan_id = ""
	_title_label.text = "Choose Your Clan"
	_status_label.text = "Select a clan to see details."
	_confirm_btn.disabled = true
	_confirm_btn.text = "NEXT →"
	_clear_detail()
	_rebuild_cards()

func _rebuild_cards() -> void:
	var col = _root.get_node_or_null("*/InnerCol")
	# Walk tree to find InnerCol
	col = _find_inner_col(_root)
	if col == null:
		return
	for c in col.get_children():
		c.queue_free()

	if _step == 0:
		for clan_id in ClanDB.get_all_clan_ids():
			var clan = ClanDB.get_clan(clan_id)
			col.add_child(_make_card(
				clan_id, clan["name"], clan["passive_name"],
				clan.get("color", C_TEXT),
				func(): _select_clan(clan_id)
			))
	else:
		var affinity = ClanDB.get_element_affinity(_clan_id)
		for el_id in ClanDB.get_all_element_ids():
			if affinity != "" and el_id != affinity:
				continue
			var el = ClanDB.get_element(el_id)
			col.add_child(_make_card(
				el_id, el["short"], el["name"],
				el.get("color", C_TEXT),
				func(): _select_element(el_id)
			))

func _find_inner_col(node: Node) -> Node:
	if node.name == "InnerCol":
		return node
	for c in node.get_children():
		var found = _find_inner_col(c)
		if found:
			return found
	return null

func _make_card(id: String, title: String, subtitle: String, col: Color, on_press: Callable) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 44)

	var normal = StyleBoxFlat.new()
	normal.bg_color = C_PANEL
	normal.set_border_width_all(1)
	normal.border_color = col.darkened(0.4)
	normal.set_corner_radius_all(3)
	var hover = StyleBoxFlat.new()
	hover.bg_color = col.darkened(0.6)
	hover.set_border_width_all(1)
	hover.border_color = col
	hover.set_corner_radius_all(3)
	var selected = StyleBoxFlat.new()
	selected.bg_color = col.darkened(0.3)
	selected.set_border_width_all(2)
	selected.border_color = col
	selected.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover",  hover)
	btn.add_theme_stylebox_override("pressed", selected)
	btn.add_theme_stylebox_override("focus", normal)

	# Card content
	var vb = VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 1)
	var ml = MarginContainer.new()
	ml.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left","right","top","bottom"]:
		ml.add_theme_constant_override("margin_" + s, 6)
	ml.add_child(vb)
	ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(ml)

	var name_lbl = Label.new()
	name_lbl.text = title
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", col)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = subtitle
	sub_lbl.add_theme_font_size_override("font_size", 9)
	sub_lbl.add_theme_color_override("font_color", C_DIM)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sub_lbl)

	btn.pressed.connect(on_press)
	btn.set_meta("card_id", id)
	return btn

func _select_clan(clan_id: String) -> void:
	_clan_id = clan_id
	_confirm_btn.disabled = false
	_status_label.text = "Clan selected. Click NEXT to choose your element."
	_show_clan_detail(clan_id)
	_highlight_card(clan_id)

func _show_clan_detail(clan_id: String) -> void:
	_clear_detail()
	var clan = ClanDB.get_clan(clan_id)
	var col  = clan.get("color", C_TEXT) as Color

	_detail_add_label(clan["display_name"], 18, col)
	_detail_add_label(clan["lore"], 10, C_DIM, true)
	_detail_add_spacer()

	# Passive
	_detail_add_label("PASSIVE — " + clan["passive_name"], 11, C_GOLD)
	_detail_add_label(clan["passive_desc"], 10, C_TEXT, true)
	_detail_add_spacer()

	# Ability pool
	_detail_add_label("ABILITY POOL", 11, C_GOLD)
	var pool = ClanDB.get_clan_pool(clan_id)
	for ab_id in pool:
		var ab = AbilityDB.get_ability(ab_id)
		if ab.is_empty():
			continue
		var min_rank = ab.get("min_rank", "")
		var rank_txt = (" [%s]" % min_rank) if min_rank != "" and min_rank != "Academy Student" else ""
		var ab_col = ab.get("icon_color", C_TEXT) as Color
		_detail_add_label("• %s%s" % [ab["name"], rank_txt], 10, ab_col)
		_detail_add_label("  %s" % ab["description"], 9, C_DIM, true)

	# Element affinity note
	var affinity = ClanDB.get_element_affinity(clan_id)
	if affinity != "":
		_detail_add_spacer()
		var el = ClanDB.get_element(affinity)
		_detail_add_label("Element locked: %s" % el.get("name", affinity), 10, el.get("color", C_TEXT))

# ── Step 2: Element ───────────────────────────────────────────────────────────

func _show_element_step() -> void:
	_step = 1
	_element_id = ""
	var clan = ClanDB.get_clan(_clan_id)
	_title_label.text = "Choose Your Element — %s" % clan["name"]
	_confirm_btn.disabled = true
	_confirm_btn.text = "BEGIN"
	_status_label.text = "Select your primary element."
	_clear_detail()
	_rebuild_cards()

	# If element is locked by clan, auto-select it
	var affinity = ClanDB.get_element_affinity(_clan_id)
	if affinity != "":
		_select_element(affinity)

func _select_element(element_id: String) -> void:
	_element_id = element_id
	_confirm_btn.disabled = false
	_status_label.text = "Element selected. Click BEGIN to enter the world."
	_show_element_detail(element_id)
	_highlight_card(element_id)

func _show_element_detail(element_id: String) -> void:
	_clear_detail()
	var el  = ClanDB.get_element(element_id)
	var col = el.get("color", C_TEXT) as Color

	_detail_add_label(el["name"], 18, col)
	_detail_add_label(el["description"], 10, C_DIM, true)
	_detail_add_spacer()

	_detail_add_label("ABILITIES (unlock via dungeon scrolls)", 11, C_GOLD)
	var pool = ClanDB.get_element_pool(element_id)
	for ab_id in pool:
		var ab = AbilityDB.get_ability(ab_id)
		if ab.is_empty():
			continue
		var min_rank = ab.get("min_rank", "")
		var rank_txt = (" [%s]" % min_rank) if min_rank != "" and min_rank != "Academy Student" else ""
		_detail_add_label("• %s%s" % [ab["name"], rank_txt], 10, col)
		_detail_add_label("  %s" % ab["description"], 9, C_DIM, true)

	_detail_add_spacer()
	_detail_add_label("Second element unlocks at Chunin rank.", 9, C_DIM, true)

# ── Confirm ───────────────────────────────────────────────────────────────────

func _on_confirm() -> void:
	if _step == 0:
		if _clan_id == "":
			return
		_show_element_step()
	else:
		if _element_id == "":
			return
		creation_complete.emit(_clan_id, _element_id)
		queue_free()

# ── Detail helpers ────────────────────────────────────────────────────────────

func _clear_detail() -> void:
	for c in _detail_box.get_children():
		c.queue_free()

func _detail_add_label(text: String, size: int, color: Color, wrap: bool = false) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap:
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(lbl)

func _detail_add_spacer() -> void:
	var sp = Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	_detail_box.add_child(sp)

func _highlight_card(selected_id: String) -> void:
	var col = _find_inner_col(_root)
	if col == null:
		return
	for btn in col.get_children():
		if not btn is Button:
			continue
		var id = btn.get_meta("card_id") if btn.has_meta("card_id") else ""
		var is_sel = (id == selected_id)
		var base_col: Color
		if _step == 0:
			base_col = ClanDB.get_clan(id).get("color", C_TEXT) if ClanDB.clan_exists(id) else C_TEXT
		else:
			base_col = ClanDB.get_element(id).get("color", C_TEXT) if ClanDB.element_exists(id) else C_TEXT

		var normal = StyleBoxFlat.new()
		normal.set_corner_radius_all(3)
		normal.set_border_width_all(2 if is_sel else 1)
		if is_sel:
			normal.bg_color     = base_col.darkened(0.3)
			normal.border_color = base_col
		else:
			normal.bg_color     = C_PANEL
			normal.border_color = base_col.darkened(0.4)
		btn.add_theme_stylebox_override("normal", normal)
