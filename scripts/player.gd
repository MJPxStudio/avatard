extends CharacterBody2D

const QuestDB = preload("res://scripts/quest_db.gd")

const ParticleBurst = preload("res://scripts/particle_burst.gd")

# ============================================================
# PLAYER — Grid-snapped step movement + combat + targeting
# ============================================================

@export var tile_size:      int   = 16
@export var walk_step_rate: float = 0.14
@export var run_step_rate:  float = 0.08

@export var attack_damage:    int   = 15
@export var attack_range:     float = 40.0
@export var attack_width:     float = 36.0
@export var attack_cooldown:  float = 0.4
@export var attack_knockback: float = 120.0

var is_running:   bool   = false
var is_dead:      bool   = false
var invuln_ticks: float  = 0.0
var facing_dir:   String = "down"

# ── Cosmetics ─────────────────────────────────────────────────────────────────
var hair_style: String = "Hair1"             # subfolder under Hairs/
var hair_color: Color  = Color("e8c49a")     # default blonde-ish
var _hair_sprite: Sprite2D = null

# Equipment visual layers — keyed by equip slot name (weapon/head/chest/legs/shoes/accessory)
# Each value is a Sprite2D node; absent key or null = slot empty / no sprite sheet loaded
var _equip_sprites: Dictionary = {}

# Z-index stacking order (bottom → top):
#   base player (AnimatedSprite2D) = 0
#   shoes = 1, legs = 2, shirt = 3, chest = 4, hair = 5, head = 6, weapon = 7, accessory = 8
const EQUIP_LAYER_Z := {
	"weapon":    7,
	"head":      6,
	"chest":     4,
	"legs":      2,
	"shoes":     1,
	"accessory": 8,
}

# Cosmetic layer animation tracking — updated whenever .play() is called
var _cosm_anim:  String = "idle_down"
var _cosm_frame: int    = 0

var grid_pos:      Vector2
var target_pos:    Vector2
var is_stepping:   bool  = false
var step_timer:    float = 0.0
var last_safe_pos: Vector2

var attack_timer:   float = 0.0
var is_attacking:   bool  = false
var hitstop_timer:  float = 0.0  # freezes movement briefly on hit

# Targeting
var locked_target:    Node2D = null
var locked_target_id: String = ""

# Debug
var _debug_attack_vis: Polygon2D = null
var _debug_enabled:    bool      = false
var _attack_flash:     float     = 0.0  # timer — briefly brighten vis on swing

# Stats
var max_hp:         int = 100
var current_hp:     int = 100
var max_chakra:     int = 100
var current_chakra: int = 100
var level:          int = 1
var current_exp:    int = 0
var max_exp:        int = 100

var hud           = null
var inventory     = null
var respawn_screen  = null  # set by main.gd; shown on death, freed on respawn
var dialogue_open:  bool = false  # true while dialogue box is open — blocks movement/attacks
var _charging:        bool  = false
var _charge_rate:     float = 12.0    # chakra per second while charging
var _charge_accum:    float = 0.0     # fractional chakra accumulator (current_chakra is int)
var _charge_particles: CPUParticles2D = null  # persistent swirl node
var settings_open:  bool = false
var kills:          int  = 0
var deaths:         int  = 0
var minimap             = null
var party_hud           = null
var party_invite_popup  = null
var hotbar     = null
var equip_panel  = null
var dungeon_hud  = null
var stat_panel  = null
var target_hud  = null
var chat        = null
var _chat_bubble:  Node  = null
var _bubble_tween: Tween = null

var stat_hp:       int = 5
var stat_chakra:   int = 5
var stat_strength: int = 5
var stat_dex:      int = 5
var stat_int:      int = 5
var stat_points:   int = 0
var quest_state:   Dictionary = {}   # local mirror of server quest_state
var quest_hud:     Node = null

var dodge_chance: float = 0.0
var cd_reduction: float = 0.0

var bleed_ticks:  int   = 0
var bleed_damage: int   = 2
var bleed_timer:  float = 0.0

var hot_ticks:    int   = 0
var hot_amount:   int   = 0
var hot_interval: float = 1.0
var hot_timer:    float = 0.0

func _ready() -> void:
	grid_pos        = _snap_to_grid(global_position)
	target_pos      = grid_pos
	global_position = grid_pos
	last_safe_pos   = grid_pos
	_build_animations()
	$AnimatedSprite2D.play("idle_down")
	_cosm_anim = "idle_down"
	_update_hud()
	$AnimatedSprite2D.animation_finished.connect(_on_animation_finished)
	# Ensure collision_mask includes layer 1 (remote player bodies) so _try_step blocks on them
	collision_mask = collision_mask | 1
	_build_hair_sprite()
	_build_equip_layers()
	_build_attack_vis()

