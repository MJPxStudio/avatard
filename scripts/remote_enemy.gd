extends Node2D

const ParticleBurst = preload("res://scripts/particle_burst.gd")

# ============================================================
# REMOTE ENEMY — Client-side visual representation
# Lerps toward server position. Supports target lock indicator.
# ============================================================

var target_position:   Vector2 = Vector2.ZERO
const INTERP_SPEED = 16.0
var enemy_type:   String  = "unknown"
var enemy_id:          String  = ""
var _last_hp:          int     = -1   # for hit flash detection
var _hitbox_size:      Vector2 = Vector2(14, 14)  # synced from server
var _attack_range:     float   = 0.0                  # synced from server for debug vis
var _hud_bar_fg:       Node    = null
var _hud_hp_label:     Node    = null
var _hud_name_label:   Node    = null
var _hud_level_label:  Node    = null
var _hud_max_hp:       int     = 1
var is_dead:           bool    = false
const HUD_BAR_W:       float   = 32.0
const HUD_BAR_H:       float   = 4.0
var _hitbox_vis:       Node    = null   # debug hitbox outline
var _sprite:           Node    = null   # reference to AnimatedSprite2D for shader flash

func setup(type: String) -> void:
	enemy_type = type
	z_index    = 2
	_build_visual()
	_build_hitbox_vis()
	_build_hud()

func _build_visual() -> void:
	match enemy_type:
		"Wolf":
			var sprite = AnimatedSprite2D.new()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.z_index = 2
			add_child(sprite)
			var sf = SpriteFrames.new()
			if sf.has_animation("default"):
				sf.remove_animation("default")
			for dir in ["down", "up", "left", "right"]:
				for prefix in ["walk", "idle"]:
					var anim = prefix + "_" + dir
					sf.add_animation(anim)
					sf.set_animation_speed(anim, 8.0)
					sf.set_animation_loop(anim, true)
					var tex = load("res://sprites/wolf/%s_%s_0.png" % [prefix, dir]) as Texture2D
					if tex:
						sf.add_frame(anim, tex)
			sprite.sprite_frames = sf
			sprite.play("walk_down")
			_sprite = sprite
			_attach_flash_shader(sprite)
		"Rogue Ninja":
			var sprite = AnimatedSprite2D.new()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.modulate = Color(0.4, 0.1, 0.5)
			sprite.z_index  = 2
			add_child(sprite)
			var sf = SpriteFrames.new()
			if sf.has_animation("default"):
				sf.remove_animation("default")
			for dir in ["down", "up", "left", "right"]:
				for prefix in ["walk", "idle"]:
					var anim = prefix + "_" + dir
					sf.add_animation(anim)
					sf.set_animation_speed(anim, 8.0)
					sf.set_animation_loop(anim, true)
					for i in range(4):
						var tex = load("res://sprites/player/%s_%s_%d.png" % [prefix, dir, i]) as Texture2D
						if tex:
							sf.add_frame(anim, tex)
			sprite.sprite_frames = sf
			sprite.play("walk_down")
			_sprite = sprite
			_attach_flash_shader(sprite)
		_:
			var vis      = ColorRect.new()
			vis.color    = Color("e74c3c")
			vis.size     = Vector2(14, 14)
			vis.position = Vector2(-7, -7)
			vis.z_index  = 2
			add_child(vis)

