extends Node2D

# ============================================================
# DUNGEON WORLD — Terrain-based procedural dungeon renderer
# Uses set_cells_terrain_connect for clean autotiling
# ============================================================

const TILE        = 32
const WALL_TILES  = 2

# These update each room entry — not const
var _room_tiles_w: int = 28
var _room_tiles_h: int = 19

# Derived — recomputed from the vars above
var ROOM_W: int = 0
var ROOM_H: int = 0
var TF: int = TILE * WALL_TILES   # 64px — stays constant

# Room type constants (matches dungeon_room_db.gd enum order)
const RT_COMBAT   = 0
const RT_ELITE    = 1
const RT_MINIBOSS = 2
const RT_BOSS     = 3
const RT_SHOP     = 4
const RT_REST     = 5
const RT_START    = 6
const RT_TREASURE = 7

# Terrain set index
const TERRAIN_SET = 0

# Terrain indices — must match order created in TileSet editor
const T_WOLF_DIRT      = 0
const T_WOLF_DARK_DIRT = 1
const T_WOLF_STONE     = 2
const T_CAVE_STONE     = 3

# ── State ─────────────────────────────────────────────────────
var _floor_terrain: int = T_WOLF_DIRT
var _wall_terrain:  int = T_WOLF_STONE

var _layer_floor: TileMapLayer = null
var _bg:          ColorRect    = null
var _room_node:   Node2D       = null
var _wall_node:   Node2D       = null  # permanent — never freed between rooms
var _exit_nodes:  Array        = []
var _fade_rect:   ColorRect    = null   # room-to-room fade overlay
var _entrance_node: Node2D     = null   # entrance arch — freed each room
var _current_room: int         = -1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ── Lifecycle ─────────────────────────────────────────────────

func _ready() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		var zone = gs.current_zone
		if "wolf" in zone:
			_floor_terrain = T_WOLF_DIRT
			_wall_terrain  = T_WOLF_STONE
		else:
			_floor_terrain = T_CAVE_STONE
			_wall_terrain  = T_CAVE_STONE
		gs.world_node = self
		set_meta("zone_name", gs.current_zone)

	# Initialise derived dimensions from defaults
	ROOM_W = _room_tiles_w * TILE
	ROOM_H = _room_tiles_h * TILE

	# Black background — covers the grey void outside room bounds
	_bg          = ColorRect.new()
	_bg.color    = Color(0, 0, 0, 1)
	_bg.size     = Vector2(4096, 4096)
	_bg.position = Vector2(-2048, -2048)
	_bg.z_index  = -10
	add_child(_bg)

	var tileset = load("res://tilesets/dungeon_tileset.tres")

	_layer_floor = TileMapLayer.new()
	_layer_floor.tile_set = tileset
	_layer_floor.z_index  = -2
	add_child(_layer_floor)


	# Wall collision node — rebuilt each room entry via _rebuild_walls()
	_wall_node = Node2D.new()
	add_child(_wall_node)

	# Room-to-room fade overlay — sits on a CanvasLayer above everything
	var fade_layer = CanvasLayer.new()
	fade_layer.layer = 60
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(_fade_rect)

	var net = get_tree().root.get_node_or_null("Network")
	if net:
		if not net.dungeon_room_enter_received.is_connected(_on_room_enter):
			net.dungeon_room_enter_received.connect(_on_room_enter)
		if not net.dungeon_room_cleared_received.is_connected(_on_room_cleared):
			net.dungeon_room_cleared_received.connect(_on_room_cleared)
		if not net.dungeon_door_vote_received.is_connected(_on_door_vote):
			net.dungeon_door_vote_received.connect(_on_door_vote)

func _clamp_camera() -> void:
	var cam = get_tree().get_first_node_in_group("camera")
	if not cam:
		print("[DW] WARNING: camera group not found!")
		return
	var lx = -(ROOM_W / 2 - TF)
	var rx =   ROOM_W / 2 - TF
	var ty = -(ROOM_H / 2 - TF)
	var by =   ROOM_H / 2 - TF
	cam.limit_left   = lx
	cam.limit_right  = rx
	cam.limit_top    = ty
	cam.limit_bottom = by