func connect_network_signals() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs and not gs.damage_received.is_connected(_on_server_damage):
		gs.damage_received.connect(_on_server_damage)
	var net = get_tree().root.get_node_or_null("Network")
	if net and not net.hit_confirmed.is_connected(_on_hit_confirmed):
		net.hit_confirmed.connect(_on_hit_confirmed)
	if not net.ability_hit_confirmed.is_connected(_on_ability_hit_confirmed):
		net.ability_hit_confirmed.connect(_on_ability_hit_confirmed)
	if net and not net.xp_gained_client.is_connected(_on_xp_gained):
		net.xp_gained_client.connect(_on_xp_gained)
	if net and not net.level_up_client.is_connected(_on_level_up):
		net.level_up_client.connect(_on_level_up)
	if net and not net.quest_progress_client.is_connected(_on_quest_progress):
		net.quest_progress_client.connect(_on_quest_progress)
	if net and not net.quest_turned_in_client.is_connected(_on_quest_turned_in):
		net.quest_turned_in_client.connect(_on_quest_turned_in)
	if net and not net.enemy_killed_client.is_connected(_on_enemy_killed):
		net.enemy_killed_client.connect(_on_enemy_killed)
	if net and not net.party_xp_shared_client.is_connected(_on_party_xp_shared):
		net.party_xp_shared_client.connect(_on_party_xp_shared)

func _on_server_damage(amount: int, knockback_dir: Vector2) -> void:
	# amount=0 is the server's respawn signal after death timer
	if amount == 0:
		print("[CLIENT] Received respawn signal — is_dead=%s" % str(is_dead))
		if is_dead:
			_respawn()
		else:
			# is_dead should be true here — if it's not, the fatal hit was dropped by
			# client-side invuln. Force-respawn anyway since server is authoritative.
			print("[CLIENT] WARNING: respawn signal but is_dead==false — forcing respawn")
			_respawn()
		return
	# Server is authoritative — clear client invuln before applying damage.
	# Server already validated this hit should land; client invuln must not block it.
	# Mismatch (server 0.5s vs client 0.6s) was causing fatal hits to be silently dropped,
	# leaving client at 15 HP with is_dead=false while server thought player was dead.
	invuln_ticks = 0.0
	call_deferred("_sync_max_hp_to_server")
	take_damage(amount, knockback_dir, 120.0)

func _on_ability_hit_confirmed(hit_pos: Vector2, _amount: int) -> void:
	# Ability hit — particles only, no recoil, no hitstop
	ParticleBurst.spawn(get_tree(), hit_pos, "hit")

func _on_hit_confirmed(hit_pos: Vector2, amount: int) -> void:
	# damage_numbers.gd handles floating hit numbers via hit_confirmed signal
	ParticleBurst.spawn(get_tree(), hit_pos, "hit")
	# Hitstop — freeze player for 2 frames (~0.033s at 60fps)
	hitstop_timer = 0.033
	var cam = get_node_or_null("Camera2D")
	if cam and cam.has_method("shake"):
		cam.shake(0.10, 4.0)
	# Bounce back — only recoil on melee swing, never on ability/remote hits
	if not is_attacking:
		return
	var recoil_dir   = -get_attack_direction()
	var recoil_dest  = _snap_to_grid(global_position + recoil_dir * 20.0)
	# Check collision at recoil destination — fall back to current pos if blocked
	var space  = get_world_2d().direct_space_state
	var shape  = $CollisionShape2D.shape
	var query  = PhysicsShapeQueryParameters2D.new()
	query.shape          = shape
	query.transform      = Transform2D(0, recoil_dest)
	query.exclude        = [self]
	query.collision_mask = collision_mask
	var results = space.intersect_shape(query)
	var blocked = results.any(func(r): return not r.collider.is_in_group("enemy") and not r.collider.is_in_group("player"))
	if blocked:
		recoil_dest = _snap_to_grid(global_position)  # stay in place if wall is there
	target_pos  = recoil_dest
	grid_pos    = _snap_to_grid(global_position)
	is_stepping = true
	step_timer  = 0.08
	# Sync recoil destination to server so position stays consistent
	var net = get_node_or_null("/root/Network")
	if net != null and net.is_network_connected():
		net.send_position.rpc_id(1, recoil_dest)

func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / tile_size) * tile_size,
		round(pos.y / tile_size) * tile_size
	)

func _update_hud() -> void:
	if hud == null:
		return
	hud.update_hp(current_hp, max_hp)
	hud.update_chakra(current_chakra, max_chakra)
	hud.update_exp(current_exp, max_exp)
	hud.update_level(level)

func _build_animations() -> void:
	var sf   := SpriteFrames.new()
	var dirs := ["down", "up", "right", "left"]
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for dir in dirs:
		var anim_name = "walk_" + dir
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 10.0)
		sf.set_animation_loop(anim_name, true)
		for f in range(4):
			var tex := load("res://sprites/player/walk_%s_%d.png" % [dir, f]) as Texture2D
			if tex: sf.add_frame(anim_name, tex)
	for dir in dirs:
		var anim_name = "idle_" + dir
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 1.0)
		sf.set_animation_loop(anim_name, false)
		var tex := load("res://sprites/player/idle_%s_0.png" % dir) as Texture2D
		if tex: sf.add_frame(anim_name, tex)
	for dir in dirs:
		var anim_name = "attack_" + dir
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, 12.0)
		sf.set_animation_loop(anim_name, false)
		var tex := load("res://sprites/player/attack_%s_0.png" % dir) as Texture2D
		if tex: sf.add_frame(anim_name, tex)
	sf.add_animation("seals")
	sf.set_animation_speed("seals", 10.0)
	sf.set_animation_loop("seals", false)
	for f in range(5):
		var tex := load("res://sprites/player/seals_%d.png" % f) as Texture2D
		if tex: sf.add_frame("seals", tex)
	$AnimatedSprite2D.sprite_frames = sf

# ── Cosmetic layer helpers ────────────────────────────────────────────────────
# Sprite2D siblings of AnimatedSprite2D (NOT children of it).
# _process reads AnimatedSprite2D.animation + .frame every frame directly.
# No signals. No tracking variables. Dead simple.

