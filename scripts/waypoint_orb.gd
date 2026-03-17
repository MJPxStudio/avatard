extends Node2D

# ============================================================
# WAYPOINT ORB
# Glowing orb that disappears when the player touches it.
# ============================================================

signal touched()

var _area:   Area2D    = null
var _visual: ColorRect = null
var _pulse:  float     = 0.0

func _ready() -> void:
	_build()

func _build() -> void:
	# Glow visual
	_visual          = ColorRect.new()
	_visual.color    = Color(0.2, 0.8, 1.0, 0.85)
	_visual.size     = Vector2(16, 16)
	_visual.position = Vector2(-8, -8)
	add_child(_visual)

	# Outer ring
	var ring      = ColorRect.new()
	ring.color    = Color(0.5, 1.0, 1.0, 0.3)
	ring.size     = Vector2(24, 24)
	ring.position = Vector2(-12, -12)
	ring.z_index  = -1
	add_child(ring)

	# Detection area
	_area                 = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask  = 1
	var shape             = CollisionShape2D.new()
	var circle            = CircleShape2D.new()
	circle.radius         = 14
	shape.shape           = circle
	_area.add_child(shape)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)

func _process(delta: float) -> void:
	_pulse += delta * 3.0
	var brightness = 0.7 + sin(_pulse) * 0.3
	if _visual:
		_visual.color = Color(0.2 * brightness, 0.8 * brightness, 1.0 * brightness, 0.85)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("local_player"):
		touched.emit()