# ── Signal handlers ───────────────────────────────────────────

var _debug_clamp_timer: float = 0.0
var _debug_exit_timer: float = 0.0

func _process(delta: float) -> void:
	var lp = get_tree().get_first_node_in_group("local_player")
	if not lp:
		_debug_clamp_timer += delta
		if _debug_clamp_timer > 3.0:
			_debug_clamp_timer = 0.0
			print("[DW] WARNING: local_player group not found! Can't clamp position.")
		return

	var hw = float(ROOM_W / 2 - TF - 8)
	var hh = float(ROOM_H / 2 - TF - 8)
	var before = lp.global_position
	var clamped = Vector2(clamp(before.x, -hw, hw), clamp(before.y, -hh, hh))

	# Log when player is outside bounds
	if before != clamped:
		print("[DW] CLAMP: player pos %s -> %s (bounds ±%s, ±%s)" % [before, clamped, hw, hh])
	lp.global_position = clamped

	# Debug exit door state every 3s
	_debug_exit_timer += delta
	if _debug_exit_timer > 3.0:
		_debug_exit_timer = 0.0
		print("[DW] exit_nodes=%d  player_pos=%s  bounds=±%s,±%s" % [_exit_nodes.size(), lp.global_position, hw, hh])
		for i in range(_exit_nodes.size()):
			var d = _exit_nodes[i]
			if is_instance_valid(d):
				print("[DW]   door[%d] pos=%s room_id=%s near=%s used=%s" % [
					i, d.position,
					d.get_meta("room_id", "?"),
					d.get_meta("near_ref", "?"),
					d.get_meta("used_ref", "?")
				])

	# E-key interaction with exit doors
	if Input.is_action_just_pressed("interact"):
		print("[DW] interact pressed. exit_nodes=%d" % _exit_nodes.size())
		var found_near = false
		for door in _exit_nodes:
			if not is_instance_valid(door):
				print("[DW]   door invalid")
				continue
			var near = door.get_meta("near_ref", false)
			var used = door.get_meta("used_ref", false)
			var rid  = door.get_meta("room_id", -1)
			print("[DW]   door room_id=%d near=%s used=%s pos=%s" % [rid, near, used, door.position])
			if near and not used:
				found_near = true
				door.set_meta("used_ref", true)
				var net = get_tree().root.get_node_or_null("Network")
				if not net or not net.is_network_connected():
					print("[DW]   -> ERROR: no network or not connected!")
					break
				if rid == -1:
					print("[DW]   -> firing request_dungeon_exit")
					net.request_dungeon_exit.rpc_id(1)
				else:
					var reward = door.get_meta("reward_type", -1)
					print("[DW]   -> firing send_room_move to room %d reward=%d" % [rid, reward])
					net.send_room_move.rpc_id(1, rid, reward)
				break
		if not found_near:
			print("[DW]   no near door found")

var _waiting_label: Label = null

func _on_door_vote(_voter_id: int, votes_so_far: int, living_count: int) -> void:
	if votes_so_far >= living_count:
		# All voted — label will disappear on next room enter
		if _waiting_label and is_instance_valid(_waiting_label):
			_waiting_label.queue_free()
			_waiting_label = null
		return
	# Show / update "Waiting for X/Y" label above the door area
	if _waiting_label == null or not is_instance_valid(_waiting_label):
		_waiting_label = Label.new()
		_waiting_label.z_index = 60
		_waiting_label.add_theme_font_size_override("font_size", 14)
		_waiting_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		_waiting_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		_waiting_label.add_theme_constant_override("shadow_offset_x", 1)
		_waiting_label.add_theme_constant_override("shadow_offset_y", 1)
		_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_waiting_label)
		_waiting_label.global_position = Vector2(-120, -int(ROOM_H / 2.0) + 40)
	_waiting_label.text = "Waiting for party... (%d/%d)" % [votes_so_far, living_count]