func _build_hud() -> void:
	# All HUD elements float above the sprite at a fixed offset
	var Y_OFFSET = -28.0
	var BAR_W    = 32.0
	var BAR_H    = 4.0

	# Name label
	var name_lbl      = Label.new()
	name_lbl.text     = enemy_type
	name_lbl.add_theme_font_size_override("font_size", 7)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	name_lbl.add_theme_constant_override("shadow_offset_x", 1)
	name_lbl.add_theme_constant_override("shadow_offset_y", 1)
	name_lbl.position = Vector2(-BAR_W / 2.0, Y_OFFSET - 18)
	name_lbl.z_index  = 10
	add_child(name_lbl)
	_hud_name_label = name_lbl

	# Level label (left of bar)
	var lvl_lbl      = Label.new()
	lvl_lbl.text     = "Lv.1"
	lvl_lbl.visible  = false  # level hidden from nameplate — shown in target HUD only
	lvl_lbl.add_theme_font_size_override("font_size", 6)
	lvl_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4, 1))
	lvl_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lvl_lbl.add_theme_constant_override("shadow_offset_x", 1)
	lvl_lbl.add_theme_constant_override("shadow_offset_y", 1)
	lvl_lbl.position = Vector2(-BAR_W / 2.0, Y_OFFSET - 9)
	lvl_lbl.z_index  = 10
	add_child(lvl_lbl)
	_hud_level_label = lvl_lbl

	# HP bar background (dark track)
	var bar_bg      = ColorRect.new()
	bar_bg.size     = Vector2(HUD_BAR_W, HUD_BAR_H)
	bar_bg.position = Vector2(-HUD_BAR_W / 2.0, Y_OFFSET)
	bar_bg.color    = Color(0.1, 0.1, 0.1, 0.85)
	bar_bg.z_index  = 9
	add_child(bar_bg)

	# HP bar foreground
	var bar_fg       = ColorRect.new()
	bar_fg.size      = Vector2(HUD_BAR_W, HUD_BAR_H)
	bar_fg.position  = Vector2(-HUD_BAR_W / 2.0, Y_OFFSET)
	bar_fg.color     = Color(0.65, 0.08, 0.08, 1.0)
	bar_fg.z_index   = 10
	add_child(bar_fg)
	_hud_bar_fg = bar_fg

	# HP number label
	var hp_lbl      = Label.new()
	hp_lbl.text     = ""
	hp_lbl.add_theme_font_size_override("font_size", 6)
	hp_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	hp_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	hp_lbl.add_theme_constant_override("shadow_offset_x", 1)
	hp_lbl.add_theme_constant_override("shadow_offset_y", 1)
	hp_lbl.position = Vector2(-BAR_W / 2.0, Y_OFFSET + BAR_H + 1)
	hp_lbl.z_index  = 10
	add_child(hp_lbl)
	_hud_hp_label = hp_lbl

func update_position(new_pos: Vector2) -> void:
	target_position = new_pos

func update_hitbox_size(size: Vector2) -> void:
	if size == _hitbox_size:
		return
	_hitbox_size = size
	# Rebuild outline with new dimensions
	if _hitbox_vis and is_instance_valid(_hitbox_vis):
		_hitbox_vis.queue_free()
		_hitbox_vis = null
	_build_hitbox_vis()

func update_state(new_hp: int, new_state: String, new_max_hp: int = -1, new_level: int = -1) -> void:
	# Freeze interpolation during boss windup so the boss stays still visually
	if new_state == "windup":
		target_position = global_position
	var was_alive = not is_dead
	is_dead = (new_hp <= 0)
	# Enemy death burst — only fires on the alive→dead transition
	if is_dead and was_alive:
		ParticleBurst.spawn(get_tree(), global_position, "death_enemy")
	# Detect hp drop and trigger hit flash
	if _last_hp != -1 and new_hp < _last_hp and not is_dead:
		hit_flash()
	_last_hp = new_hp
	# Update HUD
	if new_max_hp > 0:
		_hud_max_hp = new_max_hp
	var ratio = float(new_hp) / float(max(_hud_max_hp, 1))
	if _hud_bar_fg and is_instance_valid(_hud_bar_fg):
		_hud_bar_fg.size.x = HUD_BAR_W * ratio
		# Colour shifts red as HP drops
		_hud_bar_fg.color = Color(0.65, 0.08, 0.08, 1.0)
	if _hud_hp_label and is_instance_valid(_hud_hp_label):
		_hud_hp_label.text = "%d/%d" % [new_hp, _hud_max_hp]
	if new_level > 0 and _hud_level_label and is_instance_valid(_hud_level_label):
		_hud_level_label.text = "Lv.%d" % new_level

func show_indicator(text: String, color: Color) -> void:
	var lbl           = Label.new()
	lbl.text          = text
	lbl.z_index       = 60
	lbl.position      = Vector2(-6, -32)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	add_child(lbl)
	var tween = create_tween()
	tween.tween_property(lbl, "position:y", lbl.position.y - 18, 0.5)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.5)
	tween.tween_callback(lbl.queue_free)

func show_windup() -> void:
	# Flicker orange during windup — distinct from red hit flash
	var tween = create_tween()
	tween.set_loops(6)
	if _sprite and is_instance_valid(_sprite):
		tween.tween_property(_sprite, "modulate", Color(1.5, 0.6, 0.1, 1.0), 0.1)
		tween.tween_property(_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)
	else:
		# ColorRect fallback
		for c in get_children():
			if c is ColorRect and c.z_index == 2:
				tween.tween_property(c, "modulate", Color(1.5, 0.6, 0.1, 1.0), 0.1)
				tween.tween_property(c, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)
				break

