extends Camera2D

# Set zoom directly on the Camera2D node in the Inspector (Zoom property).
# No override here — whatever you set in the editor is what you get.

# Screen shake
var shake_duration: float = 0.0
var shake_strength: float = 0.0

# Cinematic lock-on: smoothly offset view toward a target node, then return
var _lock_target:  Node   = null
var _lock_timer:   float  = 0.0
var _lock_active:  bool   = false

func lock_to(target: Node, duration: float) -> void:
	_lock_target = target
	_lock_timer  = duration
	_lock_active = true

func release_lock() -> void:
	_lock_active = false
	_lock_target = null

func _physics_process(delta: float) -> void:
	# ── Camera lock-on (cinematic) ─────────────────────────────────────────
	if _lock_active:
		if is_instance_valid(_lock_target):
			_lock_timer -= delta
			var target_offset: Vector2 = _lock_target.global_position - get_parent().global_position
			offset = offset.lerp(target_offset, 12.0 * delta)
			if _lock_timer <= 0.0:
				_lock_active = false
				_lock_target = null
		else:
			_lock_active = false
			_lock_target = null
	elif offset != Vector2.ZERO:
		# Smooth return to player center after lock ends
		offset = offset.lerp(Vector2.ZERO, 8.0 * delta)
		if offset.length() < 0.5:
			offset = Vector2.ZERO

	# ── Screen shake ──────────────────────────────────────────────────────
	if shake_duration > 0.0:
		shake_duration -= delta
		offset += Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
	elif not _lock_active and offset == Vector2.ZERO:
		offset = Vector2.ZERO

func shake(duration: float = 0.2, strength: float = 4.0) -> void:
	shake_duration = duration
	shake_strength = strength