func _on_room_enter(room_id: int, label: String, room_type: int,
		connections: Array, floor_num: int, tiles_w: int = 28, tiles_h: int = 19, spawn_pos: Vector2 = Vector2.ZERO) -> void:
	print("[DW] >>>ROOM_ENTER room_id=%d label=%s type=%d size=%dx%d" % [
		room_id, label, room_type, tiles_w, tiles_h])
	_current_room = room_id
	# Clear any "waiting for party" label from the previous room
	if _waiting_label and is_instance_valid(_waiting_label):
		_waiting_label.queue_free()
		_waiting_label = null
	for n in _exit_nodes:
		if is_instance_valid(n):
			remove_child(n)
			n.free()
	_exit_nodes.clear()
	_rng.seed = room_id * 1337 + floor_num * 97 + int(Time.get_ticks_msec() * 0.01)

	# Update room dimensions
	_room_tiles_w = tiles_w
	_room_tiles_h = tiles_h
	ROOM_W        = _room_tiles_w * TILE
	ROOM_H        = _room_tiles_h * TILE

	# Reposition tilemaps
	var origin = Vector2(-ROOM_W / 2.0, -ROOM_H / 2.0)
	_layer_floor.position = origin

	# Rebuild collision walls
	for child in _wall_node.get_children():
		child.free()
	_build_collision_walls()

	# Free previous entrance arch
	if _entrance_node and is_instance_valid(_entrance_node):
		remove_child(_entrance_node)
		_entrance_node.free()
	_entrance_node = null

	# Draw room (tiles + overlay)
	_draw_room(room_id, room_type)

	# Draw entrance arch at bottom of room
	_draw_entrance_arch()

	# Clamp camera before entrance walk
	_clamp_camera()

	# Play entrance: fade in from black, walk player up from bottom
	var lp = get_tree().get_first_node_in_group("local_player")
	_do_room_entrance(lp)

func _draw_entrance_arch() -> void:
	_entrance_node = Node2D.new()
	_entrance_node.z_index = 3
	add_child(_entrance_node)

	var arch_w = float(TILE * 3)
	var arch_h = float(TILE * 2)
	var ax     = -arch_w / 2.0
	var ay     = float(ROOM_H) / 2.0 - float(TF) - arch_h + 4.0

	# Dark doorway recess
	var recess = ColorRect.new()
	recess.size     = Vector2(arch_w, arch_h)
	recess.position = Vector2(ax, ay)
	recess.color    = Color(0.04, 0.03, 0.05, 0.95)
	_entrance_node.add_child(recess)

	# Side pillars
	for side in [-1, 1]:
		var pillar = ColorRect.new()
		pillar.size     = Vector2(TILE * 0.5, arch_h + TILE * 0.5)
		pillar.position = Vector2(ax + int(side == 1) * (arch_w - TILE * 0.5), ay - TILE * 0.25)
		pillar.color    = Color(0.18, 0.14, 0.12)
		_entrance_node.add_child(pillar)

	# Arch header
	var header = ColorRect.new()
	header.size     = Vector2(arch_w + TILE, TILE * 0.5)
	header.position = Vector2(ax - TILE * 0.5, ay - TILE * 0.25)
	header.color    = Color(0.18, 0.14, 0.12)
	_entrance_node.add_child(header)

func _do_room_entrance(lp: Node) -> void:
	# Bottom-centre of walkable floor — just inside the entrance arch
	var entrance_y = float(ROOM_H) / 2.0 - float(TF) - float(TILE) * 1.5
	var entrance_pos = Vector2(0.0, entrance_y)
	var center_pos   = Vector2(0.0, entrance_y - float(TILE) * 3.0)

	if lp:
		lp.set_physics_process(false)
		lp.global_position = entrance_pos
		if lp.get("grid_pos")   != null: lp.grid_pos   = entrance_pos
		if lp.get("target_pos") != null: lp.target_pos = entrance_pos
		if lp.get("facing_dir") != null: lp.facing_dir = "up"
		if lp.has_method("_play_idle"):  lp._play_idle()

	# Fade in from black
	if _fade_rect:
		_fade_rect.color = Color(0, 0, 0, 1)
	var tween = create_tween()
	if _fade_rect:
		tween.tween_property(_fade_rect, "color", Color(0, 0, 0, 0), 0.35)

	# After fade, walk player to centre
	tween.tween_callback(func():
		if not lp or not is_instance_valid(lp):
			return
		var walk_tween = create_tween()
		walk_tween.tween_property(lp, "global_position", center_pos, 0.55)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		walk_tween.tween_callback(func():
			if not lp or not is_instance_valid(lp):
				return
			if lp.get("grid_pos")   != null: lp.grid_pos   = center_pos
			if lp.get("target_pos") != null: lp.target_pos = center_pos
			lp.set_physics_process(true)
		)
	)

