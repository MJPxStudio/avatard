extends CanvasLayer

# ============================================================
# STAT PANEL — 5 stats, temp allocation, confirm button
# ============================================================

const SPRITE_SIZE = Vector2(180, 280)
const SCALE       = 1.5

# Stat definitions
const STATS = ["hp", "chakra", "strength", "dex", "int"]
const STAT_LABELS = ["HP", "Chakra", "Strength", "Dexterity", "Intelligence"]

# Layout
const PANEL_PADDING   = 16
const ROW_START_Y     = 45    # first stat row Y in sprite space
const ROW_HEIGHT      = 34    # pixels between rows
const BTN_SIZE        = Vector2(16, 16)

# Drag
var is_dragging:  bool    = false
var drag_offset:  Vector2 = Vector2.ZERO
var window_root:  Control

# Stat data — set by player
var base_stats:   Dictionary = {hp=5, chakra=5, strength=5, dex=5, int=5}
var temp_alloc:   Dictionary = {hp=0, chakra=0, strength=0, dex=0, int=0}
var points_available: int = 0

# UI refs
var points_label: Label
var stat_value_labels: Dictionary = {}
var stat_pending_labels: Dictionary = {}
var minus_buttons: Dictionary = {}
var plus_buttons: Dictionary = {}
var confirm_btn: Button
var player_ref = null

func _ready() -> void:
	_build_ui()
	visible = false

func _build_ui() -> void:
	window_root = Control.new()
	window_root.size = SPRITE_SIZE * SCALE
	window_root.position = Vector2(400, 100)
	add_child(window_root)

	# Background
	var bg = TextureRect.new()
	bg.texture = load("res://sprites/stats/stat_panel.png")
	bg.size = SPRITE_SIZE * SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	window_root.add_child(bg)

	# Drag bar
	var drag_bar = Control.new()
	drag_bar.size = Vector2(SPRITE_SIZE.x * SCALE, 24)
	drag_bar.position = Vector2.ZERO
	drag_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_bar.gui_input.connect(_on_drag_input)
	window_root.add_child(drag_bar)

	# Title
	var title = Label.new()
	title.text = "CHARACTER"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color("ffd700"))
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.position = Vector2(0, 8) * SCALE
	title.size = Vector2(SPRITE_SIZE.x, 14) * SCALE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	window_root.add_child(title)

	# Points available label
	points_label = Label.new()
	points_label.add_theme_font_size_override("font_size", 9)
	points_label.add_theme_color_override("font_color", Color("88ff88"))
	points_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	points_label.add_theme_constant_override("shadow_offset_x", 1)
	points_label.add_theme_constant_override("shadow_offset_y", 1)
	points_label.position = Vector2(0, 24) * SCALE
	points_label.size = Vector2(SPRITE_SIZE.x, 12) * SCALE
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	window_root.add_child(points_label)

	# Stat rows
	for i in range(5):
		var stat = STATS[i]
		var row_y = (ROW_START_Y + i * ROW_HEIGHT) * SCALE

		# Stat label
		var name_lbl = Label.new()
		name_lbl.text = STAT_LABELS[i]
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		name_lbl.add_theme_constant_override("shadow_offset_x", 1)
		name_lbl.add_theme_constant_override("shadow_offset_y", 1)
		name_lbl.position = Vector2(PANEL_PADDING * SCALE, row_y + 2 * SCALE)
		name_lbl.size = Vector2(80 * SCALE, 14 * SCALE)
		window_root.add_child(name_lbl)

		# Current value
		var val_lbl = Label.new()
		val_lbl.add_theme_font_size_override("font_size", 9)
		val_lbl.add_theme_color_override("font_color", Color("ffd700"))
		val_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		val_lbl.add_theme_constant_override("shadow_offset_x", 1)
		val_lbl.add_theme_constant_override("shadow_offset_y", 1)
		val_lbl.position = Vector2(PANEL_PADDING * SCALE, row_y + 11 * SCALE)
		val_lbl.size = Vector2(40 * SCALE, 12 * SCALE)
		window_root.add_child(val_lbl)
		stat_value_labels[stat] = val_lbl

		# Pending allocation label (shows +N in green)
		var pend_lbl = Label.new()
		pend_lbl.add_theme_font_size_override("font_size", 9)
		pend_lbl.add_theme_color_override("font_color", Color("88ff88"))
		pend_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		pend_lbl.add_theme_constant_override("shadow_offset_x", 1)
		pend_lbl.add_theme_constant_override("shadow_offset_y", 1)
		pend_lbl.position = Vector2(55 * SCALE, row_y + 11 * SCALE)
		pend_lbl.size = Vector2(30 * SCALE, 12 * SCALE)
		pend_lbl.text = ""
		window_root.add_child(pend_lbl)
		stat_pending_labels[stat] = pend_lbl

		# Minus button
		var minus_btn = _make_small_btn("-", Color("ff6666"))
		minus_btn.position = Vector2(110 * SCALE, row_y + 8 * SCALE)
		minus_btn.pressed.connect(func(): _on_minus(stat))
		window_root.add_child(minus_btn)
		minus_buttons[stat] = minus_btn

		# Plus button
		var plus_btn = _make_small_btn("+", Color("88ff88"))
		plus_btn.position = Vector2(135 * SCALE, row_y + 8 * SCALE)
		plus_btn.pressed.connect(func(): _on_plus(stat))
		window_root.add_child(plus_btn)
		plus_buttons[stat] = plus_btn

		# Stat description
		var desc_lbl = Label.new()
		desc_lbl.text = _stat_description(stat)
		desc_lbl.add_theme_font_size_override("font_size", 7)
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		desc_lbl.position = Vector2(PANEL_PADDING * SCALE, row_y + 22 * SCALE)
		desc_lbl.size = Vector2(160 * SCALE, 10 * SCALE)
		window_root.add_child(desc_lbl)

	# Confirm button
	confirm_btn = Button.new()
	confirm_btn.text = "CONFIRM"
	confirm_btn.position = Vector2(45 * SCALE, 222 * SCALE)
	confirm_btn.size = Vector2(90 * SCALE, 22 * SCALE)
	confirm_btn.add_theme_font_size_override("font_size", 10)
	confirm_btn.add_theme_color_override("font_color", Color("ffd700"))
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.15, 0.05)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = Color("ffd700")
	confirm_btn.add_theme_stylebox_override("normal", style)
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.35, 0.25, 0.05)
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_color = Color("ffd700")
	confirm_btn.add_theme_stylebox_override("hover", style_hover)
	confirm_btn.pressed.connect(_on_confirm)
	window_root.add_child(confirm_btn)

	_refresh_ui()

