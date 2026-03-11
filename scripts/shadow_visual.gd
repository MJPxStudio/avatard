extends Node2D

# ============================================================
# SHADOW VISUAL — client-side only.
# Draws a continuous dark line from caster to shadow head,
# exactly like the Nara shadow in the anime.
# The tail is anchored to the caster and updates each frame.
# ============================================================

const SHADOW_WIDTH:     float = 2.0
const SHADOW_COLOR:     Color = Color(0.05, 0.02, 0.08, 0.95)
const EDGE_COLOR:       Color = Color(0.15, 0.05, 0.25, 0.6)
const HIT_COLOR:        Color = Color(0.5,  0.1,  0.8,  1.0)

var shadow_id:      String = ""
var caster_peer_id: int    = 0

var _line:          Line2D = null
var _edge:          Line2D = null   # slightly wider, darker edge for depth
var _caster_pos:    Vector2 = Vector2.ZERO
var _head_pos:      Vector2 = Vector2.ZERO
var _dead:          bool    = false

func _ready() -> void:
	z_index = 1   # on the ground, below players

	# Edge line (drawn first, slightly wider)
	_edge             = Line2D.new()
	_edge.width       = SHADOW_WIDTH + 1.5
	_edge.default_color = Color(0.0, 0.0, 0.0, 0.7)
	_edge.joint_mode  = Line2D.LINE_JOINT_ROUND
	_edge.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_edge.end_cap_mode   = Line2D.LINE_CAP_ROUND
	add_child(_edge)

	# Main shadow line
	_line             = Line2D.new()
	_line.width       = SHADOW_WIDTH
	_line.default_color = SHADOW_COLOR
	_line.joint_mode  = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode   = Line2D.LINE_CAP_ROUND
	add_child(_line)

func _process(_delta: float) -> void:
	if _dead:
		return
	# Keep tail anchored to caster's current position
	var caster = _get_caster()
	if caster != null:
		_caster_pos = caster
	_redraw()

func _redraw() -> void:
	_line.clear_points()
	_edge.clear_points()
	# Build a slightly jagged path — two points is enough for straight,
	# but we add the midpoint offset to give it that organic ground-shadow feel
	var mid = _caster_pos.lerp(_head_pos, 0.5)
	# Slight perpendicular wobble at midpoint
	var perp = (_head_pos - _caster_pos).normalized().rotated(PI * 0.5) * 3.0
	_line.add_point(_caster_pos)
	_line.add_point(mid + perp)
	_line.add_point(_head_pos)
	_edge.add_point(_caster_pos)
	_edge.add_point(mid + perp)
	_edge.add_point(_head_pos)

func init_positions(caster_pos: Vector2, head_pos: Vector2) -> void:
	_caster_pos = caster_pos
	_head_pos   = head_pos
	_redraw()

func move_to(new_head: Vector2) -> void:
	_head_pos = new_head
	# _process will redraw each frame

func _get_caster() -> Variant:
	# Try local player first
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return null
	var lp = gs._get_local_player()
	if lp and lp.get("peer_id") == caster_peer_id:
		return lp.global_position
	# Try remote players
	var state = gs.remote_players.get(caster_peer_id, null)
	if state:
		return state.get("position", _caster_pos)
	return null

func play_hit_effect() -> void:
	_dead = true
	# Hold the line as-is — stays black while target is rooted
	# Freed by play_despawn_effect when root expires

func play_despawn_effect() -> void:
	_dead = true
	# Shrink from head toward tail then fade
	var tween = get_tree().create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
