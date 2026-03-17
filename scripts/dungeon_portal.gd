extends Node2D

# ============================================================
# DUNGEON PORTAL
# Leader-only multi-step entrance UI:
#   1. Dungeon Selection  — tall cards per dungeon
#   2. Difficulty Screen  — floors, enemies, boss info
#   3. Ready Check        — handled by dungeon_ready_ui.gd
#
# Non-leaders see a "Waiting for party leader" notice.
# ============================================================

const DungeonData = preload("res://scripts/dungeon_data.gd")

@export var dungeon_id: String = ""  # legacy — kept so existing scenes don't error; not used

var _prompt:      Label       = null
var _status_lbl:  Label       = null
var _player_near: bool        = false
var _locked:      bool        = false
var _ready_timer: float       = 1.5

# UI canvas
var _canvas:      CanvasLayer = null
var _screen:      String      = ""   # "" | "select" | "difficulty"
var _selected_id: String      = ""

# ── Colours ──────────────────────────────────────────────────
const C_BG     = Color(0.04, 0.03, 0.06, 0.96)
const C_BORDER = Color(0.28, 0.22, 0.40, 1.0)
const C_TITLE  = Color(1.0,  0.88, 0.40, 1.0)
const C_TEXT   = Color(0.85, 0.85, 0.90, 1.0)
const C_MUTED  = Color(0.55, 0.55, 0.65, 1.0)
const C_EASY   = Color(0.25, 0.75, 0.35, 1.0)
const C_MEDIUM = Color(0.85, 0.68, 0.15, 1.0)
const C_HARD   = Color(0.85, 0.22, 0.18, 1.0)

func _ready() -> void:
	_build_world_visual()
	_build_proximity_area()
	_canvas = CanvasLayer.new()
	_canvas.layer = 42
	add_child(_canvas)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.dungeon_portal_locked_received.connect(_on_portal_locked)
		net.ready_check_updated.connect(_on_ready_check_started)

# ── World sprite ─────────────────────────────────────────────

func _build_world_visual() -> void:
	var base = ColorRect.new()
	base.size = Vector2(38, 44); base.position = Vector2(-19, -44)
	base.color = Color(0.10, 0.07, 0.14); add_child(base)
	var arch = ColorRect.new()
	arch.size = Vector2(38, 10); arch.position = Vector2(-19, -54)
	arch.color = Color(0.22, 0.12, 0.34); add_child(arch)
	var glow = ColorRect.new()
	glow.size = Vector2(20, 26); glow.position = Vector2(-10, -42)
	glow.color = Color(0.35, 0.12, 0.65, 0.7); add_child(glow)
	var lbl = Label.new()
	lbl.text = "Dungeon"; lbl.position = Vector2(-24, -68)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", C_TITLE); add_child(lbl)
	_status_lbl = Label.new()
	_status_lbl.position = Vector2(-32, -80)
	_status_lbl.add_theme_font_size_override("font_size", 7)
	_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_status_lbl.visible = false; add_child(_status_lbl)
	_prompt = Label.new()
	_prompt.text = "[E] Enter Dungeon"; _prompt.position = Vector2(-42, -92)
	_prompt.add_theme_font_size_override("font_size", 8)
	_prompt.add_theme_color_override("font_color", Color(1, 1, 0.8))
	_prompt.visible = false; add_child(_prompt)

func _build_proximity_area() -> void:
	var area = Area2D.new()
	area.collision_layer = 0; area.collision_mask = 1
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new(); circle.radius = 52
	shape.shape = circle; area.add_child(shape)
	area.body_entered.connect(_on_proximity_entered)
	area.body_exited.connect(_on_proximity_exited)
	add_child(area)

# ── Input ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _ready_timer > 0.0:
		_ready_timer -= delta
	if _player_near and not _locked and _ready_timer <= 0.0 and _screen == "":
		if Input.is_action_just_pressed("interact"):
			_on_interact()
	if _screen != "" and Input.is_action_just_pressed("ui_cancel"):
		_close_ui()

func _on_proximity_entered(body: Node) -> void:
	if body.is_in_group("local_player"):
		_player_near = true
		if not _locked and _screen == "":
			_prompt.visible = true

func _on_proximity_exited(body: Node) -> void:
	if body.is_in_group("local_player"):
		_player_near = false
		_prompt.visible = false

func _on_interact() -> void:
	if not _is_leader():
		_show_not_leader_toast()
		return
	_prompt.visible = false
	_open_dungeon_select()

# ── Leader check ──────────────────────────────────────────────

func _is_leader() -> bool:
	var gs = get_tree().root.get_node_or_null("GameState")
	if not gs:
		return true
	if gs.my_party.is_empty() or gs.my_party.size() <= 1:
		return true
	return gs.my_username == gs.my_party_leader