func _make_small_btn(label: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.size = BTN_SIZE * SCALE
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", color)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.1, 0.05)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = color
	btn.add_theme_stylebox_override("normal", style)
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.3, 0.2, 0.05)
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_color = color
	btn.add_theme_stylebox_override("hover", style_hover)
	return btn

func _stat_description(stat: String) -> String:
	match stat:
		"hp":       return "+5 Max HP per point"
		"chakra":   return "+3 Max Chakra per point"
		"strength": return "Scales physical damage"
		"dex":      return "+0.2% dodge, CD reduction"
		"int":      return "Scales jutsu damage"
	return ""

func _on_plus(stat: String) -> void:
	if points_available <= 0:
		return
	temp_alloc[stat] += 1
	points_available -= 1
	_refresh_ui()

func _on_minus(stat: String) -> void:
	if temp_alloc[stat] <= 0:
		return
	temp_alloc[stat] -= 1
	points_available += 1
	_refresh_ui()

func _on_confirm() -> void:
	if player_ref == null:
		return
	for stat in STATS:
		base_stats[stat] += temp_alloc[stat]
		temp_alloc[stat] = 0
	player_ref.apply_stats(base_stats)
	_refresh_ui()

func _refresh_ui() -> void:
	points_label.text = "Points Available: %d" % points_available
	confirm_btn.disabled = points_available == points_available  # always enabled to allow viewing
	confirm_btn.disabled = _has_pending() == false

	for stat in STATS:
		var total = base_stats[stat] + temp_alloc[stat]
		stat_value_labels[stat].text = str(base_stats[stat])
		if temp_alloc[stat] > 0:
			stat_pending_labels[stat].text = "+%d" % temp_alloc[stat]
		else:
			stat_pending_labels[stat].text = ""
		# Grey out + if no points, grey out - if no pending
		plus_buttons[stat].disabled = points_available <= 0
		minus_buttons[stat].disabled = temp_alloc[stat] <= 0

func _has_pending() -> bool:
	for stat in STATS:
		if temp_alloc[stat] > 0:
			return true
	return false

func set_player(player) -> void:
	player_ref = player
	base_stats = {
		hp       = player.stat_hp,
		chakra   = player.stat_chakra,
		strength = player.stat_strength,
		dex      = player.stat_dex,
		int      = player.stat_int
	}
	points_available = player.stat_points
	_refresh_ui()

func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_dragging = event.pressed
		if is_dragging:
			drag_offset = window_root.get_global_mouse_position() - window_root.global_position
	elif event is InputEventMouseMotion and is_dragging:
		window_root.global_position = window_root.get_global_mouse_position() - drag_offset

func toggle() -> void:
	visible = !visible
	if visible and player_ref != null:
		# Reset any unconfirmed allocations before showing
		for stat in STATS:
			temp_alloc[stat] = 0
		set_player(player_ref)