func _load_layer_textures(base_path: String) -> Dictionary:
	var textures := {}
	var dirs := ["down", "up", "right", "left"]
	for dir in dirs:
		for fr in range(4):
			var tex := load(base_path + "walk_%s%d.png" % [dir, fr]) as Texture2D
			if not tex:
				tex = load(base_path + "walk_%s_%d.png" % [dir, fr]) as Texture2D
			if tex: textures["walk_%s_%d" % [dir, fr]] = tex
		var idle_tex := load(base_path + "idle_%s.png" % dir) as Texture2D
		if idle_tex:
			textures["idle_" + dir]   = idle_tex
			textures["attack_" + dir] = idle_tex
		var atk_tex := load(base_path + "attack_%s.png" % dir) as Texture2D
		if atk_tex: textures["attack_" + dir] = atk_tex
	return textures

func _process(_delta: float) -> void:
	# Read AnimatedSprite2D state directly every render frame
	var anim: String = $AnimatedSprite2D.animation
	var fr:   int    = $AnimatedSprite2D.frame
	var key:  String
	if anim.begins_with("walk_"):
		key = "%s_%d" % [anim, fr]
	elif anim.begins_with("idle_"):
		key = anim
	elif anim.begins_with("attack_"):
		key = "attack_" + anim.substr(7)
	else:
		key = "idle_down"
	# Fall back to idle facing direction if a walk/attack frame is missing.
	var fallback_key: String = "idle_" + facing_dir
	_sync_layer(_hair_sprite, key, fallback_key)
	for spr in _equip_sprites.values():
		_sync_layer(spr, key, fallback_key)

func _sync_layer(spr: Sprite2D, key: String, fallback_key: String) -> void:
	if spr == null or not is_instance_valid(spr):
		return
	var t: Dictionary = spr.get_meta("textures", {})
	var lookup: String = key if t.has(key) else fallback_key
	if t.has(lookup):
		spr.texture = t[lookup]

func _cosm_play(_anim: String) -> void:
	pass  # unused — _process handles sync

func _build_hair_sprite() -> void:
	_hair_sprite          = Sprite2D.new()
	_hair_sprite.name     = "HairSprite"
	_hair_sprite.z_index  = 5   # above chest/shirt layers
	_hair_sprite.modulate = hair_color
	add_child(_hair_sprite)
	_hair_sprite.position = $AnimatedSprite2D.position
	_hair_sprite.set_meta("textures", _load_layer_textures("res://sprites/player/Hairs/%s/" % hair_style))

func set_hair_style(style: String) -> void:
	hair_style = style
	if _hair_sprite: _hair_sprite.queue_free()
	_hair_sprite = null
	_build_hair_sprite()

func set_hair_color(color: Color) -> void:
	hair_color = color
	if _hair_sprite: _hair_sprite.modulate = color

func _build_shirt_sprite() -> void:
	pass  # Shirt is now a chest slot equip item — see inventory.gd

func set_shirt_style(_style: String) -> void:
	pass  # Deprecated — shirt is now driven by equip_panel chest slot

func set_shirt_color(_color: Color) -> void:
	pass  # Deprecated — tint equip items via set_equip_layer tint if needed

# ── Equipment visual layers ────────────────────────────────────────────────────

func _build_equip_layers() -> void:
	# Pre-create a Sprite2D node for every possible equipment slot.
	# Nodes start with no texture; set_equip_layer() loads textures when gear is equipped.
	for slot in EQUIP_LAYER_Z.keys():
		var spr          = Sprite2D.new()
		spr.name         = "Equip_%s" % slot.capitalize()
		spr.z_index      = EQUIP_LAYER_Z[slot]
		spr.position     = $AnimatedSprite2D.position
		spr.set_meta("textures", {})
		add_child(spr)
		_equip_sprites[slot] = spr

func set_equip_layer(slot: String, sprite_folder: String, tint: Color = Color("ffffff")) -> void:
	# Called by equip_panel when an item with a sprite_folder is equipped.
	if not _equip_sprites.has(slot):
		return
	var spr: Sprite2D = _equip_sprites[slot]
	var textures := _load_layer_textures(sprite_folder)
	spr.set_meta("textures", textures)
	spr.modulate = tint
	# Set an immediate texture so it shows without waiting for next _process tick
	var immediate_key := "idle_" + facing_dir
	if textures.has(immediate_key):
		spr.texture = textures[immediate_key]

func set_equip_layer_color(slot: String, color: Color) -> void:
	# Called by tailor transmog to recolor a live equipment layer.
	if not _equip_sprites.has(slot):
		return
	_equip_sprites[slot].modulate = color

