extends CanvasLayer

# ══════════════════════════════════════════════════════════════════════════════
# CHARACTER INFO PANEL — replaces stat_panel.gd
# ══════════════════════════════════════════════════════════════════════════════

const SPRITE_SIZE = Vector2(180, 280)
const SCALE       = 1.5
const W           = 180.0

const STATS       = ["hp", "chakra", "strength", "dex", "int"]
const STAT_LABELS = ["HP", "Chakra", "Strength", "Dexterity", "Intelligence"]
const BTN_SIZE    = Vector2(16, 16)
const LM          = 12.0
const RM          = 12.0

var is_dragging: bool    = false
var drag_offset: Vector2 = Vector2.ZERO
var window_root: Control

var player_ref = null
var base_stats:       Dictionary = {hp=5, chakra=5, strength=5, dex=5, int=5}
var temp_alloc:       Dictionary = {hp=0, chakra=0, strength=0, dex=0, int=0}
var points_available: int = 0

var _username_lbl:   Label
var _rank_lbl:       Label
var _level_lbl:      Label
var _xp_lbl:         Label
var _clan_lbl:       Label
var _kd_lbl:         Label
var _points_lbl:     Label
var _confirm_btn:    Button
var _gear_bonuses:   Dictionary = {hp=0,chakra=0,strength=0,dex=0,int=0}
var _stat_val_lbls:  Dictionary = {}
var _stat_pend_lbls: Dictionary = {}
var _minus_btns:     Dictionary = {}
var _plus_btns:      Dictionary = {}

func _ready() -> void:
	_build_ui()
	visible = false

func _build_ui() -> void:
	window_root = Control.new()
	window_root.size = SPRITE_SIZE * SCALE
	window_root.position = Vector2(400, 60)
	add_child(window_root)

	var bg = TextureRect.new()
	bg.texture = load("res://sprites/stats/stat_panel.png")
	bg.size = SPRITE_SIZE * SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	window_root.add_child(bg)

	var drag_bar = Control.new()
	drag_bar.size = Vector2(SPRITE_SIZE.x * SCALE, 20)
	drag_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_bar.gui_input.connect(_on_drag_input)
	window_root.add_child(drag_bar)

	# Title
	_lbl("CHARACTER",  0,  7, W, 12, Color("ffd700"), true, 11)
	# Username
	_username_lbl = _lbl("...", 0, 20, W, 14, Color("ffffff"), true, 12)
	# Rank
	_rank_lbl = _lbl("Academy Student", 0, 35, W, 10, Color("aaaaaa"), true, 8)

	_divider(47)

	# Info grid: two columns
	_lbl("LEVEL", LM,           51, 30,  8, Color(0.55,0.55,0.55), false, 7)
	_level_lbl = _lbl("1",      LM+32,   51, 20,  9, Color("f0c040"), false, 9)
	_lbl("XP",   W-RM-65,       51, 16,  8, Color(0.55,0.55,0.55), false, 7)
	_xp_lbl = _lbl("0 / 100",   W-RM-48, 51, 60,  9, Color("88aaff"), false, 9)

	_lbl("CLAN", LM,            63, 26,  8, Color(0.55,0.55,0.55), false, 7)
	_clan_lbl = _lbl("—",       LM+28,   63, 55,  9, Color("cc88ff"), false, 9)
	_lbl("K/D",  W-RM-65,       63, 18,  8, Color(0.55,0.55,0.55), false, 7)
	_kd_lbl = _lbl("0/0 0.00",  W-RM-46, 63, 58,  9, Color(0.85,0.85,0.85), false, 9)

	_divider(74)

	# Stats section header
	_points_lbl = _lbl("Points Available: 0", 0, 77, W, 9, Color("88ff88"), true, 8)

	# Column labels
	_lbl("STAT",  LM,      86, 60, 7, Color(0.45,0.45,0.45), false, 7)
	_lbl("BASE",  LM+60,   86, 28, 7, Color(0.45,0.45,0.45), false, 7)
	_lbl("+ALLOC",LM+87,   86, 36, 7, Color(0.45,0.45,0.45), false, 7)

	var ROW_Y = 94
	var ROW_H = 23
	for i in range(5):
		var stat = STATS[i]
		var ry   = ROW_Y + i * ROW_H

		_lbl(STAT_LABELS[i], LM,    ry, 55, 9, Color("ffffff"), false, 9)
		_lbl(_stat_desc(stat), LM,  ry+11, 105, 7, Color(0.5,0.5,0.5), false, 7)

		var val_lbl = _lbl("5",   LM+60,  ry, 28, 9, Color("ffd700"), false, 9)
		_stat_val_lbls[stat] = val_lbl

		var pend_lbl = _lbl("",  LM+88,  ry, 28, 9, Color("88ff88"), false, 9)
		_stat_pend_lbls[stat] = pend_lbl

		var minus_btn = _small_btn("-", Color("ff6666"))
		minus_btn.position = Vector2((LM + 118) * SCALE, ry * SCALE)
		minus_btn.pressed.connect(func(): _on_minus(stat))
		window_root.add_child(minus_btn)
		_minus_btns[stat] = minus_btn

		var plus_btn = _small_btn("+", Color("88ff88"))
		plus_btn.position = Vector2((LM + 136) * SCALE, ry * SCALE)
		plus_btn.pressed.connect(func(): _on_plus(stat))
		window_root.add_child(plus_btn)
		_plus_btns[stat] = plus_btn

	_confirm_btn = Button.new()
	_confirm_btn.text = "CONFIRM"
	_confirm_btn.position = Vector2(45 * SCALE, 240 * SCALE)
	_confirm_btn.size = Vector2(90 * SCALE, 19 * SCALE)
	_confirm_btn.add_theme_font_size_override("font_size", 10)
	_confirm_btn.add_theme_color_override("font_color", Color("ffd700"))
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.2,0.15,0.05)
	st.set_border_width_all(1)
	st.border_color = Color("ffd700")
	_confirm_btn.add_theme_stylebox_override("normal", st)
	var sth = StyleBoxFlat.new()
	sth.bg_color = Color(0.35,0.25,0.05)
	sth.set_border_width_all(1)
	sth.border_color = Color("ffd700")
	_confirm_btn.add_theme_stylebox_override("hover", sth)
	_confirm_btn.pressed.connect(_on_confirm)
	window_root.add_child(_confirm_btn)

	_refresh_ui()

