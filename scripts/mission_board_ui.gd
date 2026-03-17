extends CanvasLayer

# ============================================================
# MISSION BOARD UI — Redesigned
# Wider board, taller cards, proper text wrapping.
# Scroll border with parchment + wood aesthetic.
# ============================================================

const MissionDB = preload("res://scripts/mission_db.gd")

const BOARD_W  = 780
const BOARD_H  = 560
const CARD_W   = 220
const CARD_H   = 120
const CARD_PAD = 12

var _root:         Control   = null
var _board_bg:     Control   = null
var _rank_tabs:    Array     = []
var _card_area:    Control   = null
var _active_panel: Control   = null
var _active_lbl:   Label     = null
var _progress_lbl: Label     = null
var _abandon_btn:  Button    = null
var _complete_btn: Button    = null

var _current_rank:    String     = "D"
var _available:       Array      = []
var _active_id:       String     = ""
var _active_data:     Dictionary = {}
var _active_progress: int        = 0
var _active_required: int        = 0

const RANK_COLORS = {
	"D": Color("bbbbbb"),
	"C": Color("55dd55"),
	"B": Color("5599ff"),
	"A": Color("dd44dd"),
	"S": Color("ffaa00"),
}

func _ready() -> void:
	layer   = 60
	visible = false
	_build()
	_connect_signals()

func _connect_signals() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if not net:
		return
	net.mission_board_received.connect(_on_board_data)
	net.mission_accepted_received.connect(_on_mission_accepted)
	net.mission_abandoned_received.connect(_on_mission_abandoned)
	net.mission_completed_received.connect(_on_mission_completed)
	net.mission_progress_received.connect(_on_progress_update)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# ── Dimmed backdrop ──────────────────────────────────────
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.60)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed: close())
	_root.add_child(dim)

	# ── Board panel with rounded corners + gold border ───────
	var outer          = PanelContainer.new()
	outer.anchor_left  = 0.5; outer.anchor_right  = 0.5
	outer.anchor_top   = 0.5; outer.anchor_bottom = 0.5
	outer.offset_left  = -BOARD_W / 2
	outer.offset_right =  BOARD_W / 2
	outer.offset_top   = -BOARD_H / 2
	outer.offset_bottom=  BOARD_H / 2
	var board_style    = StyleBoxFlat.new()
	board_style.bg_color           = Color(0.40, 0.28, 0.15, 1.0)
	board_style.border_color       = Color(0.65, 0.48, 0.15, 1.0)
	board_style.border_width_top    = 3
	board_style.border_width_bottom = 3
	board_style.border_width_left   = 3
	board_style.border_width_right  = 3
	board_style.corner_radius_top_left     = 10
	board_style.corner_radius_top_right    = 10
	board_style.corner_radius_bottom_left  = 10
	board_style.corner_radius_bottom_right = 10
	board_style.shadow_color  = Color(0, 0, 0, 0.6)
	board_style.shadow_size   = 12
	board_style.shadow_offset = Vector2(4, 4)
	board_style.content_margin_left   = 0
	board_style.content_margin_right  = 0
	board_style.content_margin_top    = 0
	board_style.content_margin_bottom = 0
	outer.add_theme_stylebox_override("panel", board_style)
	_root.add_child(outer)

	# ── Main cork board (inside the panel) ───────────────────
	_board_bg = Control.new()
	_board_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_child(_board_bg)

	# ── Title bar ────────────────────────────────────────────
	var title_bar      = ColorRect.new()
	title_bar.color    = Color(0.15, 0.09, 0.04, 1.0)
	title_bar.size     = Vector2(BOARD_W, 40)
	_board_bg.add_child(title_bar)

	var title          = Label.new()
	title.text         = "✦  MISSION BOARD  ✦"
	title.position     = Vector2(0, 8)
	title.size         = Vector2(BOARD_W, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("ffd080"))
	title.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title_bar.add_child(title)

	# ── Close button ─────────────────────────────────────────
	var close_btn  = Button.new()
	close_btn.text = "✕"
	close_btn.position = Vector2(BOARD_W - 34, 6)
	close_btn.size     = Vector2(28, 28)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(close)
	title_bar.add_child(close_btn)

	# ── Rank tabs ────────────────────────────────────────────
	var tab_bar      = ColorRect.new()
	tab_bar.color    = Color(0.12, 0.07, 0.03, 1.0)
	tab_bar.size     = Vector2(BOARD_W, 36)
	tab_bar.position = Vector2(0, 40)
	_board_bg.add_child(tab_bar)

	var tab_x = 10
	for rank in ["D", "C", "B", "A", "S"]:
		var btn              = Button.new()
		btn.text             = "  Rank %s  " % rank
		btn.position         = Vector2(tab_x, 4)
		btn.size             = Vector2(118, 28)
		btn.add_theme_font_size_override("font_size", 10)
		var col = RANK_COLORS.get(rank, Color("aaaaaa"))
		btn.add_theme_color_override("font_color", col)
		btn.pressed.connect(_on_rank_tab.bind(rank))
		tab_bar.add_child(btn)
		_rank_tabs.append(btn)
		tab_x += 124

	# ── Separator line ────────────────────────────────────────
	var sep       = ColorRect.new()
	sep.color     = Color(0.65, 0.48, 0.15, 0.5)
	sep.size      = Vector2(BOARD_W, 2)
	sep.position  = Vector2(0, 76)
	_board_bg.add_child(sep)

	# ── Card area ────────────────────────────────────────────
	_card_area          = Control.new()
	_card_area.position = Vector2(CARD_PAD, 84)
	_card_area.size     = Vector2(BOARD_W - CARD_PAD * 2, BOARD_H - 200)
	_card_area.clip_contents = true
	_board_bg.add_child(_card_area)

	# ── Active mission panel ──────────────────────────────────
	_active_panel          = ColorRect.new()
	(_active_panel as ColorRect).color = Color(0.08, 0.05, 0.02, 0.95)
	_active_panel.size     = Vector2(BOARD_W - 20, 80)
	_active_panel.position = Vector2(10, BOARD_H - 94)
	_active_panel.visible  = false
	_board_bg.add_child(_active_panel)

	# Gold top border on active panel
	var ap_border       = ColorRect.new()
	ap_border.color     = Color(0.65, 0.48, 0.15, 1.0)
	ap_border.size      = Vector2(BOARD_W - 20, 2)
	_active_panel.add_child(ap_border)

	var ap_title        = Label.new()
	ap_title.text       = "ACTIVE MISSION"
	ap_title.position   = Vector2(10, 5)
	ap_title.add_theme_font_size_override("font_size", 8)
	ap_title.add_theme_color_override("font_color", Color("ffd080"))
	_active_panel.add_child(ap_title)

	_active_lbl          = Label.new()
	_active_lbl.position = Vector2(10, 18)
	_active_lbl.size     = Vector2(BOARD_W - 200, 16)
	_active_lbl.add_theme_font_size_override("font_size", 10)
	_active_lbl.add_theme_color_override("font_color", Color("ffffff"))
	_active_panel.add_child(_active_lbl)

	_progress_lbl          = Label.new()
	_progress_lbl.position = Vector2(10, 36)
	_progress_lbl.size     = Vector2(BOARD_W - 200, 14)
	_progress_lbl.add_theme_font_size_override("font_size", 9)
	_progress_lbl.add_theme_color_override("font_color", Color("88ddaa"))
	_active_panel.add_child(_progress_lbl)

	_complete_btn          = Button.new()
	_complete_btn.text     = "Turn In"
	_complete_btn.position = Vector2(BOARD_W - 190, 10)
	_complete_btn.size     = Vector2(80, 28)
	_complete_btn.add_theme_font_size_override("font_size", 9)
	_complete_btn.pressed.connect(_on_complete_pressed)
	_active_panel.add_child(_complete_btn)

	_abandon_btn          = Button.new()
	_abandon_btn.text     = "Abandon"
	_abandon_btn.position = Vector2(BOARD_W - 100, 10)
	_abandon_btn.size     = Vector2(80, 28)
	_abandon_btn.add_theme_font_size_override("font_size", 9)
	_abandon_btn.pressed.connect(_on_abandon_pressed)
	_active_panel.add_child(_abandon_btn)

