extends Node2D

# ============================================================
# HOKAGE BUILDING INTERIOR
# Contains the Hokage NPC who gives missions.
# ============================================================

const W = 400
const H = 300

func _ready() -> void:
	_build()
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.world_node = self

func _build() -> void:
	# Floor
	var floor = ColorRect.new()
	floor.color    = Color("d4a574")
	floor.size     = Vector2(W, H)
	floor.position = Vector2(-W / 2.0, -H / 2.0)
	floor.z_index  = -1
	add_child(floor)

	# Walls
	_wall(Vector2(0, -H/2.0 - 16), Vector2(W + 32, 32))
	_wall(Vector2(0,  H/2.0 + 16), Vector2(W + 32, 32))
	_wall(Vector2(-W/2.0 - 16, 0), Vector2(32, H))
	_wall(Vector2( W/2.0 + 16, 0), Vector2(32, H))

	# Hokage desk
	var desk = ColorRect.new()
	desk.color    = Color("8b6914")
	desk.size     = Vector2(80, 40)
	desk.position = Vector2(-40, -H/2.0 + 60)
	desk.z_index  = 1
	add_child(desk)

	# Hokage NPC
	var npc_script = load("res://scripts/npc.gd")
	if npc_script:
		var npc          = Node2D.new()
		npc.set_script(npc_script)
		npc.position     = Vector2(0, -H/2.0 + 24)
		npc.z_index      = 2
		npc.set("npc_name", "Hokage")
		npc.set("dialogue", [
			"The village is at peace for now.\nBut there is always more work to be done.",
		])
		add_child(npc)
	# Visual placeholder until art assets arrive
	var npc_vis      = ColorRect.new()
	npc_vis.color    = Color("e74c3c")
	npc_vis.size     = Vector2(20, 28)
	npc_vis.position = Vector2(-10, -H/2.0 + 20)
	npc_vis.z_index  = 1
	add_child(npc_vis)

	# Exit door back to village
	var door = Area2D.new()
	door.set_script(load("res://scripts/zone_door.gd"))
	door.position          = Vector2(0, H/2.0 - 20)
	door.collision_mask    = 1
	door.destination_scene = "res://scenes/village.tscn"
	door.destination_zone  = "village"
	door.spawn_position    = Vector2(0, -460)
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size  = Vector2(32, 20)
	shape.shape = rect
	door.add_child(shape)
	add_child(door)

	var exit_vis = ColorRect.new()
	exit_vis.color    = Color("1a0a00")
	exit_vis.size     = Vector2(32, 20)
	exit_vis.position = Vector2(-16, H/2.0 - 30)
	exit_vis.z_index  = 2
	add_child(exit_vis)

func _wall(center: Vector2, size: Vector2) -> void:
	var body  = StaticBody2D.new()
	body.position = center
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size  = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
