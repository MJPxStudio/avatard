extends CanvasLayer

# ============================================================
# PARTY HUD (client-side)
# Dark panel, one row per member, kick/promote buttons for leader.
# Leave / Disband button at bottom.
# Rows use VBoxContainers — no manual pixel positioning.
# ============================================================

const PAD_X      = 10
const PAD_Y      = 74   # below player HP bar
const PANEL_W    = 160
const BAR_W      = 104
const BAR_H      = 7
const BTN_W      = 18
const BTN_H      = 14

var _members:      Array  = []
var _leader:       String = ""
var _my_username:  String = ""
var _rows:         Dictionary = {}   # username -> { root, bar_fg, hp_lbl, zone_lbl }
var _panel:        Panel         = null
var _panel_vbox:   VBoxContainer = null
var _accent_bar:   Panel         = null
var _leave_btn:    Button        = null

func _ready() -> void:
	layer = 48
	_build_panel()

func _build_panel() -> void:
	_panel          = Panel.new()
	_panel.position = Vector2(PAD_X, PAD_Y)
	_panel.size     = Vector2(PANEL_W, 0)
	_panel.visible  = false
	var ps          = StyleBoxFlat.new()
	ps.bg_color     = Color(0.04, 0.04, 0.07, 0.88)
	ps.set_corner_radius_all(4)
	ps.set_content_margin_all(0)
	_panel.add_theme_stylebox_override("panel", ps)
	add_child(_panel)

	_accent_bar          = Panel.new()
	_accent_bar.position = Vector2(0, 0)
	_accent_bar.size     = Vector2(3, 0)
	var as_          = StyleBoxFlat.new()
	as_.bg_color     = Color(0.6, 0.5, 0.22, 0.95)
	as_.corner_radius_top_left    = 4
	as_.corner_radius_bottom_left = 4
	as_.set_content_margin_all(0)
	_accent_bar.add_theme_stylebox_override("panel", as_)
	_panel.add_child(_accent_bar)

	_panel_vbox          = VBoxContainer.new()
	_panel_vbox.position = Vector2(6, 6)
	_panel_vbox.size     = Vector2(PANEL_W - 12, 0)
	_panel_vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(_panel_vbox)

func set_party(members: Array, leader: String, my_username: String) -> void:
	_leader      = leader
	_my_username = my_username
	_members     = members.filter(func(n): return n.strip_edges().to_lower() != my_username.strip_edges().to_lower())
	_rebuild()

func update_hp(states: Dictionary) -> void:
	for uname in _rows:
		var row = _rows[uname]
		for pid in states:
			var s = states[pid]
			if s.get("username", "") != uname:
				continue
			var hp     = s.get("hp", 0)
			var max_hp = maxi(s.get("max_hp", 1), 1)
			var dead   = s.get("is_dead", false)
			row["bar_fg"].size.x        = BAR_W * float(hp) / float(max_hp)
			row["bar_fg"].color         = Color(0.75, 0.15, 0.15) if not dead else Color(0.3, 0.3, 0.3)
			row["hp_lbl"].text          = "Dead" if dead else "%d/%d" % [hp, max_hp]
			row["root"].modulate.a      = 0.5 if dead else 1.0
			var zone = s.get("zone", "")
			if zone != "":
				row["zone_lbl"].text = "◉  " + _zone_display(zone)
				row["zone_lbl"].add_theme_color_override("font_color", _zone_color(zone))
			break

func _zone_display(zone: String) -> String:
	match zone:
		"village":    return "Village"
		"open_world": return "Open World"
		_:            return zone.capitalize()

func _zone_color(zone: String) -> Color:
	match zone:
		"village":    return Color(0.3, 0.65, 0.9,  1.0)
		"open_world": return Color(0.3, 0.72, 0.35, 1.0)
		_:            return Color(0.55, 0.55, 0.55, 1.0)