func open() -> void:
	visible = true
	_request_board(_current_rank)

func close() -> void:
	visible = false

func _on_rank_tab(rank: String) -> void:
	_current_rank = rank
	_request_board(rank)

func _request_board(rank: String) -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.request_mission_board.rpc_id(1, rank)

func _on_board_data(rank: String, available: Array, active_id: String, progress: int) -> void:
	if rank != _current_rank:
		return
	_available       = available
	_active_id       = active_id
	_active_progress = progress
	_rebuild_cards()
	_update_active_panel()

func _rebuild_cards() -> void:
	for child in _card_area.get_children():
		child.queue_free()

	const COLS    = 3
	const MARGIN  = 12
	const GAP     = 10
	var avail_w   = _card_area.size.x - (MARGIN * 2)
	var dyn_w     = (avail_w - GAP * (COLS - 1)) / COLS
	var col = 0
	var row = 0

	for mid in _available:
		var mdef = MissionDB.get_mission(mid)
		if mdef.is_empty():
			continue
		var card = _make_card(mdef, dyn_w)
		card.position = Vector2(MARGIN + col * (dyn_w + GAP), row * (CARD_H + GAP))
		_card_area.add_child(card)
		col += 1
		if col >= COLS:
			col = 0
			row += 1

func _make_card(mdef: Dictionary, card_w: float = CARD_W) -> Control:
	# Use PanelContainer so children get proper width constraints for autowrap
	var card           = PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, CARD_H)
	card.size          = Vector2(card_w, CARD_H)

	# Parchment background via StyleBox
	var style          = StyleBoxFlat.new()
	style.bg_color     = Color(0.88, 0.82, 0.66, 1.0)
	style.border_color = RANK_COLORS.get(mdef.get("rank", "D"), Color("aaa"))
	style.border_width_top    = 4
	style.border_width_left   = 0
	style.border_width_right  = 0
	style.border_width_bottom = 0
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left   = 8
	style.content_margin_right  = 8
	style.content_margin_top    = 4
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)

	var vbox           = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(vbox)

	# Title
	var title          = Label.new()
	title.text         = mdef.get("title", "?")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color("1a0e00"))
	vbox.add_child(title)

	# Divider
	var div            = ColorRect.new()
	div.color          = Color(0.5, 0.38, 0.2, 0.35)
	div.custom_minimum_size = Vector2(0, 1)
	div.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(div)

	# Spacer
	var sp1 = Control.new()
	sp1.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(sp1)

	# Description — inside VBoxContainer so width IS constrained
	var desc           = Label.new()
	desc.text          = mdef.get("description", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", 8)
	desc.add_theme_color_override("font_color", Color("2a1a08"))
	vbox.add_child(desc)

	# Bottom reward + button row
	var hbox           = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)

	var reward         = Label.new()
	reward.text        = "+%d XP    +%d ¥" % [mdef.get("reward_xp", 0), mdef.get("reward_gold", 0)]
	reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward.add_theme_font_size_override("font_size", 8)
	reward.add_theme_color_override("font_color", Color("2a5e18"))
	hbox.add_child(reward)

	var btn            = Button.new()
	btn.text           = "Accept"
	btn.custom_minimum_size = Vector2(64, 0)
	btn.add_theme_font_size_override("font_size", 8)
	btn.disabled       = _active_id != ""
	var mid = mdef.get("id", "")
	btn.pressed.connect(_on_accept_pressed.bind(mid))
	hbox.add_child(btn)

	return card


