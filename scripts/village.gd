extends Node2D

# ============================================================
# LEAF VILLAGE — Hub zone
# ============================================================

const ZONE_NAME = "village"

func _ready() -> void:
	set_meta("zone_name", "village")
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.world_node = self
	_build_village()

func _build_village() -> void:
	# Ground
	_make_rect(Vector2.ZERO, Vector2(2000, 1400), Color("4a7c40"), -1)

	# Paths (lighter ground)
	_make_rect(Vector2(0, 0), Vector2(80, 1400), Color("c8a96e"), -1)        # vertical center path
	_make_rect(Vector2(0, 0), Vector2(2000, 80), Color("c8a96e"), -1)        # horizontal center path

	# --- HOKAGE BUILDING (top center) ---
	_make_building(Vector2(0, -550), Vector2(220, 160), Color("e8d5a3"), "Hokage Building", "res://scenes/hokage_interior.tscn")

	# --- MARKET (center) ---
	_make_building(Vector2(0, 0), Vector2(180, 120), Color("e8a87c"), "Market", "res://scenes/market_interior.tscn")

	# --- TRAINING AREA (right) ---
	_make_rect(Vector2(500, 100), Vector2(300, 250), Color("6a9e50"), 0)     # training ground
	_make_rect(Vector2(500, 100), Vector2(300, 250), Color("00000000"), 0, true)  # collision border
	_make_zone_door(Vector2(500, 200), "res://scenes/training_interior.tscn", "Training Area")

	# --- HOMES ---
	_make_building(Vector2(-400, -300), Vector2(100, 80), Color("d4956a"), "Home", "res://scenes/home_interior.tscn")
	_make_building(Vector2(300, -300),  Vector2(100, 80), Color("d4956a"), "Home", "res://scenes/home_interior.tscn")
	_make_building(Vector2(-500, 150),  Vector2(100, 80), Color("d4956a"), "Home", "res://scenes/home_interior.tscn")
	_make_building(Vector2(-400, 300),  Vector2(100, 80), Color("d4956a"), "Home", "res://scenes/home_interior.tscn")
	_make_building(Vector2(350, 300),   Vector2(100, 80), Color("d4956a"), "Home", "res://scenes/home_interior.tscn")

	# --- GUARD NPC (near village gate, gives first quest) ---
	_make_npc(Vector2(-100, 530), "Guard", [
		"Welcome to the village, traveler.",
		"Stay safe out there.",
	])

	# --- VILLAGE GATE (bottom center) ---
	_make_rect(Vector2(0, 600), Vector2(200, 40), Color("8b6914"), 0)        # gate bar
	_make_rect(Vector2(-100, 570), Vector2(30, 80), Color("8b6914"), 0)      # left post
	_make_rect(Vector2(100, 570),  Vector2(30, 80), Color("8b6914"), 0)      # right post
	_make_zone_door(Vector2(0, 620), "res://scenes/open_world.tscn", "Open World", Vector2(0, 1800))

	# --- DUNGEON PORTAL (east edge) ---
	var portal = load("res://scripts/dungeon_portal.gd").new()
	portal.position = Vector2(800, 0)
	add_child(portal)

	# --- BOUNDARY WALLS ---
	_make_wall(Vector2(0, -710),   Vector2(2000, 40))   # top
	_make_wall(Vector2(0, 710),    Vector2(2000, 40))   # bottom
	_make_wall(Vector2(-1010, 0),  Vector2(40, 1400))   # left
	_make_wall(Vector2(1010, 0),   Vector2(40, 1400))   # right

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
	# Visual placeholder
	var vis = ColorRect.new()
	vis.color    = Color("e74c3c")
	vis.size     = Vector2(16, 24)
	vis.position = pos - Vector2(8, 12)
	vis.z_index  = 1
	add_child(vis)

func _make_building(center: Vector2, size: Vector2, color: Color, label_text: String, interior_scene: String) -> void:
	# Visual
	_make_rect(center, size, color, 0)
	# Roof line
	_make_rect(center + Vector2(0, -size.y * 0.5 + 8), Vector2(size.x, 16), color.darkened(0.3), 1)
	# Label shown by zone_door proximity prompt — no static label needed
	# Door trigger at bottom center of building
	_make_zone_door(center + Vector2(0, size.y * 0.5 - 8), interior_scene, label_text, Vector2(0, 80))
	# Collision (walls of building, not the door)
	_make_wall(center + Vector2(0, -size.y * 0.5), Vector2(size.x, 12))  # top wall
	_make_wall(center + Vector2(-size.x * 0.5, 0), Vector2(12, size.y))  # left wall
	_make_wall(center + Vector2(size.x * 0.5, 0),  Vector2(12, size.y))  # right wall

func _make_zone_door(pos: Vector2, target_scene: String, label: String, spawn: Vector2 = Vector2.ZERO) -> void:
	var door_script = load("res://scripts/zone_door.gd")
	if door_script == null:
		push_error("zone_door.gd not found")
		return
	var d = Area2D.new()
	d.set_script(door_script)
	d.position            = pos
	d.collision_mask      = 1
	d.destination_scene   = target_scene
	d.destination_zone    = label
	d.spawn_position      = spawn
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size = Vector2(40, 20)
	shape.shape = rect
	d.add_child(shape)
	add_child(d)

func _make_rect(center: Vector2, size: Vector2, color: Color, z: int = 0, _collision_only: bool = false) -> void:
	var cr = ColorRect.new()
	cr.color    = color
	cr.size     = size
	cr.position = center - size * 0.5
	cr.z_index  = z
	add_child(cr)

func _make_wall(center: Vector2, size: Vector2) -> void:
	var body  = StaticBody2D.new()
	body.position = center
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)

func _make_label(text: String, pos: Vector2) -> Label:
	var lbl = Label.new()
	lbl.text     = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color("ffffff"))
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl
