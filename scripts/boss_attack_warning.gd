extends Node2D

# ============================================================
# BOSS ATTACK WARNING (client-side)
# Spawned in world space at the attack origin.
# Slam:   pulsing circle around boss
# Charge: rectangle rotated toward charge direction
# ============================================================

var _type:        String  = "slam"
var _size:        Vector2 = Vector2.ZERO
var _windup_time: float   = 1.2
var _elapsed:     float   = 0.0
var _fired:       bool    = false

var _zone_fill:   ColorRect = null
var _border_rects: Array   = []

func setup(type: String, origin: Vector2, size: Vector2, dir: Vector2, windup_time: float) -> void:
	_type        = type
	_size        = size
	_windup_time = windup_time
	global_position = origin

	if type == "charge" and dir != Vector2.ZERO:
		# Rotate node to face charge direction
		rotation = dir.angle() - PI / 2.0

	_build_visual()

func _build_visual() -> void:
	if _type == "slam":
		_build_slam_visual()
	elif _type == "charge":
		_build_charge_visual()

func _build_slam_visual() -> void:
	var r = _size.x

	# Fill — 16-sided polygon approximation using ColorRects as a circle
	# Use a square inscribed in circle as fill, supplemented by rotated copy
	_zone_fill          = ColorRect.new()
	_zone_fill.color    = Color(1.0, 0.1, 0.1, 0.18)
	_zone_fill.size     = Vector2(r * 2, r * 2)
	_zone_fill.position = Vector2(-r, -r)
	_zone_fill.z_index  = 8
	add_child(_zone_fill)

	# Border — 4 thin rects forming a cross outline effect
	for i in range(4):
		var br     = ColorRect.new()
		br.color   = Color(1.0, 0.15, 0.15, 0.8)
		br.z_index = 9
		_border_rects.append(br)
		add_child(br)

	# Top/bottom bars
	_border_rects[0].size     = Vector2(r * 2, 2)
	_border_rects[0].position = Vector2(-r, -r)
	_border_rects[1].size     = Vector2(r * 2, 2)
	_border_rects[1].position = Vector2(-r, r - 2)
	# Left/right bars
	_border_rects[2].size     = Vector2(2, r * 2)
	_border_rects[2].position = Vector2(-r, -r)
	_border_rects[3].size     = Vector2(2, r * 2)
	_border_rects[3].position = Vector2(r - 2, -r)

func _build_charge_visual() -> void:
	var w = _size.x
	var h = _size.y

	# Fill — extends forward from origin (node is already rotated)
	_zone_fill          = ColorRect.new()
	_zone_fill.color    = Color(1.0, 0.1, 0.1, 0.18)
	_zone_fill.size     = Vector2(w, h)
	_zone_fill.position = Vector2(-w / 2.0, 0)
	_zone_fill.z_index  = 8
	add_child(_zone_fill)

	# Border
	for i in range(4):
		var br     = ColorRect.new()
		br.color   = Color(1.0, 0.2, 0.2, 0.85)
		br.z_index = 9
		_border_rects.append(br)
		add_child(br)

	_border_rects[0].size     = Vector2(w, 2)
	_border_rects[0].position = Vector2(-w / 2.0, 0)
	_border_rects[1].size     = Vector2(w, 2)
	_border_rects[1].position = Vector2(-w / 2.0, h - 2)
	_border_rects[2].size     = Vector2(2, h)
	_border_rects[2].position = Vector2(-w / 2.0, 0)
	_border_rects[3].size     = Vector2(2, h)
	_border_rects[3].position = Vector2(w / 2.0 - 2, 0)

func _process(delta: float) -> void:
	if _fired:
		return
	_elapsed += delta
	var t     = clampf(_elapsed / _windup_time, 0.0, 1.0)
	var pulse = 0.5 + 0.5 * sin(_elapsed * TAU * 2.5)

	# Opacity ramps up and pulses
	if _zone_fill:
		_zone_fill.color.a = lerp(0.10, 0.30, t) * (0.7 + 0.3 * pulse)
	for br in _border_rects:
		br.color.a = lerp(0.45, 1.0, t) * (0.8 + 0.2 * pulse)

	# Gentle scale pulse on the whole node
	var sc = 1.0 + 0.03 * sin(_elapsed * TAU * 2.5)
	scale  = Vector2.ONE * sc

	if _elapsed >= _windup_time:
		_on_fire()

func _on_fire() -> void:
	_fired = true
	if _zone_fill:
		_zone_fill.color = Color(1.0, 1.0, 1.0, 0.9)
	for br in _border_rects:
		br.color = Color(1.0, 1.0, 1.0, 1.0)
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_callback(queue_free)
