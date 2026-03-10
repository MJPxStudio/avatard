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
var _rank_label:     Label = null
var _chat_bubble:    Node  = null
var _bubble_tween:   Tween = null
var _level_label:    Label = null
var is_dead:         bool  = false
const RESPAWN_TIME:  float = 5.0

# Cosmetic layers
var _hair_sprite:   Sprite2D   = null
var _equip_sprites: Dictionary = {}  # slot → Sprite2D
var _last_appearance: Dictionary = {}
var _last_equipped:   Dictionary = {}

const EQUIP_LAYER_Z := {
	"shoes": 1, "legs": 2, "chest": 3, "head": 6, "weapon": 7, "accessory": 8
}

const _EQUIP_TINT_SHADER := """
shader_type canvas_item;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float grey_threshold : hint_range(0.0, 0.2) = 0.08;
void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float lo = min(col.r, min(col.g, col.b));
	float hi = max(col.r, max(col.g, col.b));
	if ((hi - lo) <= grey_threshold) {
		float lum = (lo + hi) * 0.5;
		COLOR = vec4(tint_color.rgb * lum, col.a);
	} else {
		COLOR = col;
	}
}
"""

func _ready() -> void:
	# Sprite
	sprite = AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(0, -10)
	add_child(sprite)
	_build_animations()
	sprite.play("idle_down")
	_build_hair_layer()
	_build_equip_layers()

	# Solid collision body
	var body           = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask  = 0
	var col_shape      = CollisionShape2D.new()
	var rect           = RectangleShape2D.new()
	rect.size          = Vector2(10, 14)
	col_shape.shape    = rect
	body.add_child(col_shape)
	add_child(body)

func _build_hair_layer() -> void:
	_hair_sprite              = Sprite2D.new()
	_hair_sprite.name         = "HairSprite"
	_hair_sprite.z_index      = 5
	_hair_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hair_sprite.offset         = Vector2(0, -10)
	_hair_sprite.set_meta("textures", {})
	add_child(_hair_sprite)

func _build_equip_layers() -> void:
	for slot in EQUIP_LAYER_Z.keys():
		var spr              = Sprite2D.new()
		spr.name             = "Equip_%s" % slot.capitalize()
		spr.z_index          = EQUIP_LAYER_Z[slot]
		spr.texture_filter   = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.offset           = Vector2(0, -10)
		spr.visible          = false
		spr.material         = null
		spr.set_meta("textures", {})
		add_child(spr)
		_equip_sprites[slot] = spr

func _load_layer_textures(base_path: String) -> Dictionary:
	var textures  := {}
	var dirs      := ["down", "up", "left", "right"]
	for dir in dirs:
		# Idle — try both naming conventions
		var idle_tex := load(base_path + "idle_%s.png" % dir) as Texture2D
		if not idle_tex:
			idle_tex = load(base_path + "idle_%s_0.png" % dir) as Texture2D
		if idle_tex:
			textures["idle_" + dir]   = idle_tex
			textures["attack_" + dir] = idle_tex
		# Walk frames — try both conventions
		for fr in range(4):
			var tex := load(base_path + "walk_%s_%d.png" % [dir, fr]) as Texture2D
			if not tex:
				tex = load(base_path + "walk_%s%d.png" % [dir, fr]) as Texture2D
			if tex:
				textures["walk_%s_%d" % [dir, fr]] = tex
	return textures

func apply_appearance(appearance: Dictionary) -> void:
	if appearance == _last_appearance:
		return
	_last_appearance = appearance.duplicate()
	# Hair
	var hair_folder: String = appearance.get("hair_folder", "")
	if hair_folder != "" and _hair_sprite != null:
		var textures := _load_layer_textures(hair_folder)
		_hair_sprite.set_meta("textures", textures)
		var idle_key := "idle_" + facing_dir
		if textures.has(idle_key):
			_hair_sprite.texture = textures[idle_key]
	var hair_color = appearance.get("hair_color", null)
	if hair_color != null and _hair_sprite != null:
		_hair_sprite.modulate = hair_color

func apply_equipped(equipped: Dictionary) -> void:
	if equipped == _last_equipped:
		return
	_last_equipped = equipped.duplicate()
	# Clear all layers first
	for slot in _equip_sprites:
		_equip_sprites[slot].texture  = null
		_equip_sprites[slot].material = null
		_equip_sprites[slot].visible  = false
		_equip_sprites[slot].set_meta("textures", {})
	# Apply each equipped item
	for slot in equipped:
		if not _equip_sprites.has(slot):
			continue
		var item: Dictionary = equipped[slot]
		var folder: String   = item.get("sprite_folder", "")
		if folder == "":
			continue
		var spr: Sprite2D    = _equip_sprites[slot]
		var textures         := _load_layer_textures(folder)
		spr.set_meta("textures", textures)
		var tint: Color      = item.get("tint", Color("ffffff"))
		var shader           = Shader.new()
		shader.code          = _EQUIP_TINT_SHADER
		var mat              = ShaderMaterial.new()
		mat.shader           = shader
		mat.set_shader_parameter("tint_color", tint)
		spr.material         = mat
		var idle_key := "idle_" + facing_dir
		if textures.has(idle_key):
			spr.texture = textures[idle_key]
			spr.visible = true

func _sync_all_layers() -> void:
	# Called each frame to keep all layers in sync with the base sprite animation
	var anim: String  = sprite.animation if sprite else "idle_down"
	var frame: int    = sprite.frame     if sprite else 0
	var parts         = anim.split("_")  # e.g. ["walk","down"] or ["idle","down"]
	var anim_type     = parts[0]         # "walk" or "idle" or "attack"
	var dir           = facing_dir

	# Hair
	if _hair_sprite != null:
		var textures: Dictionary = _hair_sprite.get_meta("textures", {})
		if anim_type == "walk":
			var key := "walk_%s_%d" % [dir, frame]
			var fallback: String = "idle_" + dir
			_hair_sprite.texture = textures.get(key, textures.get(fallback))
		else:
			_hair_sprite.texture = textures.get("idle_" + dir)

	# Equipment
	for slot in _equip_sprites:
		var spr: Sprite2D        = _equip_sprites[slot]
		var textures: Dictionary = spr.get_meta("textures", {})
		if textures.is_empty():
			spr.texture = null
			continue
		if anim_type == "walk":
			var key := "walk_%s_%d" % [dir, frame]
			var fallback: String = "idle_" + dir
			spr.texture = textures.get(key, textures.get(fallback))
		else:
			spr.texture = textures.get("idle_" + dir)



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
	# Rank label — just below the name label
	if _rank_label == null:
		_rank_label = Label.new()
		_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rank_label.z_index              = 10
		_rank_label.add_theme_font_size_override("font_size", 7)
		_rank_label.add_theme_color_override("font_color",        Color("aaaaaa"))
		_rank_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
		_rank_label.add_theme_constant_override("shadow_offset_x", 1)
		_rank_label.add_theme_constant_override("shadow_offset_y", 1)
		_rank_label.size     = Vector2(80, 10)
		_rank_label.position = Vector2(-40, -31)  # just below name label
		add_child(_rank_label)

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

func set_rank(rank_name: String) -> void:
	if _rank_label == null:
		return
	_rank_label.text = rank_name
	var lv: int = 1
	# Derive level from rank name for color (rank_label exists before level is known)
	_rank_label.add_theme_color_override("font_color", RankDB.get_rank_color(
		RankDB.RANKS[RankDB.rank_index(rank_name)]["min_level"] if RankDB.rank_index(rank_name) >= 0 else 1
	))

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
	_sync_all_layers()

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