func clear_equip_layer(slot: String) -> void:
	# Called by equip_panel when an item is unequipped.
	if not _equip_sprites.has(slot):
		return
	var spr: Sprite2D = _equip_sprites[slot]
	spr.texture = null
	spr.set_meta("textures", {})

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if invuln_ticks > 0:
		invuln_ticks -= delta
		modulate.a = 0.4 if fmod(invuln_ticks, 0.12) < 0.06 else 1.0
		if invuln_ticks <= 0:
			invuln_ticks = 0
			modulate.a   = 1.0

	if hot_ticks > 0:
		hot_timer -= delta
		if hot_timer <= 0.0:
			hot_timer   = hot_interval
			current_hp  = min(max_hp, current_hp + hot_amount)
			hot_ticks  -= 1
			_spawn_damage_number(global_position, hot_amount, Color("2ecc71"))
			_update_hud()

	if bleed_ticks > 0:
		bleed_timer -= delta
		if bleed_timer <= 0.0:
			bleed_timer  = 1.0
			take_damage(bleed_damage, Vector2.ZERO)
			bleed_ticks -= 1

	if hitstop_timer > 0:
		hitstop_timer -= delta
		move_and_slide()
		return

	if attack_timer > 0:
		attack_timer -= delta
	# Chakra charge — hold C
	if _charging:
		if current_chakra < max_chakra:
			_charge_accum += _charge_rate * delta
			if _charge_accum >= 1.0:
				var gained = int(_charge_accum)
				_charge_accum -= gained
				current_chakra = mini(max_chakra, current_chakra + gained)
				_update_hud()
		else:
			# Hit full chakra — stop
			_charge_accum = 0.0
			_stop_charge()
			var chat = get_tree().root.get_node_or_null("Main/Chat")
			if chat: chat.add_system_message("Chakra fully charged!")

	if not _chat_open():
		# Target lock — E cycles nearest, Escape releases
		if dialogue_open:
			return
		if settings_open:
			return
		if Input.is_action_just_pressed("target_lock"):
			_cycle_target()

		if Input.is_action_just_pressed("attack") and attack_timer <= 0 and not is_attacking:
			_do_attack()

		if Input.is_action_just_pressed("run"):
			is_running = !is_running
		# Chakra charge — hold C
		if Input.is_key_pressed(KEY_C):
			if not _charging and current_chakra < max_chakra:
				_start_charge()
			if is_dead:
				_stop_charge()
		elif _charging:
			_stop_charge()

		if Input.is_action_just_pressed("inventory"):
			if inventory != null:
				inventory.toggle()
			if equip_panel != null and inventory != null:
				equip_panel.visible = inventory.visible

		if Input.is_action_just_pressed("stat_panel") and stat_panel != null:
			stat_panel.toggle()

	# Auto-face locked target (always runs so lock releases cleanly)
	if locked_target != null and is_instance_valid(locked_target) and not is_attacking:
		_update_facing(locked_target.global_position - global_position)
	elif locked_target != null and not is_instance_valid(locked_target):
		_set_target(null)
	# Rotate attack debug vis to always face current attack direction
	if _debug_attack_vis and _debug_attack_vis.visible:
		var adir = get_attack_direction()
		_debug_attack_vis.rotation = adir.angle()
		if _attack_flash > 0:
			_attack_flash -= delta
			_debug_attack_vis.color = Color(1.0, 0.6, 0.0, 0.45)
		else:
			_debug_attack_vis.color = Color(1.0, 0.6, 0.0, 0.18)
	# Auto-drop target if: dead, out of range (20 tiles = 320px), or in different zone
	if locked_target != null and is_instance_valid(locked_target):
		var drop = false
		if "is_dead" in locked_target and locked_target.is_dead:
			drop = true
		if global_position.distance_to(locked_target.global_position) > 480.0:  # 30 tiles
			drop = true
		if drop:
			_set_target(null)

	var raw_input = _get_input()
	if raw_input != Vector2.ZERO and not is_attacking:
		_update_facing(raw_input)

	var current_step_rate = run_step_rate if is_running else walk_step_rate

	if is_stepping:
		var to_target  = target_pos - global_position
		var dist       = to_target.length()
		var slide_speed = tile_size / (current_step_rate * 0.9)
		if dist <= slide_speed * delta:
			global_position = target_pos
			grid_pos        = target_pos
			last_safe_pos   = grid_pos
			is_stepping     = false
			velocity        = Vector2.ZERO
			if not is_attacking:
				var input = _get_input()
				if input != Vector2.ZERO:
					_try_step(input, current_step_rate)
				else:
					_play_idle()
		else:
			velocity = to_target.normalized() * slide_speed
	else:
		step_timer -= delta
		if step_timer <= 0 and not is_attacking:
			var input = _get_input()
			if input != Vector2.ZERO:
				_try_step(input, current_step_rate)
			else:
				velocity = Vector2.ZERO
				_play_idle()

	move_and_slide()

func _chat_open() -> bool:
	return chat != null and chat.is_open()

func _get_input() -> Vector2:
	if _chat_open():
		return Vector2.ZERO
	var input := Vector2.ZERO
	# Opposing directions cancel — last-pressed wins by ignoring the opposite
	# if both are held simultaneously
	var right = Input.is_action_pressed("move_right")
	var left  = Input.is_action_pressed("move_left")
	var down  = Input.is_action_pressed("move_down")
	var up    = Input.is_action_pressed("move_up")
	# X axis: if both held, neither applies
	if right and not left:  input.x += 1
	elif left and not right: input.x -= 1
	# Y axis: if both held, neither applies
	if down and not up:   input.y += 1
	elif up and not down: input.y -= 1
	return input

func _update_facing(input: Vector2) -> void:
	var new_dir = facing_dir
	if input.x != 0 and input.y == 0:
		new_dir = "right" if input.x > 0 else "left"
	elif input.y != 0 and input.x == 0:
		new_dir = "down" if input.y > 0 else "up"
	else:
		if abs(input.x) >= abs(input.y):
			new_dir = "right" if input.x > 0 else "left"
		else:
			new_dir = "down" if input.y > 0 else "up"
	if new_dir != facing_dir:
		facing_dir = new_dir
		# Sync direction change to server immediately
		var net = get_node_or_null("/root/Network")
		if net and net.is_network_connected():
			net.send_facing.rpc_id(1, facing_dir)
		if not is_stepping:
			_play_idle()

