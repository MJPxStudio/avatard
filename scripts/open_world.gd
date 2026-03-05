extends Node2D

# ============================================================
# OPEN WORLD — Leveling zone outside Leaf Village
# Distinct areas: forest, cliffs, river, fields
# ============================================================

const W = 4000
const H = 4000

const C_FIELD  = Color("5a7a3a")
const C_FOREST = Color("2d5a1b")
const C_CLIFF  = Color("7a6a5a")
const C_RIVER  = Color("2471a3")
const C_BRIDGE = Color("8b6914")
const C_ROCK   = Color("5a5a5a")
const C_TREE   = Color("1a3a0a")
const C_GATE   = Color("4a3728")
const C_PATH   = Color("c8a96e")

func _ready() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.world_node = self
	_build()

func _build() -> void:
	var hw = W / 2.0
	var hh = H / 2.0

	# --- BASE GROUND (fields) ---
	_rect(Vector2.ZERO, Vector2(W, H), C_FIELD, -2)

	# --- DIRT PATH (vertical, connects gate to bridge) ---
	_rect(Vector2(0, hh * 0.2), Vector2(80, H * 0.6), C_PATH, -1)

	# --- FOREST (top left) ---
	_rect(Vector2(-hw * 0.6, -hh * 0.55), Vector2(W * 0.45, H * 0.4), C_FOREST, -1)
	_label("Forest", Vector2(-hw * 0.65, -hh * 0.65))
	# Tree obstacles in forest
	for i in range(18):
		var tx = randf_range(-hw * 0.8, -hw * 0.1)
		var ty = randf_range(-hh * 0.75, -hh * 0.2)
		_tree(Vector2(tx, ty))

	# --- CLIFFS (top right) ---
	_rect(Vector2(hw * 0.35, -hh * 0.65), Vector2(W * 0.3, H * 0.5), C_CLIFF, -1)
	_label("Cliffs", Vector2(hw * 0.3, -hh * 0.7))
	# Cliff wall — impassable
	_wall(Vector2(hw * 0.35, -hh * 0.4), Vector2(W * 0.3, H * 0.5))
	# Rock formations
	for i in range(8):
		var rx = randf_range(hw * 0.2, hw * 0.6)
		var ry = randf_range(-hh * 0.7, -hh * 0.1)
		_rock(Vector2(rx, ry))

	# --- RIVER (horizontal band through middle) ---
	_rect(Vector2(0, -hh * 0.05), Vector2(W, H * 0.12), C_RIVER, 0)
	_label("River", Vector2(-60, -hh * 0.12))
	# River collision (two walls, top and bottom edge)
	_wall(Vector2(0, -hh * 0.05 - H * 0.06 - 16), Vector2(W, 32))
	_wall(Vector2(0, -hh * 0.05 + H * 0.06 + 16), Vector2(W, 32))

	# --- BRIDGE (center, crosses river) ---
	_rect(Vector2(0, -hh * 0.05), Vector2(100, H * 0.14), C_BRIDGE, 1)
	_label("Bridge", Vector2(-30, -hh * 0.1))
	# Open the river walls at the bridge
	# (handled by bridge being on top visually — collision gap needed)
	# Left river wall gap
	_wall(Vector2(-W * 0.275, -hh * 0.05 - H * 0.06 - 16), Vector2(W * 0.45, 32))
	_wall(Vector2( W * 0.325, -hh * 0.05 - H * 0.06 - 16), Vector2(W * 0.35, 32))
	_wall(Vector2(-W * 0.275, -hh * 0.05 + H * 0.06 + 16), Vector2(W * 0.45, 32))
	_wall(Vector2( W * 0.325, -hh * 0.05 + H * 0.06 + 16), Vector2(W * 0.35, 32))

	# --- VILLAGE GATE ENTRANCE (bottom center) ---
	_rect(Vector2(0, hh - 60), Vector2(120, 60), C_GATE, 1)
	_label("Village Gate", Vector2(-45, hh - 80))
	# Door back to village
	_zone_door(Vector2(0, hh - 40), "res://scenes/village.tscn", "village", Vector2(0, 560))

	# --- BOUNDARY WALLS ---
	_wall(Vector2(0, -hh - 16), Vector2(W + 32, 32))
	_wall(Vector2(0,  hh + 16), Vector2(W + 32, 32))
	_wall(Vector2(-hw - 16, 0), Vector2(32, H))
	_wall(Vector2( hw + 16, 0), Vector2(32, H))

# ── Helpers ────────────────────────────────────────────────

func _rect(center: Vector2, size: Vector2, color: Color, z: int) -> void:
	var r      = ColorRect.new()
	r.color    = color
	r.size     = size
	r.position = center - size * 0.5
	r.z_index  = z
	add_child(r)

func _tree(center: Vector2) -> void:
	# Visual
	var v      = ColorRect.new()
	v.color    = C_TREE
	v.size     = Vector2(24, 24)
	v.position = center - Vector2(12, 12)
	v.z_index  = 1
	add_child(v)
	# Collision
	_wall(center, Vector2(24, 24))

func _rock(center: Vector2) -> void:
	var v      = ColorRect.new()
	v.color    = C_ROCK
	v.size     = Vector2(32, 20)
	v.position = center - Vector2(16, 10)
	v.z_index  = 1
	add_child(v)
	_wall(center, Vector2(32, 20))

func _wall(center: Vector2, size: Vector2) -> void:
	var body      = StaticBody2D.new()
	body.position = center
	var shape     = CollisionShape2D.new()
	var rect      = RectangleShape2D.new()
	rect.size     = size
	shape.shape   = rect
	body.add_child(shape)
	add_child(body)

func _zone_door(pos: Vector2, dest_scene: String, dest_zone: String, spawn: Vector2) -> void:
	var d = Area2D.new()
	d.set_script(load("res://scripts/zone_door.gd"))
	d.position          = pos
	d.collision_mask    = 1
	d.destination_scene = dest_scene
	d.destination_zone  = dest_zone
	d.spawn_position    = spawn
	var shape   = CollisionShape2D.new()
	var rect    = RectangleShape2D.new()
	rect.size   = Vector2(80, 40)
	shape.shape = rect
	d.add_child(shape)
	add_child(d)

func _label(text: String, pos: Vector2) -> void:
	var lbl = Label.new()
	lbl.text     = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("ffffff"))
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.z_index = 5
	add_child(lbl)
