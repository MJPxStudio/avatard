extends CanvasLayer

const QuestDB = preload("res://scripts/quest_db.gd")

# ============================================================
# OBJECTIVE HUD
# Small tracker in the top-right showing current quest/mission
# objective and progress. Updates via signals.
# ============================================================

var _panel:    ColorRect = null
var _title:    Label     = null
var _obj_lbl:  Label     = null
var _prog_lbl: Label     = null

func _ready() -> void:
	layer   = 35
	visible = false
	_build()
	_connect_signals()

func _build() -> void:
	# Use a Control root so anchors work properly inside the CanvasLayer
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel          = ColorRect.new()
	_panel.color    = Color(0.04, 0.04, 0.08, 0.85)
	_panel.size     = Vector2(220, 58)
	_panel.anchor_left   = 0.5
	_panel.anchor_right  = 0.5
	_panel.anchor_top    = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left   = -110
	_panel.offset_right  = 110
	_panel.offset_top    = 10
	_panel.offset_bottom = 68
	root.add_child(_panel)

	# Gold top border
	var border       = ColorRect.new()
	border.color     = Color(0.85, 0.7, 0.2, 0.9)
	border.size      = Vector2(220, 2)
	border.position  = Vector2(0, 0)
	_panel.add_child(border)

	_title           = Label.new()
	_title.position  = Vector2(8, 4)
	_title.size      = Vector2(204, 14)
	_title.add_theme_font_size_override("font_size", 8)
	_title.add_theme_color_override("font_color", Color("ffe890"))
	_panel.add_child(_title)

	_obj_lbl          = Label.new()
	_obj_lbl.position = Vector2(8, 18)
	_obj_lbl.size     = Vector2(204, 24)
	_obj_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_lbl.add_theme_font_size_override("font_size", 8)
	_obj_lbl.add_theme_color_override("font_color", Color("dddddd"))
	_panel.add_child(_obj_lbl)

	_prog_lbl          = Label.new()
	_prog_lbl.position = Vector2(8, 42)
	_prog_lbl.size     = Vector2(204, 12)
	_prog_lbl.add_theme_font_size_override("font_size", 8)
	_prog_lbl.add_theme_color_override("font_color", Color("88ddaa"))
	_panel.add_child(_prog_lbl)

func _connect_signals() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if not net:
		return
	net.quest_progress_client.connect(_on_quest_progress)
	net.mission_progress_received.connect(_on_mission_progress)
	net.mission_accepted_received.connect(_on_mission_accepted)
	net.mission_abandoned_received.connect(func(): hide_objective())
	net.mission_completed_received.connect(func(_a, _b, _c): hide_objective())
	# Quest accepted — show new objective
	net.notify_quest_accepted_received.connect(_on_quest_accepted)
	# Quest turned in — clear objective
	net.quest_turned_in_client.connect(func(_qid, _xp, _gold): hide_objective())

func _on_quest_accepted(quest_id: String) -> void:
	var qdef = QuestDB.get_quest(quest_id)
	if qdef.is_empty():
		return
	show_objective(qdef.get("title", quest_id), qdef.get("description", ""))

func show_objective(title: String, objective: String, progress: String = "") -> void:
	visible       = true
	_title.text   = title
	_obj_lbl.text = objective
	_prog_lbl.text = progress

func hide_objective() -> void:
	visible = false

func _on_quest_progress(quest_id: String, progress: int, required: int) -> void:
	var qdef = QuestDB.get_quest(quest_id)
	if qdef.is_empty():
		return
	show_objective(
		qdef.get("title", quest_id),
		qdef.get("description", ""),
		"%d / %d" % [progress, required]
	)

func _on_mission_progress(current: int, required: int) -> void:
	_prog_lbl.text = "%d / %d" % [current, required]

func _on_mission_accepted(mission_data: Dictionary, _progress: int) -> void:
	show_objective(
		"[Mission] " + mission_data.get("title", ""),
		mission_data.get("description", ""),
		"0 / %d" % mission_data.get("required", 1)
	)
