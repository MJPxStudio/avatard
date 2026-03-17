extends Node2D

# ============================================================
# TRAP VISUAL BASE — client-side visual for all trap types.
# Spawned by gs.gd on trap_spawned signal.
# Traps are semi-transparent on the ground — visible to caster
# (and all clients for now; stealth can be added later).
#
# To add a new trap type, add a case to _draw_trap().
# ============================================================

var trap_id:        String  = ""
var caster_peer_id: int     = 0
var trap_type:      String  = "base"

var _triggered: bool  = false
var _pulse_t:   float = 0.0
var _canvas:    Node2D = null

func _ready() -> void:
	z_index = 3
	_canvas = Node2D.new()
	add_child(_canvas)
	_canvas.draw.connect(_draw_trap)

func _draw_trap() -> void:
	match trap_type:
		"insect_trap":
			# Small dark-green circle with bug-leg marks
			var r = 10.0 + sin(_pulse_t * 2.5) * 1.5
			_canvas.draw_circle(Vector2.ZERO, r + 3.0, Color(0.2, 0.4, 0.05, 0.15))  # glow
			_canvas.draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(0.3, 0.55, 0.05, 0.6), 1.5)
			# Four small tick marks like bug legs
			for i in range(4):
				var angle = i * (TAU / 4.0) + _pulse_t * 0.3
				var inner = Vector2(r * 0.6, 0).rotated(angle)
				var outer = Vector2(r * 1.0, 0).rotated(angle)
				_canvas.draw_line(inner, outer, Color(0.3, 0.55, 0.05, 0.5), 1.0)
		_:
			# Generic fallback — faint yellow ring
			_canvas.draw_arc(Vector2.ZERO, 10.0, 0, TAU, 16, Color(0.9, 0.8, 0.1, 0.4), 1.0)

func _process(delta: float) -> void:
	if _triggered:
		return
	_pulse_t += delta
	_canvas.queue_redraw()

func play_trigger_effect() -> void:
	_triggered = true
	# Burst outward and fade
	var tween = get_tree().create_tween()
	tween.tween_property(_canvas, "scale", Vector2(2.5, 2.5), 0.15)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)

func play_expire_effect() -> void:
	_triggered = true
	var tween = get_tree().create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)