func _lbl(text:String, x:float, y:float, w:float, h:float,
		color:Color, centered:bool=false, font_size:int=9) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y) * SCALE
	lbl.size = Vector2(w, h) * SCALE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	if centered:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	window_root.add_child(lbl)
	return lbl

func _divider(y:float) -> void:
	var line = ColorRect.new()
	line.color = Color(1,1,1,0.15)
	line.position = Vector2(LM * SCALE, y * SCALE)
	line.size = Vector2((W - LM - RM) * SCALE, 1)
	window_root.add_child(line)

func _small_btn(label:String, color:Color) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.size = BTN_SIZE * SCALE
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", color)
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.15,0.1,0.05)
	st.set_border_width_all(1)
	st.border_color = color
	btn.add_theme_stylebox_override("normal", st)
	var sth = StyleBoxFlat.new()
	sth.bg_color = Color(0.3,0.2,0.05)
	sth.set_border_width_all(1)
	sth.border_color = color
	btn.add_theme_stylebox_override("hover", sth)
	return btn

func _stat_desc(stat:String) -> String:
	match stat:
		"hp":       return "+5 Max HP / point"
		"chakra":   return "+3 Max Chakra / point"
		"strength": return "Scales physical damage"
		"dex":      return "+0.2% dodge, CD reduction"
		"int":      return "Scales jutsu damage"
	return ""

func _on_plus(stat:String) -> void:
	if points_available <= 0: return
	temp_alloc[stat] += 1
	points_available -= 1
	_refresh_ui()

func _on_minus(stat:String) -> void:
	if temp_alloc[stat] <= 0: return
	temp_alloc[stat] -= 1
	points_available += 1
	_refresh_ui()

func _on_confirm() -> void:
	if player_ref == null: return
	var spent = 0
	for stat in STATS:
		spent += temp_alloc[stat]
		base_stats[stat] += temp_alloc[stat]
		temp_alloc[stat] = 0
	player_ref.apply_stats(base_stats)
	player_ref.stat_points = max(0, player_ref.stat_points - spent)
	points_available = player_ref.stat_points
	_refresh_ui()
	var net = player_ref.get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.send_spend_stats.rpc_id(1,
			base_stats.hp, base_stats.chakra, base_stats.strength,
			base_stats.dex, base_stats.int)

func _refresh_ui() -> void:
	_points_lbl.text = "Points Available: %d" % points_available
	_confirm_btn.disabled = not _has_pending()
	for stat in STATS:
		var gear = _gear_bonuses.get(stat, 0)
		if gear > 0:
			_stat_val_lbls[stat].text = "%d (+%d)" % [base_stats[stat], gear]
		else:
			_stat_val_lbls[stat].text = str(base_stats[stat])
		_stat_pend_lbls[stat].text = ("+%d" % temp_alloc[stat]) if temp_alloc[stat] > 0 else ""
		_plus_btns[stat].disabled  = points_available <= 0
		_minus_btns[stat].disabled = temp_alloc[stat] <= 0

func _has_pending() -> bool:
	for stat in STATS:
		if temp_alloc[stat] > 0: return true
	return false

func set_player(player) -> void:
	player_ref = player
	_username_lbl.text = player.username if player.username != "" else "Player"
	var lv: int = player.level
	_rank_lbl.text = RankDB.get_rank_name(lv)
	_rank_lbl.add_theme_color_override("font_color", RankDB.get_rank_color(lv))
	_level_lbl.text = str(lv)
	_xp_lbl.text = "%d / %d" % [player.current_exp, player.max_exp]
	var clan: String = player.get("clan") if player.get("clan") != null else ""
	_clan_lbl.text = clan if clan != "" else "—"
	update_kd(player.kills, player.deaths)
	base_stats = {
		hp=player.stat_hp, chakra=player.stat_chakra,
		strength=player.stat_strength, dex=player.stat_dex, int=player.stat_int
	}
	_gear_bonuses = {
		hp=player.get("gear_hp") if player.get("gear_hp") != null else 0,
		chakra=player.get("gear_chakra") if player.get("gear_chakra") != null else 0,
		strength=player.get("gear_str") if player.get("gear_str") != null else 0,
		dex=player.get("gear_dex") if player.get("gear_dex") != null else 0,
		int=player.get("gear_int") if player.get("gear_int") != null else 0,
	}
	points_available = player.stat_points
	_refresh_ui()

func update_kd(kills:int, deaths:int) -> void:
	_kd_lbl.text = "%d/%d  %.2f" % [kills, deaths, float(kills)/float(max(deaths,1))]

func update_xp(current:int, maximum:int) -> void:
	_xp_lbl.text = "%d / %d" % [current, maximum]

func toggle() -> void:
	visible = !visible
	if visible and player_ref != null:
		for stat in STATS: temp_alloc[stat] = 0
		set_player(player_ref)

func _on_drag_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_dragging = event.pressed
		if is_dragging:
			drag_offset = window_root.get_global_mouse_position() - window_root.global_position
	elif event is InputEventMouseMotion and is_dragging:
		window_root.global_position = window_root.get_global_mouse_position() - drag_offset
