extends Node

# ============================================================
# ARENA --- Shared geometry builder used by both client and server
# Call Arena.build(parent_node) to construct walls and obstacles
# ============================================================

const ARENA_W = 1500
const ARENA_H = 1000
const WALL_THICKNESS = 32
const WALL_COLOR = Color("5c3d1e")
const GROUND_COLOR = Color("4a7c40")

func build(parent: Node, include_visuals: bool = true) -> void:
	if include_visuals:
		var ground = ColorRect.new()
		ground.color = GROUND_COLOR
		ground.size = Vector2(ARENA_W, ARENA_H)
		ground.position = Vector2(-ARENA_W / 2.0, -ARENA_H / 2.0)
		ground.z_index = -1
		parent.add_child(ground)

	# Boundary walls
	_make_wall(parent, Vector2(0, -ARENA_H / 2.0 - WALL_THICKNESS / 2.0), Vector2(ARENA_W + WALL_THICKNESS * 2, WALL_THICKNESS), include_visuals)
	_make_wall(parent, Vector2(0,  ARENA_H / 2.0 + WALL_THICKNESS / 2.0), Vector2(ARENA_W + WALL_THICKNESS * 2, WALL_THICKNESS), include_visuals)
	_make_wall(parent, Vector2(-ARENA_W / 2.0 - WALL_THICKNESS / 2.0, 0), Vector2(WALL_THICKNESS, ARENA_H), include_visuals)
	_make_wall(parent, Vector2( ARENA_W / 2.0 + WALL_THICKNESS / 2.0, 0), Vector2(WALL_THICKNESS, ARENA_H), include_visuals)

	# Interior obstacles
	_make_wall(parent, Vector2(-300, -100), Vector2(WALL_THICKNESS, 200), include_visuals)
	_make_wall(parent, Vector2(200, 150),   Vector2(200, WALL_THICKNESS), include_visuals)
	_make_wall(parent, Vector2(0, -250),    Vector2(120, WALL_THICKNESS), include_visuals)

func _make_wall(parent: Node, center: Vector2, size: Vector2, include_visuals: bool) -> void:
	var body = StaticBody2D.new()
	body.position = center
	parent.add_child(body)

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)

	if include_visuals:
		var vis = Polygon2D.new()
		vis.color = WALL_COLOR
		vis.polygon = PackedVector2Array([
			Vector2(-size.x / 2.0, -size.y / 2.0),
			Vector2( size.x / 2.0, -size.y / 2.0),
			Vector2( size.x / 2.0,  size.y / 2.0),
			Vector2(-size.x / 2.0,  size.y / 2.0)
		])
		body.add_child(vis)