func _on_room_cleared(room_id: int, connections: Array, door_rewards: Dictionary = {}) -> void:
	print("[DW] >>>ROOM_CLEARED room_id=%d current=%d connections=%s" % [
		room_id, _current_room, str(connections)])
	if room_id != _current_room:
		print("[DW]   IGNORED (not current room)")
		return
	_show_exits(connections, door_rewards)

# ── Room drawing ──────────────────────────────────────────────

func _draw_room(_room_id: int, room_type: int) -> void:
	# Free previous overlay/exit decorations
	if _room_node and is_instance_valid(_room_node):
		remove_child(_room_node)
		_room_node.free()
	_room_node = Node2D.new()
	_room_node.z_index = 2   # above wall layer (z=0) so overlays never clip behind tiles
	add_child(_room_node)

	_layer_floor.clear()

	_paint_floor()
	_draw_room_type_overlay(room_type)

func _paint_floor() -> void:
	var cells: Array[Vector2i] = []
	for ty in range(_room_tiles_h):
		for tx in range(_room_tiles_w):
			cells.append(Vector2i(tx, ty))
	_layer_floor.set_cells_terrain_connect(cells, TERRAIN_SET, _floor_terrain)

# ── Collision walls — built ONCE, never freed ─────────────────

func _build_collision_walls() -> void:
	var W   = float(ROOM_W)
	var H   = float(ROOM_H)
	var TF  = float(TILE * WALL_TILES)  # 64px — floor starts here
	var PAD = 2048.0                    # extends far into void
	# Inner edge of each wall aligns exactly with the walkable floor boundary
	_cwall(Vector2(-W/2 - PAD, -H/2 - PAD), Vector2(W + PAD*2, PAD + TF))  # top
	_cwall(Vector2(-W/2 - PAD,  H/2 - TF),  Vector2(W + PAD*2, PAD + TF))  # bottom
	_cwall(Vector2(-W/2 - PAD, -H/2 - PAD), Vector2(PAD + TF,  H + PAD*2)) # left
	_cwall(Vector2( W/2 - TF,  -H/2 - PAD), Vector2(PAD + TF,  H + PAD*2)) # right

# ── Room type overlays ────────────────────────────────────────

func _draw_room_type_overlay(room_type: int) -> void:
	match room_type:
		RT_REST:      _overlay_rest()
		RT_SHOP:      _overlay_shop()
		RT_BOSS:      _overlay_boss()
		RT_MINIBOSS:  _overlay_miniboss()
		RT_TREASURE:  _overlay_treasure()

func _overlay_rest() -> void:
	_cr(_room_node, Vector2(-8,   4), Vector2(16,  8), Color(0.35, 0.20, 0.07), 2)
	_cr(_room_node, Vector2(-5,  -8), Vector2(10, 14), Color(0.90, 0.42, 0.04), 3)
	_cr(_room_node, Vector2(-3, -18), Vector2( 6, 12), Color(1.00, 0.68, 0.08), 4)
	_cr(_room_node, Vector2(-1, -26), Vector2( 2,  8), Color(1.00, 0.94, 0.45), 4)
	_cr(_room_node, Vector2(-50,-35), Vector2(100,60), Color(0.85, 0.38, 0.03, 0.10), 2)

func _overlay_shop() -> void:
	_cr(_room_node, Vector2(-52,-22), Vector2(104,  8), Color(0.52, 0.32, 0.10), 2)
	_cr(_room_node, Vector2(-50,-14), Vector2(100, 32), Color(0.36, 0.22, 0.08), 2)
	_cr(_room_node, Vector2(-58,-52), Vector2(116,  5), Color(0.58, 0.38, 0.13), 3)
	_cr(_room_node, Vector2(-16,-44), Vector2( 32, 20), Color(0.80, 0.76, 0.50), 2)
	_cr(_room_node, Vector2(-12,-42), Vector2( 24, 16), Color(0.96, 0.92, 0.66), 3)

