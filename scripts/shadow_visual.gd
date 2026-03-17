extends Node2D

# ============================================================
# SHADOW VISUAL — client-side only.
# The shadow HEAD moves independently; the trail is the path
# it has already traveled, left behind on the ground.
# ============================================================

const SHADOW_WIDTH:     float = 2.5
const SHADOW_COLOR:     Color = Color(0.05, 0.02, 0.08, 0.95)
const EDGE_COLOR:       Color = Color(0.0,  0.0,  0.0,  0.7)
const HIT_COLOR:        Color = Color(0.5,  0.1,  0.8,  1.0)
const MIN_POINT_DIST:   float = 4.0   # only add waypoint if head moved this far

var shadow_id:      String  = ""
var caster_peer_id: int     = 0

var _line:          Line2D  = null
var _edge:          Line2D  = null
var _head_dot:      Node2D  = null   # visible head circle
var _caster_pos:    Vector2 = Vector2.ZERO
var _head_pos:      Vector2 = Vector2.ZERO
var _trail:         Array   = []     # Vector2 waypoints laid so far (excluding caster start)
var _dead:          bool    = false
var _frozen:        bool    = false  # true once caught — trail stops growing

func _ready() -> void:
	z_index = 1

	_edge             = Line2D.new()
	_edge.width       = SHADOW_WIDTH + 1.5
	_edge.default_color = EDGE_COLOR
	_edge.joint_mode  = Line2D.LINE_JOINT_ROUND
	_edge.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_edge.end_cap_mode   = Line2D.LINE_CAP_ROUND
	add_child(_edge)

	_line             = Line2D.new()
	_line.width       = SHADOW_WIDTH
	_line.default_color = SHADOW_COLOR
	_line.joint_mode  = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode   = Line2D.LINE_CAP_ROUND
	add_child(_line)

	# Shadow head — small dark ellipse
	_head_dot = Node2D.new()
	_head_dot.z_index = 2
	var head_rect         = ColorRect.new()
	head_rect.size        = Vector2(10, 5)
	head_rect.position    = Vector2(-5, -2.5)
	var mat               = ShaderMaterial.new()
	var shader            = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = dot(uv, uv);
	COLOR = vec4(0.1, 0.0, 0.15, 0.9 * step(d, 1.0));
}
"""
	mat.shader            = shader
	head_rect.material    = mat
	_head_dot.add_child(head_rect)
	add_child(_head_dot)

func _process(_delta: float) -> void:
	if _dead:
		return
	# Keep tail anchored to caster
	if not _frozen:
		var caster = _get_caster()
		if caster != null:
			_caster_pos = caster
	_head_dot.global_position = _head_pos
	_redraw()

func _redraw() -> void:
	_line.clear_points()
	_edge.clear_points()
	# Always start from caster
	_line.add_point(_caster_pos)
	_edge.add_point(_caster_pos)
	for pt in _trail:
		_line.add_point(pt)
		_edge.add_point(pt)
	# Current head at end
	if _trail.is_empty() or _trail[-1].distance_to(_head_pos) > 1.0:
		_line.add_point(_head_pos)
		_edge.add_point(_head_pos)

func init_positions(caster_pos: Vector2, head_pos: Vector2) -> void:
	_caster_pos = caster_pos
	_head_pos   = head_pos
	_trail.clear()
	_redraw()

func move_to(new_head: Vector2) -> void:
	if _frozen:
		return
	# Only record a waypoint if the head has moved far enough
	if _trail.is_empty() or _trail[-1].distance_to(new_head) >= MIN_POINT_DIST:
		_trail.append(new_head)
	_head_pos = new_head

func _get_caster() -> Variant:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return null
	var lp = gs._get_local_player()
	if lp and lp.get("peer_id") == caster_peer_id:
		return lp.global_position
	var state = gs.remote_players.get(caster_peer_id, null)
	if state:
		return state.get("position", _caster_pos)
	return null

func play_hit_effect() -> void:
	_frozen = true
	_head_dot.visible = false
	# Keep black — do not tint

func retract_to(new_head: Vector2, duration: float) -> void:
	# Retract by trimming trail points from the end as the head moves back
	_frozen = false
	var start_pos = _head_pos
	var steps     = 12
	var tween     = get_tree().create_tween()
	for i in range(1, steps + 1):
		var t      = float(i) / float(steps)
		var target = start_pos.lerp(new_head, t)
		tween.tween_callback(func():
			_head_pos = target
			# Trim any trail points farther from caster than current head
			var head_dist = _caster_pos.distance_to(_head_pos)
			var i2 = _trail.size() - 1
			while i2 >= 0 and _caster_pos.distance_to(_trail[i2]) > head_dist:
				_trail.remove_at(i2)
				i2 -= 1
		).set_delay(duration / steps * i)
	tween.tween_callback(func():
		_head_pos = new_head
		_trail.clear()
		_frozen = true
	)

func play_despawn_effect() -> void:
	_dead = true
	_head_dot.visible = false
	var tween = get_tree().create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
