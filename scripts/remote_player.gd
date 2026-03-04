extends Node2D

var peer_id: int = -1
var username: String = ""
var target_position: Vector2 = Vector2.ZERO
var facing_dir: String = "down"
var is_moving: bool = false

const INTERP_SPEED = 16.0

var sprite: AnimatedSprite2D = null
var name_label: Label = null

func _ready() -> void:
	# Sprite
	sprite = AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(0, -10)  # match local player sprite anchor
	add_child(sprite)
	_build_animations()
	sprite.play("idle_down")

	# Name label
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 8)
	name_label.add_theme_color_override("font_color", Color("ffffff"))
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-30, -28)
	name_label.size = Vector2(60, 12)
	add_child(name_label)

func _build_animations() -> void:
	var sf = SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	var dirs = ["down", "up", "right", "left"]
	for dir in dirs:
		var anim = "walk_" + dir
		sf.add_animation(anim)
		sf.set_animation_speed(anim, 10.0)
		sf.set_animation_loop(anim, true)
		for f in range(4):
			var tex = load("res://sprites/player/walk_%s_%d.png" % [dir, f]) as Texture2D
			if tex: sf.add_frame(anim, tex)
	for dir in dirs:
		var anim = "idle_" + dir
		sf.add_animation(anim)
		sf.set_animation_speed(anim, 1.0)
		sf.set_animation_loop(anim, false)
		var tex = load("res://sprites/player/idle_%s_0.png" % dir) as Texture2D
		if tex: sf.add_frame(anim, tex)
	sprite.sprite_frames = sf

func set_username(uname: String) -> void:
	username = uname
	if name_label:
		name_label.text = uname

func update_position(new_pos: Vector2) -> void:
	if new_pos != target_position:
		is_moving = true
		# Determine facing from movement direction
		var diff = new_pos - target_position
		if abs(diff.x) > abs(diff.y):
			facing_dir = "right" if diff.x > 0 else "left"
		elif diff.y != 0:
			facing_dir = "down" if diff.y > 0 else "up"
	target_position = new_pos

func _process(delta: float) -> void:
	var prev_pos = global_position
	global_position = global_position.lerp(target_position, INTERP_SPEED * delta)

	var moved = global_position.distance_to(prev_pos) > 0.5
	if moved:
		var walk_anim = "walk_" + facing_dir
		if sprite.animation != walk_anim:
			sprite.play(walk_anim)
	else:
		is_moving = false
		var idle_anim = "idle_" + facing_dir
		if sprite.animation != idle_anim:
			sprite.play(idle_anim)