func _rebuild() -> void:
	for uname in _rows:
		if is_instance_valid(_rows[uname]["root"]):
			_rows[uname]["root"].queue_free()
	_rows.clear()
	if is_instance_valid(_leave_btn) and _leave_btn:
		_leave_btn.queue_free()
		_leave_btn = null

	if _members.is_empty():
		_panel.visible = false
		return

	_panel.visible = true
	var am_leader  = (_leader == _my_username)

	for uname in _members:
		var is_leader = (uname == _leader)

		# Root: VBoxContainer for this member
		var root = VBoxContainer.new()
		root.add_theme_constant_override("separation", 3)
		root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_panel_vbox.add_child(root)

		# ── Row 1: name + crown + action buttons ──────────────────
		var name_row = HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 3)
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(name_row)

		if is_leader:
			var crown = Label.new()
			crown.text = "★"
			crown.add_theme_font_size_override("font_size", 8)
			crown.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
			name_row.add_child(crown)

		var name_lbl = Label.new()
		name_lbl.text = uname
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 8)
		var name_color = Color(0.75, 0.65, 0.3, 1.0) if is_leader else Color(0.88, 0.88, 0.88, 1.0)
		name_lbl.add_theme_color_override("font_color", name_color)
		name_row.add_child(name_lbl)

		if am_leader:
			var kick_btn = _make_small_btn("✕", Color(0.55, 0.1, 0.1), func():
				var net = get_tree().root.get_node_or_null("Network")
				if net and net.is_network_connected():
					net.send_party_kick.rpc_id(1, uname)
			)
			kick_btn.tooltip_text = "Kick %s" % uname
			name_row.add_child(kick_btn)

			var promo_btn = _make_small_btn("▲", Color(0.15, 0.35, 0.6), func():
				var net = get_tree().root.get_node_or_null("Network")
				if net and net.is_network_connected():
					net.send_party_promote.rpc_id(1, uname)
			)
			promo_btn.tooltip_text = "Promote %s" % uname
			name_row.add_child(promo_btn)

		# ── Row 2: zone indicator ──────────────────────────────────
		var zone_lbl = Label.new()
		zone_lbl.text = "◉  —"
		zone_lbl.add_theme_font_size_override("font_size", 7)
		zone_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
		root.add_child(zone_lbl)

		# ── Row 3: HP bar ──────────────────────────────────────────
		# Use a Control container so bar_fg can overlay bar_bg
		var bar_container = Control.new()
		bar_container.custom_minimum_size = Vector2(BAR_W, BAR_H)
		bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(bar_container)

		var bar_bg = ColorRect.new()
		bar_bg.color  = Color(0.1, 0.1, 0.1, 0.8)
		bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar_container.add_child(bar_bg)

		var bar_fg = ColorRect.new()
		bar_fg.color  = Color(0.75, 0.15, 0.15)
		bar_fg.size   = Vector2(BAR_W, BAR_H)
		bar_fg.anchor_top    = 0.0
		bar_fg.anchor_bottom = 1.0
		bar_fg.anchor_left   = 0.0
		bar_fg.anchor_right  = 0.0
		bar_fg.offset_left   = 0
		bar_fg.offset_right  = BAR_W
		bar_container.add_child(bar_fg)

		var hp_lbl = Label.new()
		hp_lbl.text = "---"
		hp_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		hp_lbl.add_theme_font_size_override("font_size", 7)
		hp_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		bar_container.add_child(hp_lbl)

		_rows[uname] = { "root": root, "bar_fg": bar_fg, "hp_lbl": hp_lbl,
						 "name_lbl": name_lbl, "zone_lbl": zone_lbl }

	# Separator
	var sep = ColorRect.new()
	sep.color = Color(0.3, 0.25, 0.12, 0.8)
	sep.custom_minimum_size = Vector2(PANEL_W - 12, 1)
	_panel_vbox.add_child(sep)

	# Leave / Disband button
	var btn_label = "Disband Party" if (_leader == _my_username) else "Leave Party"
	var btn_color = Color(0.5, 0.1, 0.1) if (_leader == _my_username) else Color(0.25, 0.25, 0.25)
	_leave_btn = _make_leave_btn(btn_label, btn_color)
	_panel_vbox.add_child(_leave_btn)

func _process(_delta: float) -> void:
	# Sync panel height to vbox minimum size every frame
	if _panel and _panel.visible and _panel_vbox:
		var min_h = _panel_vbox.get_combined_minimum_size().y + 12
		if _panel.size.y != min_h:
			_panel.size         = Vector2(PANEL_W, min_h)
			_accent_bar.size    = Vector2(3, min_h)
			_panel_vbox.size    = Vector2(PANEL_W - 12, min_h - 12)

func _make_small_btn(label: String, bg: Color, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
	btn.focus_mode          = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 7)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	var s      = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(2)
	s.set_content_margin_all(1)
	btn.add_theme_stylebox_override("normal", s)
	var sh     = StyleBoxFlat.new()
	sh.bg_color = bg.lightened(0.2)
	sh.set_corner_radius_all(2)
	sh.set_content_margin_all(1)
	btn.add_theme_stylebox_override("hover", sh)
	btn.pressed.connect(callback)
	return btn

func _make_leave_btn(label: String, bg: Color) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(PANEL_W - 12, 20)
	btn.focus_mode          = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 8)
	btn.add_theme_color_override("font_color", Color(1, 0.85, 0.85, 1))
	var s      = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(3)
	s.set_content_margin_all(3)
	btn.add_theme_stylebox_override("normal", s)
	var sh     = StyleBoxFlat.new()
	sh.bg_color = bg.lightened(0.15)
	sh.set_corner_radius_all(3)
	sh.set_content_margin_all(3)
	btn.add_theme_stylebox_override("hover", sh)
	btn.pressed.connect(func():
		var net = get_tree().root.get_node_or_null("Network")
		if net and net.is_network_connected():
			net.send_party_leave.rpc_id(1)
	)
	return btn
