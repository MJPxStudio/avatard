extends CanvasLayer

# ============================================================
# DUNGEON READY UI (client-side)
# Shown when a ready check is active. Displays party members,
# ready status, and a Ready/Cancel button.
# ============================================================

var _panel:        Panel  = null
var _title_lbl:    Label  = null
var _member_rows:  Array  = []
var _ready_btn:    Button = null
var _cancel_btn:   Button = null
var _countdown_lbl: Label = null

var _is_ready:    bool   = false
var _dungeon_id:  String = ""

const PANEL_W = 240
const PANEL_H = 200

func _ready() -> void:
	layer   = 40
	visible = false
	_build_ui()
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.ready_check_updated.connect(_on_ready_update)
		net.ready_check_cancelled_received.connect(_on_cancelled)
		net.dungeon_launching_received.connect(_on_launching)

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.anchor_left   = 0.5
	_panel.anchor_right  = 0.5
	_panel.anchor_top    = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left   = -PANEL_W / 2
	_panel.offset_right  =  PANEL_W / 2
	_panel.offset_top    = -PANEL_H / 2
	_panel.offset_bottom =  PANEL_H / 2
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.10, 0.95)
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = Color(0.3, 0.3, 0.5)
	_panel.add_theme_stylebox_override("panel", s)
	add_child(_panel)

	_title_lbl = Label.new()
	_title_lbl.text = "Dungeon Ready Check"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.anchor_left  = 0.0; _title_lbl.anchor_right = 1.0
	_title_lbl.offset_top   = 10; _title_lbl.offset_bottom = 26
	_title_lbl.add_theme_font_size_override("font_size", 11)
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_panel.add_child(_title_lbl)

	# Member rows — up to 4
	for i in range(4):
		var row = Label.new()
		row.anchor_left  = 0.0; row.anchor_right = 1.0
		row.offset_left  = 14
		row.offset_top   = 32 + i * 22
		row.offset_bottom = 32 + i * 22 + 18
		row.add_theme_font_size_override("font_size", 9)
		row.visible = false
		_panel.add_child(row)
		_member_rows.append(row)

	_countdown_lbl = Label.new()
	_countdown_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_lbl.anchor_left  = 0.0; _countdown_lbl.anchor_right = 1.0
	_countdown_lbl.offset_top   = 128; _countdown_lbl.offset_bottom = 148
	_countdown_lbl.add_theme_font_size_override("font_size", 14)
	_countdown_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	_countdown_lbl.visible = false
	_panel.add_child(_countdown_lbl)

	_ready_btn = Button.new()
	_ready_btn.text          = "Ready"
	_ready_btn.anchor_left   = 0.0; _ready_btn.anchor_right  = 0.5
	_ready_btn.offset_left   = 14;  _ready_btn.offset_right  = -7
	_ready_btn.offset_top    = 155; _ready_btn.offset_bottom = 178
	_ready_btn.pressed.connect(_on_ready_pressed)
	_panel.add_child(_ready_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text         = "Cancel"
	_cancel_btn.anchor_left  = 0.5;  _cancel_btn.anchor_right  = 1.0
	_cancel_btn.offset_left  = 7;    _cancel_btn.offset_right  = -14
	_cancel_btn.offset_top   = 155;  _cancel_btn.offset_bottom = 178
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_panel.add_child(_cancel_btn)

func _on_ready_update(members: Array, dungeon_id: String) -> void:
	if not visible:
		show_ready_check(members, dungeon_id)
	else:
		_update_members(members)

func show_ready_check(members: Array, dungeon_id: String) -> void:
	_dungeon_id = dungeon_id
	visible     = true
	# Update title with dungeon name if we can resolve it
	var DungeonData = load("res://scripts/dungeon_data.gd")
	if DungeonData:
		var def = DungeonData.get_dungeon(dungeon_id)
		if not def.is_empty():
			_title_lbl.text = def.get("display_name", "Dungeon") + " — Ready?"
	_update_members(members)
	_countdown_lbl.visible = false
	_ready_btn.disabled    = false
	_cancel_btn.disabled   = false

func _update_members(members: Array) -> void:
	for i in range(_member_rows.size()):
		if i < members.size():
			var m    = members[i]
			var row  = _member_rows[i]
			var icon = "✓" if m.get("ready", false) else "○"
			var col  = Color(0.3, 1.0, 0.4) if m.get("ready", false) else Color(0.75, 0.75, 0.75)
			row.text = "%s  %s" % [icon, m.get("username", "?")]
			row.add_theme_color_override("font_color", col)
			row.visible = true
		else:
			_member_rows[i].visible = false

func _on_launching(countdown: float) -> void:
	_ready_btn.disabled  = true
	_cancel_btn.disabled = true
	_countdown_lbl.visible = true
	_countdown_lbl.text  = "Launching..."
	# Tick down visually
	var elapsed = 0.0
	var total   = countdown
	get_tree().create_timer(0.0).timeout.connect(func(): _tick_countdown(total, elapsed))

func _tick_countdown(total: float, elapsed: float) -> void:
	var remaining = total - elapsed
	if remaining <= 0.0:
		return
	_countdown_lbl.text = "Launching in %d..." % ceili(remaining)
	get_tree().create_timer(0.5).timeout.connect(
		func(): _tick_countdown(total, elapsed + 0.5), CONNECT_ONE_SHOT)

func _on_cancelled(reason: String) -> void:
	visible = false
	_is_ready = false
	var lp = get_tree().get_first_node_in_group("local_player")
	if lp and lp.chat:
		lp.chat.add_system_message("Ready check cancelled: %s" % reason)

func _on_ready_pressed() -> void:
	_is_ready = not _is_ready
	_ready_btn.text = "Unready" if _is_ready else "Ready"
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.send_player_ready.rpc_id(1, _is_ready)

func _on_cancel_pressed() -> void:
	visible   = false
	_is_ready = false
	_ready_btn.text = "Ready"
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.send_cancel_ready.rpc_id(1)

func close() -> void:
	visible   = false
	_is_ready = false
