extends Node2D

# ============================================================
# BUG SWARM VISUAL — client-side animated cone effect.
# Attaches to the caster node and follows them.
# Direction updates each frame from caster's facing.
# ============================================================

const CONE_LENGTH:   float = 160.0
const CONE_HALF_DEG: float = 30.0
const DURATION:      float = 4.0
const FADE_TIME:     float = 0.4
const BUG_COUNT:     int   = 40
const BUG_SPEED_MIN: float = 55.0
const BUG_SPEED_MAX: float = 130.0
const BUG_SIZE_MIN:  float = 1.5
const BUG_SIZE_MAX:  float = 3.0

var direction:    Vector2 = Vector2.RIGHT
var caster_node:  Node    = null
var target_node:  Node    = null   # if set, cone tracks this target each frame

var _t:       float = 0.0
var _fading:  bool  = false
var _bugs:    Array = []

class Bug:
	var angle:  float   # fixed random angle within cone (radians from center)
	var speed:  float   # px/sec along its ray
	var dist:   float   # current distance from origin along its ray
	var size:   float
	var alpha:  float

func _ready() -> void:
	z_index = 10
	position = Vector2.ZERO   # position is always relative to parent (caster)
	for i in BUG_COUNT:
		_spawn_bug(randf() * CONE_LENGTH)   # stagger so cone looks full immediately

func _spawn_bug(start_dist: float = 0.0) -> void:
	var b       = Bug.new()
	b.angle     = deg_to_rad(randf_range(-CONE_HALF_DEG, CONE_HALF_DEG))
	b.speed     = randf_range(BUG_SPEED_MIN, BUG_SPEED_MAX)
	b.dist      = start_dist
	b.size      = randf_range(BUG_SIZE_MIN, BUG_SIZE_MAX)
	b.alpha     = randf_range(0.65, 1.0)
	_bugs.append(b)

func _process(delta: float) -> void:
	_t += delta

	# Follow caster position every frame, direction tracks target if one is set
	if caster_node and is_instance_valid(caster_node):
		global_position = caster_node.global_position
		if target_node and is_instance_valid(target_node):
			var to_target = target_node.global_position - global_position
			if to_target.length() > 1.0:
				direction = to_target.normalized()

	if _t >= DURATION and not _fading:
		_fading = true
		var tw = create_tween()
		tw.tween_property(self, "modulate:a", 0.0, FADE_TIME)
		tw.tween_callback(queue_free)

	# Advance bugs
	for b in _bugs.duplicate():
		b.dist += b.speed * delta
		if b.dist >= CONE_LENGTH:
			_bugs.erase(b)
			if not _fading:
				_spawn_bug(0.0)

	queue_redraw()

func _draw() -> void:
	var half_rad = deg_to_rad(CONE_HALF_DEG)

	# Filled cone polygon — per-vertex colors for gradient
	var steps  = 16
	var points = PackedVector2Array()
	var colors = PackedColorArray()
	points.append(Vector2.ZERO)
	colors.append(Color(0.25, 0.5, 0.04, 0.20))
	for i in range(steps + 1):
		var a = -half_rad + (float(i) / steps) * (half_rad * 2.0)
		points.append(direction.rotated(a) * CONE_LENGTH)
		colors.append(Color(0.15, 0.35, 0.02, 0.0))
	draw_polygon(points, colors)

	# Outline
	var arc_from = atan2(direction.rotated(-half_rad).y, direction.rotated(-half_rad).x)
	var arc_to   = atan2(direction.rotated( half_rad).y, direction.rotated( half_rad).x)
	draw_arc(Vector2.ZERO, CONE_LENGTH, arc_from, arc_to, 24,
		Color(0.3, 0.6, 0.05, 0.28), 1.0)
	draw_line(Vector2.ZERO, direction.rotated(-half_rad) * CONE_LENGTH,
		Color(0.3, 0.6, 0.05, 0.22), 1.0)
	draw_line(Vector2.ZERO, direction.rotated( half_rad) * CONE_LENGTH,
		Color(0.3, 0.6, 0.05, 0.22), 1.0)

	# Draw each bug at its position along its own ray
	for b in _bugs:
		# Bug sits along direction.rotated(b.angle) at distance b.dist
		var bug_pos = direction.rotated(b.angle) * b.dist
		var fade    = 1.0 - (b.dist / CONE_LENGTH)   # full at origin, gone at tip
		var col_out = Color(0.15, 0.3,  0.02, b.alpha * fade * 0.85)
		var col_in  = Color(0.45, 0.72, 0.1,  b.alpha * fade)
		draw_circle(bug_pos, b.size,       col_out)
		draw_circle(bug_pos, b.size * 0.5, col_in)