func _overlay_boss() -> void:
	var ay = ROOM_H/2 - TF - 80.0   # bottom of room, away from exit doors
	_cr(_room_node, Vector2(-38, ay),      Vector2(76, 30), Color(0.16, 0.12, 0.10), 2)
	_cr(_room_node, Vector2(-30, ay - 24), Vector2(60, 24), Color(0.20, 0.14, 0.12), 3)
	_cr(_room_node, Vector2(-16, ay - 48), Vector2(32, 24), Color(0.82, 0.78, 0.72), 4)
	_cr(_room_node, Vector2(-18, ay - 28), Vector2(12,  8), Color(0.08, 0.06, 0.06), 5)
	_cr(_room_node, Vector2(  6, ay - 28), Vector2(12,  8), Color(0.08, 0.06, 0.06), 5)
	_cr(_room_node, Vector2(-12, ay - 18), Vector2(24,  4), Color(0.08, 0.06, 0.06), 5)
	_cr(_room_node, Vector2(-80, ay - 64), Vector2(160,96), Color(0.55, 0.04, 0.04, 0.13), 1)

func _overlay_miniboss() -> void:
	for side in [-1, 1]:
		var px = side * 200.0
		_cr(_room_node, Vector2(px - 6, -44), Vector2(12, 64), Color(0.24, 0.16, 0.10), 2)
		_cr(_room_node, Vector2(px - 9, -48), Vector2(18, 10), Color(0.88, 0.42, 0.04), 3)
		_cr(_room_node, Vector2(px - 6, -58), Vector2(12, 12), Color(1.00, 0.68, 0.08), 4)

func _overlay_treasure() -> void:
	# Treasure chest: gold body, darker lid, latch highlight
	var cy = 20.0   # center slightly below room center
	_cr(_room_node, Vector2(-28, cy),        Vector2(56, 36), Color(0.65, 0.45, 0.08), 2)  # body
	_cr(_room_node, Vector2(-28, cy - 18),   Vector2(56, 20), Color(0.80, 0.58, 0.12), 3)  # lid
	_cr(_room_node, Vector2(-28, cy - 20),   Vector2(56,  4), Color(0.95, 0.75, 0.20), 3)  # lid rim
	_cr(_room_node, Vector2( -8, cy + 8),    Vector2(16, 12), Color(0.85, 0.65, 0.10), 3)  # latch bg
	_cr(_room_node, Vector2( -5, cy + 10),   Vector2(10,  8), Color(1.00, 0.90, 0.35), 4)  # latch gold
	# Glow behind chest
	_cr(_room_node, Vector2(-48, cy - 30),   Vector2(96, 80), Color(0.90, 0.75, 0.10, 0.12), 1)

# ── Exit doors ────────────────────────────────────────────────


# ── Door sprite helper ────────────────────────────────────────

const RoomDB = preload("res://scripts/dungeon_room_db.gd")

# ── Door system ───────────────────────────────────────────────

