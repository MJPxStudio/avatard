extends Node2D

# ============================================================
# COCOON VISUAL — client-side only.
# A pulsing green-brown blob that travels with the projectile.
# Spawned by gs.gd on shadow_spawn for cocoon_ prefixed IDs.
# ============================================================

var cocoon_id:      String  = ""
var caster_peer_id: int     = 0

var _blob:    Node2D = null
var _pos:     Vector2 = Vector2.ZERO
var _dead:    bool    = false
var _pulse_t: float   = 0.0

const RADIUS:       float = 24.0
const BLOB_COLOR:   Color = Color(0.3, 0.55, 0.05, 0.85)
const PULSE_SPEED:  float = 4.0
const PULSE_SCALE:  float = 0.12   # ±12% size pulse

func _ready() -> void:
	z_index = 4
	_blob = Node2D.new()
	add_child(_blob)
	_blob.draw.connect(_draw_blob)

func _draw_blob() -> void:
	var r = RADIUS * (1.0 + sin(_pulse_t * PULSE_SPEED) * PULSE_SCALE)
	# Outer glow ring
	_blob.draw_circle(Vector2.ZERO, r + 4.0, Color(0.5, 0.75, 0.1, 0.25))
	# Main body
	_blob.draw_circle(Vector2.ZERO, r, BLOB_COLOR)
	# Inner highlight
	_blob.draw_circle(Vector2(-r * 0.25, -r * 0.25), r * 0.35, Color(0.55, 0.8, 0.15, 0.4))

func _process(delta: float) -> void:
	if _dead:
		return
	_pulse_t += delta
	global_position = _pos
	_blob.queue_redraw()

func move_to(new_pos: Vector2) -> void:
	_pos = new_pos

func init_position(start_pos: Vector2) -> void:
	_pos = start_pos
	global_position = start_pos

func play_hit_effect() -> void:
	_dead = true
	# Burst outward then fade
	var tween = get_tree().create_tween()
	tween.tween_property(_blob, "scale", Vector2(2.2, 2.2), 0.15)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)

func play_despawn_effect() -> void:
	_dead = true
	var tween = get_tree().create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)