func _try_step(input: Vector2, step_rate: float) -> void:
	_update_facing(input)
	var next_pos = grid_pos + Vector2(
		sign(input.x) * tile_size,
		sign(input.y) * tile_size
	)
	var space   = get_world_2d().direct_space_state
	var shape   = $CollisionShape2D.shape
	var query   = PhysicsShapeQueryParameters2D.new()
	query.shape           = shape
	query.transform       = Transform2D(0, next_pos)
	query.exclude         = [self]
	query.collision_mask  = collision_mask
	var results = space.intersect_shape(query)
	var blocked = false
	for r in results:
		if not r.collider.is_in_group("enemy"):
			blocked = true
			break
	if not blocked:
		target_pos  = next_pos
		is_stepping = true
		step_timer  = step_rate
		var net = get_node_or_null("/root/Network")
		if net != null and net.is_network_connected():
			net.send_position.rpc_id(1, next_pos)
		var walk_anim = "walk_" + facing_dir
		if $AnimatedSprite2D.animation != walk_anim:
			$AnimatedSprite2D.play(walk_anim)
			_cosm_play(walk_anim)

func _play_idle() -> void:
	var idle_anim = "idle_" + facing_dir
	if $AnimatedSprite2D.animation != idle_anim:
		$AnimatedSprite2D.play(idle_anim)
		_cosm_play(idle_anim)

# ------ DEBUG -------------------------------------------------------------------

func _build_attack_vis() -> void:
	# Visualises the server-side PvP hit box:
	#   forward: -8 to +48  (fwd > -8 and fwd < 48 in request_attack)
	#   lateral: ±52        (lat < 52)
	var poly           = Polygon2D.new()
	poly.name          = "AttackDebugVis"
	poly.z_index       = 60
	poly.visible       = false
	# Rectangle corners in local space (x = forward, y = lateral)
	# Will be rotated by set_polygon each frame to match attack direction
	poly.color         = Color(1.0, 0.6, 0.0, 0.18)  # orange, semi-transparent
	poly.polygon       = PackedVector2Array([
		Vector2(-8,  -28),
		Vector2(48,  -28),
		Vector2(48,   28),
		Vector2(-8,   28),
	])
	add_child(poly)
	_debug_attack_vis = poly
	# Outline — 4 edge lines via a second Polygon2D in outline mode
	var outline        = Polygon2D.new()
	outline.z_index    = 61
	outline.color      = Color(1.0, 0.6, 0.0, 0.85)
	outline.visible    = false
	outline.name       = "AttackDebugOutline"
	poly.add_child(outline)

func set_attack_debug(enabled: bool) -> void:
	_debug_enabled = enabled
	if _debug_attack_vis:
		_debug_attack_vis.visible = enabled

# ------ COMBAT ------------------------------------------------------------------

func get_attack_direction() -> Vector2:
	# Single source of truth for attack/ability direction.
	# Returns vector toward locked target, or facing direction as fallback.
	if locked_target != null and is_instance_valid(locked_target):
		return (locked_target.global_position - global_position).normalized()
	return _facing_vec()

func _do_attack() -> void:
	is_attacking = true
	attack_timer = attack_cooldown
	_attack_flash = 0.12  # briefly brighten the debug vis on swing
	var dir_vec = get_attack_direction()
	_update_facing(dir_vec)
	$AnimatedSprite2D.play("attack_" + facing_dir)
	_cosm_play("attack_" + facing_dir)
	# Lunge — slide forward, stop just short of any enemy in the way
	var lunge_dest = global_position + dir_vec * 50.0
	var space      = get_world_2d().direct_space_state
	var shape      = $CollisionShape2D.shape
	var query      = PhysicsShapeQueryParameters2D.new()
	query.shape          = shape
	query.exclude        = [self]
	query.collision_mask = collision_mask
	# Walk toward lunge destination in steps, stop when an enemy blocks
	var lunge_pos = global_position
	var step      = dir_vec * float(tile_size)
	var steps     = int(50.0 / float(tile_size)) + 1
	for i in range(steps):
		var candidate = _snap_to_grid(global_position + dir_vec * float(tile_size) * float(i + 1))
		if candidate.distance_to(global_position) > 50.0:
			break
		query.transform = Transform2D(0, candidate)
		var hits = space.intersect_shape(query)
		var hit_enemy = hits.any(func(r): return r.collider.is_in_group("enemy"))
		var hit_wall  = hits.any(func(r): return not r.collider.is_in_group("enemy"))
		if hit_wall:
			break  # wall — stop here
		if hit_enemy:
			break  # enemy in the way — stop just before it
		lunge_pos = candidate
	target_pos  = lunge_pos
	is_stepping = true
	step_timer  = attack_cooldown * 0.5
	var net = get_node_or_null("/root/Network")
	if net != null and net.is_network_connected():
		# Send actual visual position at time of attack — server uses this for hit check
		net.send_attack.rpc_id(1, dir_vec, global_position)
		# Also sync lunge destination so server position stays in step with client
		if lunge_pos != global_position:
			net.send_position.rpc_id(1, lunge_pos)

