extends Node2D

var target_position: Vector2 = Vector2.ZERO
const INTERP_SPEED = 16.0
var sprite: AnimatedSprite2D = null

func _ready() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	_build_animations()
	sprite.play("walk_down")

func _build_animations() -> void:
	var sf = SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	var dirs = ["down", "up", "left", "right"]
	for dir in dirs:
		for prefix in ["walk", "idle"]:
			var anim = prefix + "_" + dir
			sf.add_animation(anim)
			sf.set_animation_speed(anim, 8.0)
			sf.set_animation_loop(anim, true)
			var path = "res://sprites/wolf/%s_%s_0.png" % [prefix, dir]
			var tex = load(path) as Texture2D
			if tex:
				sf.add_frame(anim, tex)
	sprite.sprite_frames = sf

func update_position(new_pos: Vector2) -> void:
	var diff = new_pos - target_position
	if diff.length() > 1.0:
		if abs(diff.x) > abs(diff.y):
			var dir = "right" if diff.x > 0 else "left"
			if sprite.animation != "walk_" + dir:
				sprite.play("walk_" + dir)
		else:
			var dir = "down" if diff.y > 0 else "up"
			if sprite.animation != "walk_" + dir:
				sprite.play("walk_" + dir)
	target_position = new_pos

func _process(delta: float) -> void:
	global_position = global_position.lerp(target_position, INTERP_SPEED * delta)