func _show_not_leader_toast() -> void:
	for c in _canvas.get_children():
		c.queue_free()
	var lbl = Label.new()
	lbl.text = "Only the party leader can enter the dungeon."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl.offset_top = 80; lbl.offset_left = -220; lbl.offset_right = 220
	_canvas.add_child(lbl)
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(lbl): lbl.queue_free()
	, CONNECT_ONE_SHOT)

# ── UI helpers ────────────────────────────────────────────────

func _clear_canvas() -> void:
	for c in _canvas.get_children():
		c.queue_free()

func _close_ui() -> void:
	_clear_canvas()
	_screen = ""
	if _player_near and not _locked:
		_prompt.visible = true

func _make_panel(w: float, h: float) -> Panel:
	var p = Panel.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -w / 2.0; p.offset_right  =  w / 2.0
	p.offset_top  = -h / 2.0; p.offset_bottom =  h / 2.0
	var s = StyleBoxFlat.new()
	s.bg_color = C_BG
	s.set_corner_radius_all(10)
	s.set_border_width_all(1)
	s.border_color = C_BORDER
	p.add_theme_stylebox_override("panel", s)
	_canvas.add_child(p)
	return p

func _make_btn(text: String, color: Color, parent: Control,
		x: float, y: float, w: float, h: float) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.position = Vector2(x, y); btn.size = Vector2(w, h)
	var s  = StyleBoxFlat.new()
	s.bg_color = Color(color.r, color.g, color.b, 0.18)
	s.set_corner_radius_all(6); s.set_border_width_all(1)
	s.border_color = color
	var sh = StyleBoxFlat.new()
	sh.bg_color = Color(color.r, color.g, color.b, 0.36)
	sh.set_corner_radius_all(6); sh.set_border_width_all(1)
	sh.border_color = Color(min(color.r * 1.3, 1.0), min(color.g * 1.3, 1.0), min(color.b * 1.3, 1.0))
	btn.add_theme_stylebox_override("normal",  s)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sh)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_font_size_override("font_size", 11)
	parent.add_child(btn)
	return btn

func _lbl(text: String, size: int, color: Color, parent: Control,
		x: float, y: float, w: float = 0.0, center: bool = false) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.position = Vector2(x, y)
	if w > 0:
		l.size = Vector2(w, 28)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

# ── Screen 1: Dungeon Selection ───────────────────────────────

func _open_dungeon_select() -> void:
	_clear_canvas()
	_screen = "select"

	var dungeons = DungeonData.DUNGEONS
	var count    = dungeons.size()
	var card_w   = 220.0
	var card_h   = 430.0
	var gap      = 24.0
	var pw       = count * card_w + (count - 1) * gap + 80.0
	var ph       = card_h + 90.0

	var panel = _make_panel(pw, ph)
	panel.clip_contents = false

	_lbl("Select Dungeon", 14, C_TITLE, panel, 0, 16, pw, true)

	var close_btn = _make_btn("✕", C_MUTED, panel, pw - 44, 10, 30, 26)
	close_btn.pressed.connect(_close_ui)

	var idx = 0
	for did in dungeons:
		var def    = dungeons[did]
		var card_x = 40.0 + idx * (card_w + gap)
		_build_dungeon_card(panel, did, def, card_x, 54.0, card_w, card_h)
		idx += 1

