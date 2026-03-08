extends Node2D

var peer_id: int = -1
var username: String = ""
signal right_clicked(player_node: Node, screen_pos: Vector2)

var _is_party_member: bool = false
var _is_targeted:     bool = false
var target_position: Vector2 = Vector2.ZERO
var facing_dir: String = "down"
var is_moving: bool = false

const INTERP_SPEED = 16.0

var sprite:          AnimatedSprite2D = null
var _death_timer:    float = 0.0
var _death_label:    Label = null
var _name_label:     Label = null
var _chat_bubble:    Node  = null   # current speech bubble node
var _bubble_tween:   Tween = null
var _level_label:    Label = null
var is_dead:         bool  = false
const RESPAWN_TIME:  float = 5.0

func _ready() -> void:
	# Sprite
	sprite = AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(0, -10)  # match local player sprite anchor
	add_child(sprite)
	_build_animations()
	sprite.play("idle_down")

	# Solid collision body so the local player cannot walk through us.
	# StaticBody2D on layer 1 (local player layer) — no mask needed (it doesn't push anything).
	var body           = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var col_shape      = CollisionShape2D.new()
	var rect           = RectangleShape2D.new()
	rect.size          = Vector2(10, 14)
	col_shape.shape    = rect
	body.add_child(col_shape)
	add_child(body)



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
	_attach_outline_shader(sprite)

func set_username(uname: String) -> void:
	username = uname
	# Create or update floating nameplate above sprite
	if _name_label == null:
		_name_label = Label.new()
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.z_index              = 10
		_name_label.add_theme_font_size_override("font_size", 8)
		_name_label.add_theme_color_override("font_color",        Color(1.0, 0.82, 0.2, 1.0))  # gold
		_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
		_name_label.add_theme_constant_override("shadow_offset_x", 1)
		_name_label.add_theme_constant_override("shadow_offset_y", 1)
		_name_label.size = Vector2(80, 12)
		_name_label.position = Vector2(-40, -42)  # centered above sprite
		add_child(_name_label)
		# Level label — small, just below name
		_level_label = Label.new()
		_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_level_label.z_index              = 10
		_level_label.add_theme_font_size_override("font_size", 7)
		_level_label.add_theme_color_override("font_color",        Color(0.7, 0.9, 0.7, 1.0))
		_level_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
		_level_label.add_theme_constant_override("shadow_offset_x", 1)
		_level_label.add_theme_constant_override("shadow_offset_y", 1)
		_level_label.size     = Vector2(80, 10)
		_level_label.position = Vector2(-40, -32)
		_level_label.visible  = false  # level shown in target HUD only, not nameplate
		add_child(_level_label)
	_name_label.text = uname

func _attach_outline_shader(spr: Node) -> void:
	var mat    = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform bool outline_active = false;