func telegraph(color: Color = Color(1, 0.3, 0, 0.8), duration: float = 0.4) -> void:
	var flash      = ColorRect.new()
	flash.color    = color
	flash.size     = Vector2(20, 20)
	flash.position = Vector2(-10, -18)
	flash.z_index  = 5
	add_child(flash)
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, duration)
	tween.tween_callback(flash.queue_free)

func _build_hitbox_vis() -> void:
	# Outline matching server-side CollisionShape2D — size synced at runtime
	var outline      = Node2D.new()
	outline.z_index  = 50
	outline.name     = "HitboxVis"
	# Four edges as thin ColorRects
	var W = _hitbox_size.x; var H = _hitbox_size.y
	var edges = [
		[Vector2(-W/2.0, -H/2.0),      Vector2(W, 1)],   # top
		[Vector2(-W/2.0,  H/2.0 - 1),  Vector2(W, 1)],   # bottom
		[Vector2(-W/2.0, -H/2.0),      Vector2(1, H)],   # left
		[Vector2( W/2.0 - 1, -H/2.0),  Vector2(1, H)],   # right
	]
	for edge in edges:
		var r      = ColorRect.new()
		r.position = edge[0]
		r.size     = edge[1]
		r.color    = Color(0, 1, 1, 0.9)
		outline.add_child(r)
	_hitbox_vis = outline
	add_child(outline)
	# Start hidden — F1 in gs.gd controls visibility
	outline.visible = false

func set_hitbox_visible(visible: bool) -> void:
	if _hitbox_vis and is_instance_valid(_hitbox_vis):
		_hitbox_vis.visible = visible
	var arv = get_node_or_null("AttackRangeVis")
	if arv:
		arv.visible = visible

func set_attack_range(r: float) -> void:
	_attack_range = r
	var old_vis = get_node_or_null("AttackRangeVis")
	if old_vis:
		old_vis.queue_free()
	if r <= 0.0:
		return
	# Draw approximate circle using 16 short ColorRect segments
	var vis       = Node2D.new()
	vis.name      = "AttackRangeVis"
	vis.z_index   = 49
	vis.visible   = false
	var segments  = 20
	var seg_len   = (TAU * r) / segments
	for i in range(segments):
		var angle = (TAU / segments) * i
		var seg           = ColorRect.new()
		seg.size          = Vector2(seg_len + 1, 1)
		seg.color         = Color(1.0, 0.5, 0.0, 0.85)
		seg.position      = Vector2(cos(angle) * r, sin(angle) * r)
		seg.rotation      = angle + PI / 2.0
		vis.add_child(seg)
	add_child(vis)

func _attach_flash_shader(sprite: Node) -> void:
	var mat    = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform bool  outline_active = false;
uniform vec4  outline_color : source_color = vec4(0.9, 0.1, 0.1, 1.0);

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (col.a < 0.01 && outline_active) {
		// Draw outline on transparent pixels bordering opaque ones
		vec2 px = TEXTURE_PIXEL_SIZE;
		float n = 0.0;
		n = max(n, texture(TEXTURE, UV + vec2( px.x, 0.0 )).a);
		n = max(n, texture(TEXTURE, UV + vec2(-px.x, 0.0 )).a);
		n = max(n, texture(TEXTURE, UV + vec2( 0.0,  px.y)).a);
		n = max(n, texture(TEXTURE, UV + vec2( 0.0, -px.y)).a);
		COLOR = n > 0.01 ? outline_color : vec4(0.0);
	} else {
		if (col.a > 0.01) {
			col.rgb = mix(col.rgb, vec3(1.0), flash_amount);
		}
		COLOR = col;
	}
}
"""
	mat.shader = shader
	sprite.material = mat

func hit_flash() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var mat = _sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("flash_amount", 1.0)
	var tween = create_tween()
	tween.tween_method(func(v): mat.set_shader_parameter("flash_amount", v), 1.0, 0.0, 0.12)

func set_targeted(active: bool) -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var mat = _sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("outline_active", active)

func _process(delta: float) -> void:
	global_position = global_position.lerp(target_position, INTERP_SPEED * delta)
