extends Node2D

# ============================================================
# SCROLL VENDOR NPC — debug only
# Gives the player all ability scrolls for their clan
# and element for free. Press F to open.
# ============================================================

const C_BG     := Color(0.07, 0.05, 0.04, 0.97)
const C_BORDER := Color("ffd700")
const C_TEXT   := Color("e8e0d0")
const C_DIM    := Color("888070")
const C_GOLD   := Color("ffd700")

var _in_range: bool        = false
var _prompt:   Label       = null
var _ui:       CanvasLayer = null
var _open:     bool        = false

func _ready() -> void:
	add_to_group("npc")
	_build_visual()
	_build_proximity()

func _build_visual() -> void:
	# Dark purple placeholder square
	var vis      = ColorRect.new()
	vis.color    = Color(0.3, 0.1, 0.5, 1.0)
	vis.size     = Vector2(16, 24)
	vis.position = Vector2(-8, -12)
	vis.z_index  = 1
	add_child(vis)

	var lbl      = Label.new()
	lbl.text     = "Scroll Vendor"
	lbl.z_index  = 2
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color",        Color("ffd700"))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.position = Vector2(-24, -28)
	add_child(lbl)

	var dbg      = Label.new()
	dbg.text     = "[DEBUG]"
	dbg.z_index  = 2
	dbg.add_theme_font_size_override("font_size", 7)
	dbg.add_theme_color_override("font_color", Color("ff6666"))
	dbg.position = Vector2(-12, -38)
	add_child(dbg)

	_prompt                      = Label.new()
	_prompt.visible              = false
	_prompt.z_index              = 10
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 9)
	_prompt.add_theme_color_override("font_color",        Color("ffd700"))
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_prompt.text     = "[F] Scroll Shop"
	_prompt.position = Vector2(-32, -50)
	add_child(_prompt)

func _build_proximity() -> void:
	var area            = Area2D.new()
	area.collision_mask = 1
	var shape           = CollisionShape2D.new()
	var rect            = RectangleShape2D.new()
	rect.size           = Vector2(64, 64)
	shape.shape         = rect
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("local_player"):
		_in_range = true
		if _prompt: _prompt.visible = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("local_player"):
		_in_range = false
		if _prompt: _prompt.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F and _in_range and not _open:
			_open_shop()
		elif event.physical_keycode == KEY_ESCAPE and _open:
			_close_shop()

# ── Shop UI ───────────────────────────────────────────────────────────────────

func _open_shop() -> void:
	var player = get_tree().get_first_node_in_group("local_player")
	if player == null:
		return
	_open = true

	_ui          = CanvasLayer.new()
	_ui.layer    = 20
	add_child(_ui)

	var win_style = StyleBoxFlat.new()
	win_style.bg_color = C_BG
	win_style.set_border_width_all(2)
	win_style.border_color = C_BORDER
	win_style.set_corner_radius_all(4)

	var win          = Panel.new()
	win.add_theme_stylebox_override("panel", win_style)
	win.size         = Vector2(420, 400)
	win.position     = Vector2(270, 70)
	_ui.add_child(win)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + s, 12)
	win.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	var title_row = HBoxContainer.new()
	vbox.add_child(title_row)
	var title = Label.new()
	title.text = "SCROLL VENDOR  [DEBUG]"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", C_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(_close_shop)
	close_btn.focus_mode = Control.FOCUS_NONE
	title_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	# Clan/element info
	var clan_id    = player.get("clan") as String
	var element_id = player.get("element") as String
	var info       = Label.new()
	var clan_name  = ClanDB.get_clan(clan_id).get("display_name", clan_id) if ClanDB.clan_exists(clan_id) else "None"
	var el_name    = ClanDB.get_element(element_id).get("name", element_id) if ClanDB.element_exists(element_id) else "None"
	info.text      = "Clan: %s  |  Element: %s" % [clan_name, el_name]
	info.add_theme_font_size_override("font_size", 9)
	info.add_theme_color_override("font_color", C_DIM)
	vbox.add_child(info)

	# Scroll list
	var scroll_area = ScrollContainer.new()
	scroll_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_area)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll_area.add_child(list)

	# Gather scrolls for this player's clan + element
	var scroll_ids: Array = []
	for item_id in ItemDB.get_all_ids():
		var item = ItemDB.get_item(item_id)
		var effect = item.get("use_effect", {})
		if effect.get("type", "") != "unlock_ability":
			continue
		var ab_id = effect.get("ability_id", "")
		if ab_id == "":
			continue
		if not AbilityDB.exists(ab_id):
			continue
		var ab     = AbilityDB.get_ability(ab_id)
		var source = ab.get("source", "")
		if source == "clan:" + clan_id or source == "element:" + element_id:
			scroll_ids.append(item_id)

	if scroll_ids.is_empty():
		var empty = Label.new()
		empty.text = "No scrolls available.\nMake sure your clan and element are set."
		empty.add_theme_color_override("font_color", C_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(empty)
	else:
		for sid in scroll_ids:
			list.add_child(_make_scroll_row(sid, player))

func _make_scroll_row(scroll_id: String, player: Node) -> Control:
	var item      = ItemDB.get_item(scroll_id)
	var effect    = item.get("use_effect", {})
	var ab_id     = effect.get("ability_id", "")
	var ab        = AbilityDB.get_ability(ab_id)
	var ab_col    = ab.get("icon_color", C_TEXT) as Color
	var already   = ab_id in player.get("unlocked_abilities")

	var row_style = StyleBoxFlat.new()
	row_style.bg_color = Color(0.12, 0.09, 0.07, 1.0)
	row_style.set_corner_radius_all(3)
	row_style.set_border_width_all(1)
	row_style.border_color = ab_col.darkened(0.4)

	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", row_style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	var margin = MarginContainer.new()
	for s in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + s, 6)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(margin)

	var info_col = VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 1)
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(info_col)

	var name_lbl = Label.new()
	name_lbl.text = ab.get("name", scroll_id)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", ab_col)
	info_col.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = ab.get("description", "")
	desc_lbl.add_theme_font_size_override("font_size", 9)
	desc_lbl.add_theme_color_override("font_color", C_DIM)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_col.add_child(desc_lbl)

	# Get button
	var get_btn = Button.new()
	get_btn.focus_mode = Control.FOCUS_NONE
	get_btn.custom_minimum_size = Vector2(70, 0)
	if already:
		get_btn.text     = "Learned"
		get_btn.disabled = true
	else:
		get_btn.text = "Learn"
		get_btn.pressed.connect(func():
			_learn_ability(ab_id, player, get_btn)
		)
	hbox.add_child(get_btn)

	return panel

func _learn_ability(ab_id: String, player: Node, btn: Button) -> void:
	if ab_id in player.get("unlocked_abilities"):
		btn.text     = "Learned"
		btn.disabled = true
		return
	# Directly unlock — no scroll item needed
	var ab = AbilityDB.get_ability(ab_id)
	player.unlocked_abilities.append(ab_id)
	# Persist via server
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "debug_unlock_ability", {"ability_id": ab_id})
	btn.text     = "Learned"
	btn.disabled = true
	if player.chat:
		player.chat.add_system_message("Learned: %s" % ab.get("name", ab_id))

func _close_shop() -> void:
	_open = false
	if _ui:
		_ui.queue_free()
		_ui = null