func _facing_vec() -> Vector2:
	match facing_dir:
		"up":    return Vector2.UP
		"down":  return Vector2.DOWN
		"left":  return Vector2.LEFT
		"right": return Vector2.RIGHT
	return Vector2.DOWN

func _on_animation_finished() -> void:
	if $AnimatedSprite2D.animation.begins_with("attack_"):
		is_attacking = false
		_play_idle()

func _sync_max_hp_to_server() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.send_max_hp.rpc_id(1, max_hp, current_hp)

func apply_stats(stats: Dictionary) -> void:
	stat_hp       = stats.hp
	stat_chakra   = stats.chakra
	stat_strength = stats.strength
	stat_dex      = stats.dex
	stat_int      = stats.int
	# stat_points intentionally NOT reset here — caller is responsible for setting it
	max_hp        = 100 + stat_hp * 5
	max_chakra    = 100 + stat_chakra * 3
	dodge_chance  = stat_dex * 0.002
	cd_reduction  = stat_dex * 0.001
	current_hp     = min(current_hp, max_hp)
	current_chakra = min(current_chakra, max_chakra)
	_sync_max_hp_to_server()
	_update_hud()

# ── Quest system ─────────────────────────────────────────────

func accept_quest_locally(quest_id: String) -> void:
	quest_state[quest_id] = {"status": "active", "progress": 0}
	var qdef = QuestDB.get_quest(quest_id)
	if not qdef.is_empty() and quest_hud:
		quest_hud.show_quest(quest_id, 0, qdef.get("required", 1))
	# System message in chat
	var chat = get_tree().root.get_node_or_null("Main/Chat")
	if chat and chat.has_method("add_system_message"):
		chat.add_system_message("[Quest] Accepted: " + qdef.get("title", quest_id))

func _on_quest_progress(quest_id: String, progress: int, required: int) -> void:
	if quest_state.has(quest_id):
		quest_state[quest_id]["progress"] = progress
	if quest_hud:
		if progress >= required:
			quest_hud.show_quest(quest_id, progress, required)
			quest_hud.mark_complete()
		else:
			quest_hud.show_quest(quest_id, progress, required)
	# System message
	var qdef = QuestDB.get_quest(quest_id)
	var target = qdef.get("target", "")
	var chat = get_tree().root.get_node_or_null("Main/Chat")
	if chat and chat.has_method("add_system_message"):
		if progress >= required:
			chat.add_system_message("[Quest] %s complete! Return to turn in." % qdef.get("title", quest_id))
		else:
			chat.add_system_message("[Quest] %s: %d/%d" % [target, progress, required])

func _on_quest_turned_in(quest_id: String, reward_xp: int, reward_gold: int) -> void:
	if quest_state.has(quest_id):
		quest_state[quest_id]["status"] = "turned_in"
	if quest_hud:
		quest_hud.hide_quest()
	# Gold float
	if reward_gold > 0:
		_spawn_damage_number(global_position + Vector2(0, -40), reward_gold, Color("ffd700"))
	var qdef = QuestDB.get_quest(quest_id)
	var chat = get_tree().root.get_node_or_null("Main/Chat")
	if chat and chat.has_method("add_system_message"):
		chat.add_system_message("[Quest] Completed: %s (+%d XP, +%d gold)" % [qdef.get("title", quest_id), reward_xp, reward_gold])

# ── Chakra charge ────────────────────────────────────────────

func _start_charge() -> void:
	_charging = true
	if _charge_particles == null:
		_charge_particles = CPUParticles2D.new()
		_charge_particles.z_index            = 8
		_charge_particles.one_shot           = false
		_charge_particles.emitting           = false
		_charge_particles.explosiveness      = 0.0
		_charge_particles.amount             = 24
		_charge_particles.lifetime           = 0.9
		_charge_particles.emission_shape     = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_charge_particles.emission_sphere_radius = 36.0
		_charge_particles.direction          = Vector2(0, -1)
		_charge_particles.spread             = 180.0
		_charge_particles.initial_velocity_min = 10.0
		_charge_particles.initial_velocity_max = 25.0
		# Negative radial accel pulls inward; tangential spins them around the player
		_charge_particles.radial_accel_min   = -60.0
		_charge_particles.radial_accel_max   = -40.0
		_charge_particles.tangential_accel_min = 90.0
		_charge_particles.tangential_accel_max = 140.0
		_charge_particles.gravity            = Vector2(0, 0)
		_charge_particles.scale_amount_min   = 0.3
		_charge_particles.scale_amount_max   = 0.65
		var grad = Gradient.new()
		grad.set_color(0, Color(0.4, 0.85, 1.0, 1.0))
		grad.add_point(1.0, Color(0.15, 0.35, 1.0, 0.0))
		_charge_particles.color_ramp         = grad
		add_child(_charge_particles)
	_charge_particles.emitting = true

func _stop_charge() -> void:
	_charging    = false
	_charge_accum = 0.0
	if _charge_particles:
		_charge_particles.emitting = false

func level_up() -> void:
	# Local stub — kept for compatibility. Real level-ups come from server via _on_level_up.
	pass

func _on_xp_gained(cur_exp: int, m_exp: int, amount: int) -> void:
	current_exp = cur_exp
	max_exp     = m_exp
	_update_hud()
	# Floating "+XP" number above player head
	_spawn_xp_number(amount)

