extends CanvasLayer

# ============================================================
# TARGET HUD — Fixed screen-space panel for locked target
# Shows: name, level, HP bar + numbers
# Visible only when a target is locked via E key
# ============================================================

const BAR_W:   float = 120.0
const BAR_H:   float = 8.0
const PANEL_W: float = 140.0
const PANEL_H: float = 46.0

var _root:       Control = null
var _name_label: Label   = null
var _lvl_label:  Label   = null
var _bar_bg:     ColorRect = null
var _bar_fg:     ColorRect = null
var _hp_label:   Label   = null
var _border:     ColorRect = null

var _tracked_enemy: Node = null
var _max_hp:        int  = 1

func _ready() -> void:
	_build()
	hide_hud()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Panel background
	var panel      = ColorRect.new()
	panel.color    = Color(0.05, 0.05, 0.05, 0.78)
	panel.size     = Vector2(PANEL_W, PANEL_H)
	panel.position = Vector2(-PANEL_W / 2.0, 10)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_root.add_child(panel)

	# Thin coloured top border (recoloured per target type)
	_border         = ColorRect.new()
	_border.color   = Color(0.85, 0.15, 0.15, 1.0)
	_border.size    = Vector2(PANEL_W, 2)
	_border.position = Vector2(0, 0)
	panel.add_child(_border)

	# Enemy name
	_name_label                  = Label.new()
	_name_label.text             = ""
	_name_label.position         = Vector2(6, 4)
	_name_label.size             = Vector2(PANEL_W - 12, 14)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 9)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(_name_label)

	# Level label
	_lvl_label                  = Label.new()
	_lvl_label.text             = ""
	_lvl_label.position         = Vector2(6, 16)
	_lvl_label.size             = Vector2(PANEL_W - 12, 10)
	_lvl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lvl_label.add_theme_font_size_override("font_size", 7)
	_lvl_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4, 1))
	_lvl_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_lvl_label.add_theme_constant_override("shadow_offset_x", 1)
	_lvl_label.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(_lvl_label)

	# HP bar background
	_bar_bg          = ColorRect.new()
	_bar_bg.color    = Color(0.15, 0.15, 0.15, 1.0)
	_bar_bg.size     = Vector2(BAR_W, BAR_H)
	_bar_bg.position = Vector2((PANEL_W - BAR_W) / 2.0, 28)
	panel.add_child(_bar_bg)

	# HP bar foreground
	_bar_fg          = ColorRect.new()
	_bar_fg.color    = Color(0.65, 0.08, 0.08, 1.0)
	_bar_fg.size     = Vector2(BAR_W, BAR_H)
	_bar_fg.position = Vector2((PANEL_W - BAR_W) / 2.0, 28)
	panel.add_child(_bar_fg)

	# HP number label
	_hp_label                  = Label.new()
	_hp_label.text             = ""
	_hp_label.position         = Vector2(6, 30)
	_hp_label.size             = Vector2(PANEL_W - 12, BAR_H + 2)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 7)
	_hp_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_hp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_hp_label.add_theme_constant_override("shadow_offset_x", 1)
	_hp_label.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(_hp_label)

func set_target(node: Node) -> void:
	_tracked_enemy = node
	if node == null:
		hide_hud()
		return
	if "enemy_type" in node:
		# Enemy target
		_name_label.text = node.enemy_type
		_border.color    = Color(0.85, 0.15, 0.15, 1.0)  # red for enemies
	elif "username" in node:
		# Player target — green if party member, blue otherwise
		_name_label.text = node.username if node.username != "" else "Player"
		var gs = get_tree().root.get_node_or_null("GameState")
		var in_party = gs != null and node.username != "" and node.username in gs.my_party
		_border.color = Color(0.2, 0.85, 0.35, 1.0) if in_party else Color(0.3, 0.6, 1.0, 1.0)
	else:
		_name_label.text = "?"
		_border.color    = Color(0.85, 0.15, 0.15, 1.0)
	_lvl_label.text  = ""
	_root.visible    = true

func update_target(hp: int, max_hp: int, level: int) -> void:
	if _root == null or not _root.visible:
		return
	_max_hp          = max(max_hp, 1)
	var ratio        = float(hp) / float(_max_hp)
	_bar_fg.size.x   = BAR_W * ratio
	_bar_fg.color    = Color(0.65, 0.08, 0.08, 1.0)  # stays dark red
	_hp_label.text   = "%d/%d" % [hp, _max_hp]
	_lvl_label.text  = "Lv. %d" % level

func update_target_player(hp: int, max_hp: int, level: int = 1) -> void:
	if _root == null or not _root.visible:
		return
	_max_hp          = max(max_hp, 1)
	var ratio        = float(hp) / float(_max_hp)
	_bar_fg.size.x   = BAR_W * ratio
	_bar_fg.color    = Color(0.65, 0.08, 0.08, 1.0)  # dark red
	_hp_label.text   = "%d/%d" % [hp, _max_hp]
	_lvl_label.text  = "Lv. %d" % level

func hide_hud() -> void:
	if _root != null:
		_root.visible = false
