extends Camera2D

# Set zoom directly on the Camera2D node in the Inspector (Zoom property).
# No override here — whatever you set in the editor is what you get.

# Screen shake
var shake_duration: float = 0.0
var shake_strength: float = 0.0

func _physics_process(delta: float) -> void:
	# Smooth follow (owner is the player node this camera is child of)
	# Camera2D handles position automatically when it's a child of player,
	# but if you ever detach it, use this:
	# global_position = global_position.lerp(target.global_position, follow_speed * delta)

	# Screen shake
	if shake_duration > 0.0:
		shake_duration -= delta
		offset = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)
	else:
		offset = Vector2.ZERO

func shake(duration: float = 0.2, strength: float = 4.0) -> void:
	shake_duration = duration
	shake_strength = strength