func _on_level_up(new_level: int, cur_exp: int, m_exp: int, points: int, new_max_hp: int,
		str_: int, hp_: int, chakra_: int, dex_: int, int_: int) -> void:
	level         = new_level
	current_exp   = cur_exp
	max_exp       = m_exp
	stat_points   = points
	# Sync all stat values from server — prevents client drift
	stat_strength = str_
	stat_hp       = hp_
	stat_chakra   = chakra_
	stat_dex      = dex_
	stat_int      = int_
	# Server passively raises max_hp on level-up
	max_hp        = new_max_hp
	current_hp    = new_max_hp  # full heal
	_update_hud()
	if stat_panel != null:
		stat_panel.set_player(self)
	_show_level_up_effect()

func _on_enemy_killed(_xp: int, gold: int, item_drop: String) -> void:
	# Gold / item drop feedback — extend when inventory is built
	if gold > 0:
		_spawn_damage_number(global_position + Vector2(0, -30), gold, Color("ffd700"))
	if item_drop != "":
		var lbl = Label.new()
		lbl.text = "+ " + item_drop
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color("88ffcc"))
		lbl.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		get_tree().current_scene.add_child(lbl)
		lbl.global_position = global_position + Vector2(-20, -44)
		var tw = get_tree().create_tween()
		tw.tween_property(lbl, "position", lbl.position + Vector2(0, -28), 1.0)
		tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.0)
		tw.tween_callback(lbl.queue_free)

func _on_party_xp_shared(members: Array, amount: int) -> void:
	# Show a floating label for each party member that received shared XP
	var offset_y := 0
	for member_name in members:
		var lbl = Label.new()
		lbl.text = "[Party] %s +%d XP" % [member_name, amount]
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.2, 0.95, 0.35))  # party green
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		get_tree().current_scene.add_child(lbl)
		lbl.global_position = global_position + Vector2(-40, -50 + offset_y)
		var tw = get_tree().create_tween()
		tw.tween_property(lbl, "position", lbl.position + Vector2(0, -24), 1.2)
		tw.parallel().tween_interval(0.6)
		tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
		tw.tween_callback(lbl.queue_free)
		offset_y += 12


func _spawn_xp_number(amount: int) -> void:
	var lbl = Label.new()
	lbl.text = "+%d XP" % amount
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color("ffd700"))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	get_tree().current_scene.add_child(lbl)
	lbl.global_position = global_position + Vector2(-20, -66)
	var tw = get_tree().create_tween()
	tw.tween_property(lbl, "position", lbl.position + Vector2(0, -24), 1.2)
	tw.parallel().tween_interval(0.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(lbl.queue_free)

func _show_level_up_effect() -> void:
	# Particle burst — golden explosion around player
	ParticleBurst.spawn(get_tree(), global_position, "level_up")
	# Big "LEVEL UP!" label that rises and fades
	var lbl = Label.new()
	lbl.text = "LEVEL UP!"
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color("ffd700"))
	lbl.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	get_tree().current_scene.add_child(lbl)
	lbl.global_position = global_position + Vector2(-36, -60)
	var tw = get_tree().create_tween()
	tw.tween_property(lbl, "position", lbl.position + Vector2(0, -40), 1.8)
	tw.parallel().tween_interval(0.8)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tw.tween_callback(lbl.queue_free)

func _spawn_damage_number(pos: Vector2, amount: int, color: Color = Color("ffdd00")) -> void:
	var lbl = Label.new()
	lbl.text = str(amount)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	get_tree().current_scene.add_child(lbl)
	lbl.global_position = pos + Vector2(-8, -20)
	var tween = get_tree().create_tween()
	tween.tween_property(lbl, "position", lbl.position + Vector2(0, -24), 0.6)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
	tween.tween_callback(lbl.queue_free)

# ------ TAKE DAMAGE -------------------------------------------------------------

func start_hot(amount: int, interval: float, ticks: int) -> void:
	hot_amount   = amount
	hot_interval = interval
	hot_ticks    = ticks
	hot_timer    = 0.0

func _get_substitution() -> AbilityBase:
	if hotbar == null:
		return null
	for slot in hotbar.slots:
		if slot != null and slot is AbilitySubstitution:
			return slot
	return null

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO, kb_force: float = 0.0) -> void:
	if is_dead or invuln_ticks > 0:
		return
	var sub = _get_substitution()
	if sub != null and sub.is_primed:
		sub.try_substitute(self, global_position + knockback_dir * 60.0)
		return
	current_hp   = max(0, current_hp - amount)
	invuln_ticks = 0.6
	_spawn_damage_number(global_position, amount, Color("ff3333"))
	if kb_force > 0:
		var kb_target = _snap_to_grid(global_position + knockback_dir * tile_size * 2)
		var space     = get_world_2d().direct_space_state
		var shape     = $CollisionShape2D.shape
		var query     = PhysicsShapeQueryParameters2D.new()
		query.shape          = shape
		query.transform      = Transform2D(0, kb_target)
		query.exclude        = [self]
		query.collision_mask = collision_mask
		var results = space.intersect_shape(query)
		var blocked = results.any(func(r): return not r.collider.is_in_group("enemy"))
		if blocked:
			var kb_fallback = _snap_to_grid(global_position + knockback_dir * tile_size)
			query.transform  = Transform2D(0, kb_fallback)
			var results2     = space.intersect_shape(query)
			var blocked2     = results2.any(func(r): return not r.collider.is_in_group("enemy"))
			kb_target = global_position if blocked2 else kb_fallback
		target_pos  = kb_target
		grid_pos    = _snap_to_grid(global_position)
		is_stepping = true
		step_timer  = walk_step_rate * 0.5
		var net = get_node_or_null("/root/Network")
		if net and net.is_network_connected():
			net.send_position.rpc_id(1, kb_target)
	_update_hud()
	if current_hp <= 0:
		is_dead  = true
		modulate = Color(0.3, 0.3, 0.3)
		ParticleBurst.spawn(get_tree(), global_position, "death_player")
		_set_target(null)
		print("[CLIENT] Player died — waiting for server respawn signal")
		# Show respawn countdown overlay
		print("[CLIENT] Death: creating respawn screen")
		if respawn_screen == null:
			var script = load("res://scripts/respawn_screen.gd")
			if script == null:
				push_error("[CLIENT] respawn_screen.gd not found!")
			else:
				# MUST use CanvasLayer.new() — script extends CanvasLayer, not Node
				var rs = CanvasLayer.new()
				rs.set_script(script)
				var main = get_tree().root.get_node_or_null("Main")
				if main == null:
					push_error("[CLIENT] Main node not found for respawn screen!")
				else:
					main.add_child(rs)
					respawn_screen = rs
					print("[CLIENT] Respawn screen created OK")
		# Server controls respawn timing — sends sync_damage(0) when ready

