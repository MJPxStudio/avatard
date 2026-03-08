extends CanvasLayer

# ============================================================
# MINIMAP — Top-right HUD overlay.
# Draws local player (white), remote players (blue),
# and enemies (red) as dots within a 500-world-px view radius.
# Updated every frame via queue_redraw().
# ============================================================

const MAP_SIZE:    float = 110.0  # pixel size of the map square
const VIEW_RADIUS: float = 500.0  # world-units shown from center to edge
const PAD:         float = 6.0    # screen edge margin (matches HUD_PAD)
const DOT_SELF:    float = 3.0    # radius of local player dot
const DOT_OTHER:   float = 2.0    # radius of remote dots

const COL_BG:      Color = Color(0.04, 0.04, 0.06, 0.82)
const COL_BORDER:  Color = Color(0.5,  0.5,  0.4,  0.9)
const COL_SELF:    Color = Color(1.0,  1.0,  1.0,  1.0)
const COL_PLAYER:  Color = Color(0.3,  0.6,  1.0,  1.0)
const COL_PARTY:   Color = Color(0.2,  0.95, 0.35, 1.0)
const COL_ENEMY:   Color = Color(1.0,  0.25, 0.25, 1.0)
const COL_DEAD:    Color = Color(0.4,  0.4,  0.4,  0.6)
const COL_ZONE:    Color = Color(0.8,  0.75, 0.5,  1.0)

var _draw_node:  Node2D = null
var _zone_label: Label  = null

func _ready() -> void:
	layer = 50  # above world, below dialogue (90) and fade (128)
	_build()

func _build() -> void:
	# Root control anchored to top-right
	var root            = Control.new()
	root.anchor_left    = 1.0
	root.anchor_right   = 1.0
	root.anchor_top     = 0.0
	root.anchor_bottom  = 0.0
	root.offset_left    = -(MAP_SIZE + PAD)
	root.offset_right   = -PAD
	root.offset_top     = PAD
	root.offset_bottom  = PAD + MAP_SIZE
	root.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Background and border drawn by _draw_node (circle shape)

	# Zone label above the map
	_zone_label                      = Label.new()
	_zone_label.position             = Vector2(0, -(PAD + 12))
	_zone_label.size                 = Vector2(MAP_SIZE, 12)
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.add_theme_font_size_override("font_size", 8)
	_zone_label.add_theme_color_override("font_color", COL_ZONE)
	_zone_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_zone_label.add_theme_constant_override("shadow_offset_x", 1)
	_zone_label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(_zone_label)

	# Drawing node — sits on top of background, clips to map bounds
	_draw_node          = Node2D.new()
	_draw_node.position = Vector2(MAP_SIZE / 2.0, MAP_SIZE / 2.0)
	root.add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)

func _process(_delta: float) -> void:
	if _draw_node:
		_draw_node.queue_redraw()
	# Update zone label
	if _zone_label:
		var gs = get_tree().root.get_node_or_null("GameState")
		if gs:
			_zone_label.text = gs.current_zone.capitalize()

func _world_to_map(world_pos: Vector2, origin: Vector2) -> Vector2:
	# Convert world position relative to local player into map pixel offset
	var rel   = world_pos - origin
	var scale = (MAP_SIZE / 2.0) / VIEW_RADIUS
	return rel * scale

func _on_draw() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return
	var player = get_tree().get_first_node_in_group("local_player")
	if player == null or not is_instance_valid(player):
		return

	var origin: Vector2 = player.global_position
	var half = MAP_SIZE / 2.0
	var radius = half

	# Circle background and border
	_draw_node.draw_circle(Vector2.ZERO, radius, COL_BG)
	# Border ring — draw as a slightly larger circle outline
	for i in 180:
		var a0 = (float(i) / 180.0) * TAU
		var a1 = (float(i + 1) / 180.0) * TAU
		_draw_node.draw_line(
			Vector2(cos(a0), sin(a0)) * radius,
			Vector2(cos(a1), sin(a1)) * radius,
			COL_BORDER, 1.5)

	# Remote enemies
	for enemy in gs.remote_enemy_nodes.values():
		if not is_instance_valid(enemy):
			continue
		var mp = _world_to_map(enemy.global_position, origin)
		if mp.length() > radius - DOT_OTHER:
			continue
		var col = COL_DEAD if enemy.is_dead else COL_ENEMY
		_draw_node.draw_circle(mp, DOT_OTHER, col)

	# Remote players — only same zone
	for state in gs.remote_players.values():
		if state.get("zone", "") != gs.current_zone:
			continue
		var pos = state.get("position", Vector2.ZERO)
		var mp  = _world_to_map(pos, origin)
		if mp.length() > radius - DOT_OTHER:
			continue
		var is_dead  = state.get("is_dead", false)
		var uname    = state.get("username", "")
		var in_party = uname != "" and uname in gs.my_party
		var col = COL_DEAD if is_dead else (COL_PARTY if in_party else COL_PLAYER)
		_draw_node.draw_circle(mp, DOT_OTHER, col)

	# Local player — always center
	_draw_node.draw_circle(Vector2.ZERO, DOT_SELF, COL_SELF)