uniform vec4 outline_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform bool death_active = false;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (col.a < 0.01 && outline_active) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float n = 0.0;
		n = max(n, texture(TEXTURE, UV + vec2( px.x, 0.0 )).a);
		n = max(n, texture(TEXTURE, UV + vec2(-px.x, 0.0 )).a);
		n = max(n, texture(TEXTURE, UV + vec2( 0.0,  px.y)).a);
		n = max(n, texture(TEXTURE, UV + vec2( 0.0, -px.y)).a);
		COLOR = n > 0.01 ? outline_color : vec4(0.0);
	} else {
		COLOR = death_active ? col * vec4(0.3, 0.3, 0.3, 1.0) : col;
	}
}
"""
	mat.shader = shader
	spr.material = mat

func set_targeted(on: bool) -> void:
	_is_targeted = on
	_update_outline()

func set_party_member(on: bool) -> void:
	_is_party_member = on
	_update_outline()

func _update_outline() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var mat = sprite.material as ShaderMaterial
	if mat == null:
		return
	# Party members always show a green outline (dimmed when not targeted)
	# Non-party targeted players show blue outline
	if _is_party_member:
		var alpha = 1.0 if _is_targeted else 0.55
		mat.set_shader_parameter("outline_color", Color(0.2, 0.95, 0.35, alpha))
		mat.set_shader_parameter("outline_active", true)
	else:
		mat.set_shader_parameter("outline_color", Color(0.3, 0.6, 1.0, 1.0))
		mat.set_shader_parameter("outline_active", _is_targeted)

func update_position(new_pos: Vector2) -> void:
	if new_pos != target_position:
		var diff = new_pos - target_position
		# If position jump is large (e.g. respawn teleport), snap immediately
		# instead of lerping across the entire map visually
		if diff.length() > 300.0:
			global_position = new_pos
		is_moving = true
		# Determine facing from movement direction
		if abs(diff.x) > abs(diff.y):
			facing_dir = "right" if diff.x > 0 else "left"
		elif diff.y != 0:
			facing_dir = "down" if diff.y > 0 else "up"
	target_position = new_pos

func set_facing(dir: String) -> void:
	if dir != facing_dir:
		facing_dir = dir
		# Apply idle facing immediately when not moving
		if not is_moving and sprite:
			sprite.play("idle_" + facing_dir)

func set_level(lv: int) -> void:
	if _level_label:
		_level_label.text = "Lv. %d" % lv

func set_dead(dead: bool) -> void:
	is_dead = dead
	# Dim nameplate when dead
	if _name_label:
		_name_label.modulate.a = 0.35 if dead else 1.0
	if _level_label:
		_level_label.modulate.a = 0.35 if dead else 1.0
	# Shader darkening
	if sprite != null and is_instance_valid(sprite):
		var mat = sprite.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("death_active", dead)
	# Disable collision so dead players are walkable
	var body = get_node_or_null("StaticBody2D")
	if body:
		body.collision_layer = 0 if dead else 1
	# World-space respawn countdown above body
	if dead:
		# Only create label + reset timer on the first dead=true call, not every sync tick
		if _death_label == null:
			_death_timer = RESPAWN_TIME
			_death_label = Label.new()
			_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_death_label.position = Vector2(-12, -28)
			_death_label.add_theme_font_size_override("font_size", 9)
			_death_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
			_death_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
			_death_label.add_theme_constant_override("shadow_offset_x", 1)
			_death_label.add_theme_constant_override("shadow_offset_y", 1)
			add_child(_death_label)
		_update_death_label()
	else:
		if _death_label != null:
			_death_label.queue_free()
			_death_label = null
		_death_timer = 0.0

func _update_death_label() -> void:
	if _death_label == null:
		return
	var secs = ceili(_death_timer)
	_death_label.text = "%d" % max(secs, 0)

func _process(delta: float) -> void:
	if _death_label != null:
		_death_timer = max(_death_timer - delta, 0.0)
		_update_death_label()
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

func _bubble_count_lines(text: String, chars_per_line: int) -> int:
	var words = text.split(" ")
	var lines = 1
	var cur = 0
	for word in words:
		var wlen = word.length()
		if cur == 0:
			cur = wlen
		elif cur + 1 + wlen > chars_per_line:
			lines += 1
			cur = wlen
		else:
			cur += 1 + wlen
	return lines

func show_chat_bubble(text: String) -> void:
	if _bubble_tween != null and _bubble_tween.is_valid():
		_bubble_tween.kill()
	if _chat_bubble != null and is_instance_valid(_chat_bubble):
		_chat_bubble.queue_free()

	const FONT_SZ      := 8
	const PAD          := 5
	const MAX_W        := 120
	const LINE_H       := 10
	const CHARS_SINGLE := 22
	const TAIL_H       := 5
	const GAP          := 3    # gap between tail tip and nameplate (Y=-42)

	var single_w = int(text.length() * 5.2 + PAD * 2)
	var bubble_w: int
	var line_count: int
	if single_w <= MAX_W:
		bubble_w   = max(single_w, 30)
		line_count = 1
	else:
		bubble_w   = MAX_W
		line_count = _bubble_count_lines(text, CHARS_SINGLE)

	var bubble_h = line_count * LINE_H + PAD * 2

	# Layout (Y axis, world space):
	#   nameplate:   Y = -42
	#   tail tip:    Y = -42 - GAP            = -45
	#   panel bottom:Y = -42 - GAP - TAIL_H   = -50  (= tail base)
	#   panel top:   Y = panel_bottom - bubble_h
	var panel_bottom = -42 - GAP - TAIL_H
	var top_y        = panel_bottom - bubble_h

	var root = Node2D.new()
	root.z_index = 12
	_chat_bubble = root
	add_child(root)

	# Background panel
	var panel = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.96)
	style.border_color = Color(0.25, 0.25, 0.25, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	panel.size     = Vector2(bubble_w, bubble_h)
	panel.position = Vector2(-bubble_w / 2.0, top_y)
	root.add_child(panel)

	# Tail — base flush with panel bottom, tip points DOWN toward nameplate
	# polygon: base at Y=0, tip at Y=+TAIL_H → position at panel_bottom
	var half_tail = 5
	var tail = Polygon2D.new()
	tail.color   = Color(0.25, 0.25, 0.25, 1.0)
	tail.polygon = PackedVector2Array([
		Vector2(-half_tail, 0),
		Vector2( half_tail, 0),
		Vector2(0,          TAIL_H),
	])
	tail.position = Vector2(0, panel_bottom)
	root.add_child(tail)

	# White fill covers tail interior so border line doesn't bleed through
	var tail_fill = Polygon2D.new()
	tail_fill.color   = Color(1.0, 1.0, 1.0, 0.96)
	tail_fill.polygon = PackedVector2Array([
		Vector2(-(half_tail - 1), 1),
		Vector2( (half_tail - 1), 1),
		Vector2(0,                TAIL_H - 1),
	])
	tail_fill.position = Vector2(0, panel_bottom)
	root.add_child(tail_fill)

	# Text label
	var lbl = Label.new()
	lbl.text                 = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	lbl.size                 = Vector2(bubble_w - PAD * 2, bubble_h)
	lbl.position             = Vector2(-bubble_w / 2.0 + PAD, top_y)
	lbl.add_theme_font_size_override("font_size", FONT_SZ)
	lbl.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1.0))
	root.add_child(lbl)

	_bubble_tween = get_tree().create_tween()
	_bubble_tween.tween_interval(3.5)
	_bubble_tween.tween_property(root, "modulate:a", 0.0, 0.6)
	_bubble_tween.tween_callback(func(): if is_instance_valid(root): root.queue_free())
