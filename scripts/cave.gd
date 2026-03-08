extends Node2D

# ============================================================
# CAVE — Instanced dungeon zone
# Dark cave environment used for Cave of Trials and Class Trial.
# ============================================================

const ZONE_NAME = "cave_of_trials"   # overridden per instance by zone_name meta

func _ready() -> void:
	set_meta("zone_name", ZONE_NAME)
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.world_node = self
	_build_cave()

func _build_cave() -> void:
	# ── Floor ──────────────────────────────────────────────
	_make_rect(Vector2.ZERO, Vector2(1200, 800), Color(0.18, 0.14, 0.12), -2)

	# ── Rock texture overlay (darker patches) ──────────────
	for x in range(-500, 500, 80):
		for y in range(-350, 350, 80):
			var jx = x + randi() % 30 - 15
			var jy = y + randi() % 30 - 15
			_make_rect(Vector2(jx, jy), Vector2(40 + randi() % 20, 30 + randi() % 15),
				Color(0.12, 0.10, 0.08, 0.4), -1)

	# ── Walls (border) ─────────────────────────────────────
	var wall_color = Color(0.10, 0.08, 0.07)
	var W = 1200; var H = 800
	_make_wall(Vector2(-W/2, -H/2), Vector2(W,  32),  wall_color)   # top
	_make_wall(Vector2(-W/2,  H/2 - 32), Vector2(W, 32),  wall_color)  # bottom
	_make_wall(Vector2(-W/2, -H/2), Vector2(32, H),  wall_color)   # left
	_make_wall(Vector2(W/2 - 32, -H/2), Vector2(32, H), wall_color)  # right

	# ── Stalactites / rock pillars ─────────────────────────
	var pillar_positions = [
		Vector2(-300, -100), Vector2(-300, 100),
		Vector2( 300, -100), Vector2( 300, 100),
		Vector2(-150,  200), Vector2( 150, -200),
	]
	for pp in pillar_positions:
		_make_wall(pp, Vector2(28, 48), Color(0.12, 0.09, 0.08))

	# ── Entrance marker (bottom center — where players spawn) ──
	_make_rect(Vector2(0, 200), Vector2(40, 6), Color(0.6, 0.5, 0.2, 0.7), 0)

	# ── Exit portal (top of cave — far from spawn) ──────────
	var exit = preload("res://scripts/dungeon_exit.gd").new()
	exit.position = Vector2(0, -160)
	add_child(exit)

func _make_rect(pos: Vector2, size: Vector2, color: Color, z: int = 0) -> void:
	var cr       = ColorRect.new()
	cr.position  = pos - size / 2.0
	cr.size      = size
	cr.color     = color
	cr.z_index   = z
	add_child(cr)

func _make_wall(pos: Vector2, size: Vector2, color: Color) -> void:
	var body     = StaticBody2D.new()
	body.position = pos + size / 2.0
	var shape    = CollisionShape2D.new()
	var rect     = RectangleShape2D.new()
	rect.size    = size
	shape.shape  = rect
	body.add_child(shape)
	var vis      = ColorRect.new()
	vis.position = -size / 2.0
	vis.size     = size
	vis.color    = color
	body.add_child(vis)
	add_child(body)
