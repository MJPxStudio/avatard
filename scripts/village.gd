extends Node2D

# ============================================================
# LEAF VILLAGE — Hub zone
# Visual map is now built with TileMapLayer nodes in the scene.
# This script only handles: zone doors, NPCs, dungeon portal.
# ============================================================

const ZONE_NAME = "village"

func _ready() -> void:
	set_meta("zone_name", "village")
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.world_node = self
	_build_village()

func _build_village() -> void:
	# --- ZONE DOORS ---
	# Position these to match where your tile-painted doors actually are.
	# Adjust the Vector2 positions as you build the map.
	_make_zone_door(Vector2(0, -550),    "res://scenes/hokage_interior.tscn", "Hokage Building", Vector2(0, 80))
	_make_zone_door(Vector2(0, 0),       "res://scenes/market_interior.tscn",  "Market",          Vector2(0, 80))
	_make_zone_door(Vector2(500, 200),   "res://scenes/training_interior.tscn","Training Area",   Vector2(0, 80))
	_make_zone_door(Vector2(-400, -300), "res://scenes/home_interior.tscn",    "Home",            Vector2(0, 80))
	_make_zone_door(Vector2(300, -300),  "res://scenes/home_interior.tscn",    "Home",            Vector2(0, 80))
	_make_zone_door(Vector2(-500, 150),  "res://scenes/home_interior.tscn",    "Home",            Vector2(0, 80))
	_make_zone_door(Vector2(-400, 300),  "res://scenes/home_interior.tscn",    "Home",            Vector2(0, 80))
	_make_zone_door(Vector2(350, 300),   "res://scenes/home_interior.tscn",    "Home",            Vector2(0, 80))

	# --- OPEN WORLD EXIT ---
	_make_zone_door(Vector2(0, 620), "res://scenes/open_world.tscn", "Open World", Vector2(0, 1800))

	# --- GUARD NPC ---
	_make_npc(Vector2(-100, 530), "Guard", [
		"Welcome to the village, traveler.",
		"Stay safe out there.",
	])

	# --- BARBER NPC ---
	_make_barber(Vector2(200, 530))

	# --- DUNGEON PORTAL ---
	var portal = load("res://scripts/dungeon_portal.gd").new()
	portal.position = Vector2(800, 0)
	add_child(portal)

	# --- BOUNDARY WALLS --- (re-enable once map is painted)
	#_make_wall(Vector2(0, -710),   Vector2(2000, 40))   # top
	#_make_wall(Vector2(0, 710),    Vector2(2000, 40))   # bottom
	#_make_wall(Vector2(-1010, 0),  Vector2(40, 1400))   # left
	#_make_wall(Vector2(1010, 0),   Vector2(40, 1400))   # right

func _make_npc(pos: Vector2, npc_name_val: String, default_dialogue: Array) -> void:
	var npc_script = load("res://scripts/npc.gd")
	if npc_script == null:
		return
	var npc = Node2D.new()
	npc.set_script(npc_script)
	npc.position = pos
	npc.z_index  = 2
	npc.set("npc_name", npc_name_val)
	npc.set("dialogue",  default_dialogue)
	add_child(npc)
	# Visual placeholder — replace with sprite when art is ready
	var vis = ColorRect.new()
	vis.color    = Color("e74c3c")
	vis.size     = Vector2(16, 24)
	vis.position = pos - Vector2(8, 12)
	vis.z_index  = 1
	add_child(vis)

func _make_zone_door(pos: Vector2, target_scene: String, label: String, spawn: Vector2 = Vector2.ZERO) -> void:
	var door_script = load("res://scripts/zone_door.gd")
	if door_script == null:
		push_error("zone_door.gd not found")
		return
	var d = Area2D.new()
	d.set_script(door_script)
	d.position          = pos
	d.collision_mask    = 1
	d.destination_scene = target_scene
	d.destination_zone  = label
	d.spawn_position    = spawn
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size = Vector2(40, 20)
	shape.shape = rect
	d.add_child(shape)
	add_child(d)

func _make_barber(pos: Vector2) -> void:
	var barber_script = load("res://scripts/barber_npc.gd")
	if barber_script == null:
		return
	var barber = Node2D.new()
	barber.set_script(barber_script)
	barber.position = pos
	add_child(barber)

func _make_wall(center: Vector2, size: Vector2) -> void:
	var body  = StaticBody2D.new()
	body.position = center
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