func _build_dungeon_card(parent: Control, dungeon_id: String, def: Dictionary,
		x: float, y: float, w: float, h: float) -> void:
	var accent: Color = def.get("accent_color", Color(0.4, 0.3, 0.6))

	# Outer container — just a plain Control, no StyleBox fighting
	var card = Control.new()
	card.position = Vector2(x, y)
	card.size = Vector2(w, h)
	parent.add_child(card)

	# Background PNG — handles all the art (diagonal, border, rounding)
	var bg = TextureRect.new()
	var bg_path: String = def.get("card_bg", "")
	if bg_path != "" and ResourceLoader.exists(bg_path):
		bg.texture = ResourceLoader.load(bg_path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	# VBox for all content — anchored full rect with margins
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10; vbox.offset_right = -10
	vbox.offset_top = 8;   vbox.offset_bottom = -12
	card.add_child(vbox)

	# Icon
	var icon_path: String = def.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex = ResourceLoader.load(icon_path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
		if tex:
			var icon_rect = TextureRect.new()
			icon_rect.texture = tex
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.custom_minimum_size = Vector2(0, 100)
			icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.add_child(icon_rect)

	var name_lbl = Label.new()
	name_lbl.text = def.get("display_name", dungeon_id)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(name_lbl)

	var lvl_lbl = Label.new()
	lvl_lbl.text = "Min Level %d" % def.get("min_level", 1)
	lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lvl_lbl.add_theme_font_size_override("font_size", 8)
	lvl_lbl.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(lvl_lbl)

	var divider = ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(accent.r * 0.5, accent.g * 0.35, accent.b * 0.15, 0.5)
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(divider)

	var sp1 = Control.new(); sp1.custom_minimum_size = Vector2(0, 6); vbox.add_child(sp1)

	var desc = Label.new()
	desc.text = def.get("description", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", 8)
	desc.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(desc)

	var elbl = Label.new()
	elbl.text = "Enemies: " + ", ".join(def.get("enemy_types", []) as Array)
	elbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elbl.add_theme_font_size_override("font_size", 8)
	elbl.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(elbl)

	var sp2 = Control.new(); sp2.custom_minimum_size = Vector2(0, 8); vbox.add_child(sp2)

	var btn = _make_btn("Select  \u25b6", accent, vbox, 0, 0, 0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func(): _open_difficulty_select(dungeon_id))

# ── Screen 2: Difficulty ─────────────────────────────────────

func _open_difficulty_select(dungeon_id: String) -> void:
	_clear_canvas()
	_screen    = "difficulty"
	_selected_id = dungeon_id

	var def        = DungeonData.get_dungeon(dungeon_id)
	var accent     = def.get("accent_color", Color(0.4, 0.3, 0.6))
	var theme_data = load(def.get("theme_script", "res://scripts/wolf_den_data.gd")).new()

	var pw = 500.0; var ph = 370.0
	var panel = _make_panel(pw, ph)

	var back_btn = _make_btn("◀ Back", C_MUTED, panel, 14, 10, 84, 28)
	back_btn.pressed.connect(_open_dungeon_select)

	_lbl(def.get("display_name", dungeon_id), 14, C_TITLE,  panel, 0, 14, pw, true)
	_lbl("Select Difficulty", 9,  C_MUTED, panel, 0, 36, pw, true)

	var div = ColorRect.new()
	div.size = Vector2(pw - 40, 1); div.position = Vector2(20, 58)
	div.color = C_BORDER; panel.add_child(div)

	var etypes: Array = def.get("enemy_types", [])
	_lbl("Enemies: " + ", ".join(etypes), 8, C_MUTED, panel, 24, 66)

	var diffs = [
		{ "id": "easy",   "label": "Easy",   "color": C_EASY,   "x": 24.0  },
		{ "id": "medium", "label": "Medium", "color": C_MEDIUM, "x": 186.0 },
		{ "id": "hard",   "label": "Hard",   "color": C_HARD,   "x": 348.0 },
	]
	for d in diffs:
		var floors: int   = theme_data.FLOOR_COUNTS.get(d["id"], 3)
		var boss: String  = theme_data.BOSSES.get(d["id"], {}).get("label", "Boss")
		var rcfg: Dictionary = theme_data.ROOMS_PER_FLOOR.get(d["id"], {"min": 4, "max": 6})
		_build_diff_card(panel, dungeon_id, d["id"], d["label"], d["color"],
			d["x"], 88.0, 138.0, 240.0, floors, boss, rcfg)

func _build_diff_card(parent: Control, dungeon_id: String,
		diff_id: String, diff_label: String, accent: Color,
		x: float, y: float, w: float, h: float,
		floors: int, boss: String, rooms: Dictionary) -> void:

	var card = Panel.new()
	card.position = Vector2(x, y)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(accent.r * 0.11, accent.g * 0.11, accent.b * 0.11, 0.95)
	s.set_corner_radius_all(8); s.set_border_width_all(1)
	s.border_color = Color(accent.r * 0.45, accent.g * 0.45, accent.b * 0.45)
	card.add_theme_stylebox_override("panel", s)
	parent.add_child(card)

	var band = ColorRect.new()
	band.size = Vector2(w, 5); band.color = accent; card.add_child(band)

	_lbl(diff_label, 13, accent, card, 0, 14, w, true)

	var stats = [
		["Floors",        str(floors)],
		["Rooms / Floor", "%d – %d" % [rooms.get("min", 4), rooms.get("max", 6)]],
		["Boss",          boss],
	]
	for i in range(stats.size()):
		var ry = 46.0 + i * 46.0
		_lbl(stats[i][0], 7, C_MUTED, card, 0, ry,       w, true)
		_lbl(stats[i][1], 10, C_TEXT, card, 0, ry + 16.0, w, true)

	var btn = _make_btn("Confirm", accent, card, 12, h - 46, w - 24, 34)
	btn.pressed.connect(func(): _confirm_difficulty(dungeon_id, diff_id))

# ── Confirm ───────────────────────────────────────────────────

func _confirm_difficulty(dungeon_id: String, difficulty: String) -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if not net or not net.is_network_connected():
		return
	_close_ui()
	net.request_ready_check.rpc_id(1, dungeon_id, difficulty)

# ── Portal locked ─────────────────────────────────────────────

func _on_portal_locked(did: String, locked: bool) -> void:
	_locked = locked
	_status_lbl.text    = "In Progress" if locked else ""
	_status_lbl.visible = locked
	if locked:
		_prompt.visible = false
		if _screen != "":
			_close_ui()

func _on_ready_check_started(_members: Array, _dungeon_id: String) -> void:
	if _screen != "":
		_close_ui()