func _show_exits(connections: Array, door_rewards: Dictionary = {}) -> void:
	print("[DW] _show_exits connections=%s door_rewards=%s" % [str(connections), str(door_rewards)])
	for n in _exit_nodes:
		if is_instance_valid(n):
			remove_child(n)
			n.free()
	_exit_nodes.clear()

	# New format: door_rewards = { "0": {room_id, reward}, "1": {room_id, reward}, ... }
	# Old format fallback: connections array with no rewards
	if not door_rewards.is_empty() and door_rewards.has("0"):
		# New multi-door format — one door per reward choice
		var total = door_rewards.size()
		var idx = 0
		for key in door_rewards:
			var entry   = door_rewards[key]
			var rid     = entry.get("room_id", -1) if entry is Dictionary else -1
			var reward  = entry.get("reward",  -1) if entry is Dictionary else -1
			var pos     = _exit_position(idx, total)
			var door: Area2D
			if rid == -1:
				door = _make_dungeon_exit_door(pos)
			elif rid == -2:
				door = _make_next_floor_door(pos)
			else:
				door = _make_exit_door(pos, rid, reward)
			add_child(door)
			_exit_nodes.append(door)
			idx += 1
	else:
		# Fallback: plain connections list (boss door, treasure door, etc.)
		var total = connections.size()
		for i in range(total):
			var pos    = _exit_position(i, total)
			var rid    = connections[i]
			var reward = door_rewards.get(rid, -1)
			var door: Area2D
			if rid == -1:
				door = _make_dungeon_exit_door(pos)
			elif rid == -2:
				door = _make_next_floor_door(pos)
			else:
				door = _make_exit_door(pos, rid, reward)
			add_child(door)
			_exit_nodes.append(door)

func _make_door(pos: Vector2, room_id: int, reward_type: int = -1) -> Area2D:
	var area = Area2D.new()
	area.collision_layer = 0
	area.collision_mask  = 1
	area.position        = pos

	# Interaction trigger shape
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size = Vector2(56, 72)
	shape.shape = rect
	area.add_child(shape)

	# Solid blocker — prevents walking through the door
	var blocker       = StaticBody2D.new()
	blocker.collision_layer = 1
	blocker.collision_mask  = 0
	var bshape        = CollisionShape2D.new()
	var brect         = RectangleShape2D.new()
	brect.size        = Vector2(56, 16)
	bshape.shape      = brect
	blocker.add_child(bshape)
	area.add_child(blocker)

	# Door sprite
	var tex_path = "res://sprites/dungeon/door_exit.png"
	var door_tint = Color(1, 1, 1, 1)
	if reward_type == RoomDB.RewardType.BOON:
		door_tint = Color(0.8, 0.6, 1.0)   # purple tint
	elif reward_type == RoomDB.RewardType.UPGRADE:
		door_tint = Color(0.5, 0.7, 1.0)   # blue tint
	elif reward_type == RoomDB.RewardType.REST:
		door_tint = Color(0.5, 1.0, 0.6)   # green tint
	elif reward_type == RoomDB.RewardType.SHOP:
		door_tint = Color(1.0, 0.95, 0.3)  # gold tint
	elif reward_type == RoomDB.RewardType.GOLD:
		door_tint = Color(1.0, 0.8, 0.1)   # amber tint
	elif reward_type == RoomDB.RewardType.RESOURCES:
		door_tint = Color(0.6, 0.9, 0.4)   # olive tint

	if ResourceLoader.exists(tex_path):
		var tex = ResourceLoader.load(tex_path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
		if tex:
			var spr      = Sprite2D.new()
			spr.texture  = tex
			spr.position = Vector2(0, -8)
			spr.scale    = Vector2(1.0, 1.0)
			spr.modulate = door_tint
			spr.z_index  = 4
			area.add_child(spr)

	# Reward symbol drawn above door
	if reward_type >= 0:
		_draw_reward_symbol(area, reward_type)

	# Proximity prompt — panel with room type name
	var reward_label = RoomDB.REWARD_LABELS.get(reward_type, "") if reward_type >= 0 else ""
	var prompt_text  = "[E]  %s" % reward_label if reward_label != "" else "[E]  Enter"
	var prompt_color = RoomDB.REWARD_COLORS.get(reward_type, Color(1.0, 0.88, 0.30))

	var bg = Panel.new()
	bg.position = Vector2(-70, -110)
	bg.size     = Vector2(140, 30)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.04, 0.03, 0.07, 0.90)
	bg_style.set_corner_radius_all(5)
	bg_style.set_border_width_all(1)
	bg_style.border_color = Color(prompt_color.r * 0.6, prompt_color.g * 0.6, prompt_color.b * 0.8)
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.visible = false
	area.add_child(bg)

	var lbl = Label.new()
	lbl.text     = prompt_text
	lbl.position = Vector2(-70, -110)
	lbl.size     = Vector2(140, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", prompt_color)
	lbl.visible = false
	area.add_child(lbl)

	area.set_meta("room_id",     room_id)
	area.set_meta("reward_type", reward_type)
	area.set_meta("near_ref",    false)
	area.set_meta("used_ref",    false)
	area.set_meta("prompt_lbl",  lbl)
	area.set_meta("prompt_bg",   bg)

	area.body_entered.connect(func(body):
		if body.is_in_group("local_player"):
			area.set_meta("near_ref", true)
			lbl.visible = true
			bg.visible  = true
	)
	area.body_exited.connect(func(body):
		if body.is_in_group("local_player"):
			area.set_meta("near_ref", false)
			lbl.visible = false
			bg.visible  = false
	)
	return area

func _draw_reward_symbol(parent: Node2D, reward_type: int) -> void:
	var c = RoomDB.REWARD_COLORS.get(reward_type, Color(1,1,1))
	var sy = -82.0  # y above door top

	match reward_type:
		RoomDB.RewardType.BOON:
			# Star shape
			_cr(parent, Vector2(-8, sy - 8),  Vector2(16, 24), c, 5)
			_cr(parent, Vector2(-14, sy - 2), Vector2(28, 12), c, 5)
		RoomDB.RewardType.UPGRADE:
			# Up arrow
			_cr(parent, Vector2(-5, sy - 10), Vector2(10, 20), c, 5)
			_cr(parent, Vector2(-12, sy - 4), Vector2(24,  8), c, 5)
			_cr(parent, Vector2(-8,  sy - 14),Vector2(16,  8), c, 5)
		RoomDB.RewardType.REST:
			# Cross / plus
			_cr(parent, Vector2(-4, sy - 12), Vector2( 8, 24), c, 5)
			_cr(parent, Vector2(-12, sy - 4), Vector2(24,  8), c, 5)
		RoomDB.RewardType.SHOP:
			# Bag / circle
			_cr(parent, Vector2(-10, sy - 10), Vector2(20, 20), c, 5)
			_cr(parent, Vector2(-6,  sy - 14), Vector2(12,  6), Color(c.r*0.6, c.g*0.6, c.b*0.3), 6)
		RoomDB.RewardType.GOLD, RoomDB.RewardType.RESOURCES:
			# Diamond
			_cr(parent, Vector2(-8,  sy - 12), Vector2(16, 24), c, 5)
			_cr(parent, Vector2(-12, sy - 6),  Vector2(24, 12), c, 5)

func _make_exit_door(pos: Vector2, room_id: int, reward_type: int = -1) -> Area2D:
	return _make_door(pos, room_id, reward_type)

func _make_next_floor_door(pos: Vector2) -> Area2D:
	var area = _make_door(pos, -2, -1)
	# Override prompt
	var lbl = area.get_meta("prompt_lbl")
	lbl.text = "[E] Next Floor"
	lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 1.0))
	return area