func _update_active_panel() -> void:
	if _active_id == "":
		_active_panel.visible = false
		return
	_active_panel.visible = true
	var mdef          = MissionDB.get_mission(_active_id)
	_active_data      = mdef
	_active_required  = mdef.get("required", 1)
	_active_lbl.text  = "[%s]  %s" % [mdef.get("rank", "D"), mdef.get("title", _active_id)]

	match mdef.get("type", ""):
		"kill":
			_progress_lbl.text       = "Kills: %d / %d" % [_active_progress, _active_required]
			_complete_btn.disabled   = _active_progress < _active_required
		"collect":
			var lp       = get_tree().get_first_node_in_group("local_player")
			var inv_count = 0
			if lp and lp.inventory and lp.inventory.has_method("get_count"):
				inv_count = lp.inventory.get_count(mdef.get("item_id", ""))
			_progress_lbl.text       = "In inventory: %d / %d" % [inv_count, _active_required]
			_complete_btn.disabled   = inv_count < _active_required
		"deliver":
			if _active_progress >= 1:
				_progress_lbl.text   = "Letter delivered — return to turn in."
				_complete_btn.disabled = false
			else:
				_progress_lbl.text   = "Deliver to: %s" % _active_data.get("assigned_target", "?")
				_complete_btn.disabled = true

func _on_accept_pressed(mission_id: String) -> void:
	if _active_id != "":
		return
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.accept_mission.rpc_id(1, mission_id)

func _on_complete_pressed() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.complete_mission.rpc_id(1)

func _on_abandon_pressed() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.abandon_mission.rpc_id(1)

func _on_mission_accepted(mission_data: Dictionary, progress: int) -> void:
	_active_id       = mission_data.get("id", "")
	_active_data     = mission_data
	_active_progress = progress
	_active_required = mission_data.get("required", 1)
	_rebuild_cards()
	_update_active_panel()

func _on_mission_abandoned() -> void:
	_active_id       = ""
	_active_progress = 0
	_active_data     = {}
	_rebuild_cards()
	_update_active_panel()
	_request_board(_current_rank)

func _on_mission_completed(mission_id: String, xp: int, gold: int) -> void:
	_active_id       = ""
	_active_progress = 0
	_active_data     = {}
	var lp = get_tree().get_first_node_in_group("local_player")
	if lp and lp.chat:
		lp.chat.add_system_message("[Mission] Complete! +%d XP  +%d ¥" % [xp, gold])
	_rebuild_cards()
	_update_active_panel()
	_request_board(_current_rank)

func _on_progress_update(current: int, required: int) -> void:
	_active_progress = current
	_active_required = required
	_update_active_panel()

func _process(_delta: float) -> void:
	if visible and _active_id != "" and _active_data.get("type") == "collect":
		_update_active_panel()