# ------ TARGETING ---------------------------------------------------------------

func _cycle_target() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	# Merge enemies and remote players, sort by distance
	var all_nodes: Array = []
	for node in gs.get_sorted_enemy_nodes(global_position):
		all_nodes.append(node)
	for node in gs.remote_player_nodes.values():
		if is_instance_valid(node):
			all_nodes.append(node)
	all_nodes.sort_custom(func(a, b):
		return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position)
	)
	var candidates = all_nodes.slice(0, 3)
	if candidates.is_empty():
		_set_target(null)
		return
	var current_idx = -1
	for i in range(candidates.size()):
		if _node_target_id(candidates[i]) == locked_target_id:
			current_idx = i
			break
	var next_idx = (current_idx + 1) % candidates.size()
	_set_target(candidates[next_idx])

func _node_target_id(node: Node) -> String:
	if "enemy_id" in node:
		return node.enemy_id
	if "peer_id" in node:
		return "player_%d" % node.peer_id
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if not settings_open and not dialogue_open and not _chat_open():
				_open_settings()
				get_viewport().set_input_as_handled()

func _open_settings() -> void:
	if settings_open:
		return
	var script = load("res://scripts/settings_menu.gd")
	if script == null:
		return
	var menu = CanvasLayer.new()
	menu.set_script(script)
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	main.add_child(menu)
	settings_open = true
	# Hide all HUD while menu is open
	for ui in [hud, target_hud, chat, hotbar, minimap, party_hud, party_invite_popup]:
		if ui != null and is_instance_valid(ui):
			ui.visible = false
	menu.closed.connect(func():
		settings_open = false
		for ui in [hud, target_hud, chat, hotbar, minimap, party_hud, party_invite_popup]:
			if ui != null and is_instance_valid(ui):
				ui.visible = true
	)

func set_dialogue_open(open: bool) -> void:
	dialogue_open = open
	if open:
		_set_target(null)   # drop combat target while talking
	# Hide all HUD elements during dialogue
	for ui in [hud, target_hud, chat, hotbar, minimap, party_hud, party_invite_popup]:
		if ui != null and is_instance_valid(ui):
			ui.visible = not open

func _set_target(node: Node2D) -> void:
	if locked_target != null and is_instance_valid(locked_target):
		if locked_target.has_method("set_targeted"):
			locked_target.set_targeted(false)
	if node == null:
		locked_target    = null
		locked_target_id = ""
		if target_hud != null:
			target_hud.hide_hud()
		return
	locked_target    = node
	locked_target_id = _node_target_id(node)
	if node.has_method("set_targeted"):
		node.set_targeted(true)
	if target_hud != null:
		target_hud.set_target(node)

# ------ CHAT BUBBLE -------------------------------------------------------------

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

func _respawn() -> void:
	print("[CLIENT] _respawn() called — transitioning to village")
	current_hp     = max_hp
	current_chakra = max_chakra
	is_dead        = false
	invuln_ticks   = 2.0
	modulate       = Color(1, 1, 1)
	_set_target(null)
	_update_hud()
	# Clear respawn overlay
	print("[CLIENT] _respawn: clearing respawn screen (exists=%s)" % str(respawn_screen != null))
	if respawn_screen != null and is_instance_valid(respawn_screen):
		respawn_screen.queue_free()
		respawn_screen = null
	# BUG1 FIX: must match server village_spawn (40,40) — NOT Vector2.ZERO
	# Vector2.ZERO is outside village bounds and causes gray map + position desync
	const VILLAGE_SPAWN = Vector2(40.0, 40.0)
	# Respawn burst fires at the known village spawn — position not yet set so hardcode it
	ParticleBurst.spawn(get_tree(), VILLAGE_SPAWN, "respawn")
	# BUG4 FIX: confirm hp with server after respawn
	call_deferred("_sync_max_hp_to_server")
	var main = get_tree().root.get_node_or_null("Main")
	if main and main.has_method("transition_to_zone"):
		main.transition_to_zone("res://scenes/village.tscn", VILLAGE_SPAWN)