func _make_dungeon_exit_door(pos: Vector2) -> Area2D:
	var area = _make_door(pos, -1, -1)
	var lbl  = area.get_meta("prompt_lbl")
	lbl.text = "[E] Leave Dungeon"
	lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	# Reddish tint on sprite
	for child in area.get_children():
		if child is Sprite2D:
			child.modulate = Color(1.0, 0.6, 0.5)
	return area

func _exit_position(index: int, total: int = 1) -> Vector2:
	# Doors spread horizontally across the top portion of the room
	var spacing = 130.0
	var offset  = (index - (total - 1) / 2.0) * spacing
	return Vector2(offset, -float(ROOM_H) / 2.0 + float(TF) + 96.0)

func _cr(parent: Node, pos: Vector2, size: Vector2, color: Color, z: int = 0) -> void:
	var c = ColorRect.new()
	c.position = pos; c.size = size; c.color = color; c.z_index = z
	parent.add_child(c)

func _cwall(pos: Vector2, size: Vector2) -> void:
	var body      = StaticBody2D.new()
	body.position = pos + size / 2.0
	var shape     = CollisionShape2D.new()
	var rect      = RectangleShape2D.new()
	rect.size     = size
	shape.shape   = rect
	body.add_child(shape)
	_wall_node.add_child(body)
