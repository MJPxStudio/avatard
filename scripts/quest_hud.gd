extends Control

# ============================================================
# QUEST HUD — Shows active quest title + progress.
# Anchored top-right, below the minimap.
# PanelContainer auto-sizes to fit label content.
# ============================================================

const QuestDB = preload("res://scripts/quest_db.gd")

# Minimap constants — must match minimap.gd
const MM_PAD:         float = 6.0
const MM_ZONE_LBL_H:  float = 18.0
const MM_SIZE:        float = 110.0
const PANEL_W:        float = 152.0
const PAD:            float = 6.0

var _title_label: Label = null
var _prog_label:  Label = null
var _active_quest_id: String = ""

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_build()
	visible = false

func _build() -> void:
	# Anchor root Control to top-right corner
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	var top = MM_PAD + MM_ZONE_LBL_H + MM_SIZE + PAD
	offset_left   = -(PANEL_W + PAD)
	offset_top    = top
	offset_right  = -PAD
	offset_bottom = top  # height driven by PanelContainer child

	# PanelContainer auto-sizes to fit its children
	var pc = PanelContainer.new()
	pc.custom_minimum_size = Vector2(PANEL_W, 0)
	var sb = StyleBoxFlat.new()
	sb.bg_color     = Color(0.06, 0.06, 0.1, 0.88)
	sb.border_color = Color(0.8, 0.7, 0.2, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left   = 7
	sb.content_margin_right  = 7
	sb.content_margin_top    = 5
	sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)
	add_child(pc)

	# VBox stacks labels vertically — PanelContainer sizes to fit it
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	pc.add_child(vbox)

	# "QUEST" header
	var header = Label.new()
	header.text = "QUEST"
	header.add_theme_font_size_override("font_size", 7)
	header.add_theme_color_override("font_color",        Color(0.8, 0.7, 0.2, 1.0))
	header.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	header.add_theme_constant_override("shadow_offset_x", 1)
	header.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(header)

	# Quest title
	_title_label = Label.new()
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.custom_minimum_size = Vector2(PANEL_W - 14, 0)
	_title_label.add_theme_font_size_override("font_size", 9)
	_title_label.add_theme_color_override("font_color",        Color(0.95, 0.95, 0.95, 1.0))
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_title_label.add_theme_constant_override("shadow_offset_x", 1)
	_title_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(_title_label)

	# Progress line
	_prog_label = Label.new()
	_prog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prog_label.custom_minimum_size = Vector2(PANEL_W - 14, 0)
	_prog_label.add_theme_font_size_override("font_size", 8)
	_prog_label.add_theme_color_override("font_color",        Color(0.7, 0.85, 0.7, 1.0))
	_prog_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_prog_label.add_theme_constant_override("shadow_offset_x", 1)
	_prog_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(_prog_label)

func show_quest(quest_id: String, progress: int, required: int) -> void:
	_active_quest_id = quest_id
	var qdef = QuestDB.get_quest(quest_id)
	if qdef.is_empty():
		return
	_title_label.text = qdef["title"]
	if qdef["type"] == "kill":
		_prog_label.text = "%s: %d/%d" % [qdef["target"], progress, required]
	elif qdef["type"] == "talk":
		_prog_label.text = "Speak with %s" % qdef["target"]
	visible = true

func hide_quest() -> void:
	visible = false
	_active_quest_id = ""

func mark_complete() -> void:
	if _prog_label:
		_prog_label.text = "Complete! Return to turn in."
		_prog_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.3, 1.0))
