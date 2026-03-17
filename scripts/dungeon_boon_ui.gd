extends CanvasLayer

# ============================================================
# DUNGEON BOON UI
# Full-screen 3-card boon selection panel.
# Fires when the server sends dungeon_boon_offer.
# Player must choose one — no dismiss/cancel.
# ============================================================

const BoonDB = preload("res://scripts/dungeon_boon_db.gd")

const C_BG     = Color(0.04, 0.03, 0.07, 0.96)
const C_BORDER = Color(0.28, 0.20, 0.42)
const C_DIM    = Color(0.55, 0.55, 0.65)
const C_TEXT   = Color(0.88, 0.88, 0.92)
const C_TITLE  = Color(1.00, 0.88, 0.40)

var _panel:   Panel = null
var _offered: Array = []

func _ready() -> void:
	layer   = 55   # above HUD (50) but below fade (60+)
	visible = false
	_build_ui()
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		if not net.dungeon_boon_offer_received.is_connected(_on_boon_offer):
			net.dungeon_boon_offer_received.connect(_on_boon_offer)

func _build_ui() -> void:
	# Dark overlay
	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var s = StyleBoxFlat.new()
	s.bg_color = C_BG
	s.set_corner_radius_all(10)
	s.set_border_width_all(1)
	s.border_color = C_BORDER
	_panel.add_theme_stylebox_override("panel", s)
	add_child(_panel)

func _on_boon_offer(boon_ids: Array) -> void:
	_offered = boon_ids
	_show(boon_ids)

func _show(boon_ids: Array) -> void:
	# Clear old cards
	for child in _panel.get_children():
		child.queue_free()

	var count   = boon_ids.size()
	var card_w  = 200.0
	var card_h  = 280.0
	var gap     = 20.0
	var pw      = count * card_w + (count - 1) * gap + 60.0
	var ph      = card_h + 100.0

	_panel.offset_left   = -pw / 2.0
	_panel.offset_right  =  pw / 2.0
	_panel.offset_top    = -ph / 2.0
	_panel.offset_bottom =  ph / 2.0

	# Header
	var title = Label.new()
	title.text = "Choose a Boon"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 14
	title.offset_bottom = 36
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", C_TITLE)
	_panel.add_child(title)

	# Cards
	for i in range(count):
		var boon_id = boon_ids[i]
		var boon    = BoonDB.get_boon(boon_id)
		if boon.is_empty():
			continue
		var cx = 30.0 + i * (card_w + gap)
		_build_card(_panel, boon_id, boon, cx, 44.0, card_w, card_h)

	visible = true

func _build_card(parent: Control, boon_id: String, boon: Dictionary,
		x: float, y: float, w: float, h: float) -> void:
	var rarity  = boon.get("rarity", BoonDB.Rarity.COMMON)
	var r_color = BoonDB.rarity_color(rarity)
	var r_name  = BoonDB.rarity_name(rarity)

	var card = PanelContainer.new()
	card.position = Vector2(x, y)
	card.custom_minimum_size = Vector2(w, h)
	card.size = Vector2(w, h)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(r_color.r * 0.10, r_color.g * 0.08, r_color.b * 0.14, 0.97)
	s.set_corner_radius_all(8)
	s.set_border_width_all(2)
	s.border_color = Color(r_color.r * 0.6, r_color.g * 0.6, r_color.b * 0.8)
	s.content_margin_left = 10; s.content_margin_right  = 10
	s.content_margin_top  = 8;  s.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", s)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	card.add_child(vbox)

	# Rarity badge
	var rarity_lbl = Label.new()
	rarity_lbl.text = r_name.to_upper()
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rarity_lbl.add_theme_font_size_override("font_size", 8)
	rarity_lbl.add_theme_color_override("font_color", r_color)
	vbox.add_child(rarity_lbl)

	# Rarity divider
	var div1 = ColorRect.new()
	div1.custom_minimum_size = Vector2(0, 1)
	div1.color = Color(r_color.r * 0.4, r_color.g * 0.4, r_color.b * 0.5, 0.6)
	div1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(div1)

	var sp1 = Control.new(); sp1.custom_minimum_size = Vector2(0, 6); vbox.add_child(sp1)

	# Boon name
	var name_lbl = Label.new()
	name_lbl.text = boon.get("name", "?")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(name_lbl)

	var sp2 = Control.new(); sp2.custom_minimum_size = Vector2(0, 8); vbox.add_child(sp2)

	# Description
	var desc_lbl = Label.new()
	desc_lbl.text = boon.get("desc", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	desc_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 9)
	desc_lbl.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(desc_lbl)

	# Clan tag
	var clan = boon.get("clan", "")
	if clan != "any" and clan != "":
		var clan_lbl = Label.new()
		clan_lbl.text = clan.capitalize() + " Clan"
		clan_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		clan_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clan_lbl.add_theme_font_size_override("font_size", 7)
		clan_lbl.add_theme_color_override("font_color", C_DIM)
		vbox.add_child(clan_lbl)

	var sp3 = Control.new(); sp3.custom_minimum_size = Vector2(0, 8); vbox.add_child(sp3)

	# Select button
	var btn = Button.new()
	btn.text = "Choose"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(r_color.r * 0.18, r_color.g * 0.18, r_color.b * 0.22, 0.95)
	bs.set_corner_radius_all(6); bs.set_border_width_all(1)
	bs.border_color = r_color
	var bh = StyleBoxFlat.new()
	bh.bg_color = Color(r_color.r * 0.35, r_color.g * 0.35, r_color.b * 0.42, 0.95)
	bh.set_corner_radius_all(6); bh.set_border_width_all(1)
	bh.border_color = Color(min(r_color.r * 1.3, 1.0), min(r_color.g * 1.3, 1.0), min(r_color.b * 1.3, 1.0))
	btn.add_theme_stylebox_override("normal",  bs)
	btn.add_theme_stylebox_override("hover",   bh)
	btn.add_theme_stylebox_override("pressed", bh)
	btn.add_theme_color_override("font_color", r_color)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func(): _on_choose(boon_id))
	vbox.add_child(btn)

func _on_choose(boon_id: String) -> void:
	visible = false
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.send_player_ready.rpc_id(1, true)   # reuse ready signal for boon choice
		# Actually use the dedicated boon RPC
		net.send_boon_choice.rpc_id(1, boon_id)
