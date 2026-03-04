extends CharacterBody2D

# ============================================================
# PLAYER --- Grid-snapped step movement + combat
# ============================================================

# Grid tuning
@export var tile_size:      int   = 16     # pixels per tile --- all movement snaps to this
@export var walk_step_rate: float = 0.14   # seconds between steps (walking)
@export var run_step_rate:  float = 0.08   # seconds between steps (running)   # seconds between steps (walking)

# Combat tuning
@export var attack_damage:    int   = 15
@export var attack_range:     float = 28.0
@export var attack_width:     float = 24.0
@export var attack_cooldown:  float = 0.4
@export var attack_knockback: float = 120.0

var is_running:   bool   = false
var is_dead:      bool   = false
var invuln_ticks: float  = 0.0
var facing_dir:   String = "down"

# Grid movement
var grid_pos:      Vector2   # current tile position (in world pixels, snapped)
var target_pos:    Vector2   # tile we're moving toward
var is_stepping:   bool  = false
var step_timer:    float = 0.0
var last_safe_pos: Vector2

# Combat state
var attack_timer:  float = 0.0
var is_attacking:  bool  = false

# Stats
var max_hp:         int = 100
var current_hp:     int = 100
var max_chakra:     int = 100
var current_chakra: int = 100
var level:          int = 1
var current_exp:    int = 0
var max_exp:        int = 100

# HUD reference
var hud = null
# Inventory reference
var inventory = null
# Hotbar reference
var hotbar = null
# Base stats
var stat_hp:       int = 5
var stat_chakra:   int = 5
var stat_strength: int = 5
var stat_dex:      int = 5
var stat_int:      int = 5
var stat_points:   int = 0  # unspent points

# Derived stats (recalculated on apply_stats)
var dodge_chance:     float = 0.0   # 0.2% per dex
var cd_reduction:     float = 0.0   # 0.1% per dex

# Equip panel reference
var equip_panel = null
# Stat panel reference
var stat_panel = null

# Bleed
var bleed_ticks:  int   = 0
var bleed_damage: int   = 2
var bleed_timer:  float = 0.0

func _ready() -> void:
	# Snap starting position to grid
	grid_pos = _snap_to_grid(global_position)
	target_pos = grid_pos
	global_position = grid_pos
	last_safe_pos = grid_pos

	_build_animations()
	$AnimatedSprite2D.play("idle_down")
	_update_hud()
	$AnimatedSprite2D.animation_finished.connect(_on_animation_finished)

func connect_network_signals() -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs and not gs.damage_received.is_connected(_on_server_damage):
		gs.damage_received.connect(_on_server_damage)
	var net = get_tree().root.get_node_or_null("Network")
	if net and not net.hit_confirmed.is_connected(_on_hit_confirmed):
		net.hit_confirmed.connect(_on_hit_confirmed)

func _on_server_damage(amount: int, knockback_dir: Vector2) -> void:
	take_damage(amount, knockback_dir, 120.0)

func _on_hit_confirmed(hit_pos: Vector2, amount: int) -> void:
	_spawn_damage_number(hit_pos, amount)

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
	var sf := SpriteFrames.new()
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

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Invuln flash
	if invuln_ticks > 0:
		invuln_ticks -= delta
		modulate.a = 0.4 if fmod(invuln_ticks, 0.12) < 0.06 else 1.0
		if invuln_ticks <= 0:
			invuln_ticks = 0
			modulate.a = 1.0

	# Bleed tick
	if bleed_ticks > 0:
		bleed_timer -= delta
		if bleed_timer <= 0.0:
			bleed_timer = 1.0
			take_damage(bleed_damage, Vector2.ZERO)
			bleed_ticks -= 1

	# Attack cooldown
	if attack_timer > 0:
		attack_timer -= delta

	# Attack input
	if Input.is_action_just_pressed("attack") and attack_timer <= 0 and not is_attacking:
		_do_attack()

	# Run toggle
	if Input.is_action_just_pressed("run"):
		is_running = !is_running

	# Inventory + equip panel toggle together
	if Input.is_action_just_pressed("inventory"):
		if inventory != null:
			inventory.toggle()
		if equip_panel != null:
			equip_panel.visible = inventory.visible

	# Stat panel toggle
	if Input.is_action_just_pressed("stat_panel") and stat_panel != null:
		stat_panel.toggle()

	# Update facing instantly on any directional input --- don't wait for step
	var raw_input = _get_input()
	if raw_input != Vector2.ZERO and not is_attacking:
		_update_facing(raw_input)

	var current_step_rate = run_step_rate if is_running else walk_step_rate

	# ------ GRID MOVEMENT ------
	if is_stepping:
		# Fixed speed slide toward target tile
		var to_target = target_pos - global_position
		var dist = to_target.length()
		var slide_speed = tile_size / (current_step_rate * 0.9)

		if dist <= slide_speed * delta:
			global_position = target_pos
			grid_pos = target_pos
			last_safe_pos = grid_pos
			is_stepping = false
			velocity = Vector2.ZERO

			# Immediately chain next step if direction still held
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

func _get_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_action_pressed("move_right"): input.x += 1
	if Input.is_action_pressed("move_left"):  input.x -= 1
	if Input.is_action_pressed("move_up"):    input.y -= 1
	if Input.is_action_pressed("move_down"):  input.y += 1
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
		# Update idle animation immediately when turning while still
		if not is_stepping:
			_play_idle()

func _try_step(input: Vector2, step_rate: float) -> void:
	_update_facing(input)

	# Calculate next grid position --- each axis moves one full tile
	var next_pos = grid_pos + Vector2(
		sign(input.x) * tile_size,
		sign(input.y) * tile_size
	)

	# Test if target tile is clear using a shape cast
	var space = get_world_2d().direct_space_state
	var shape = $CollisionShape2D.shape
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, next_pos)
	query.exclude = [self]
	query.collision_mask = collision_mask
	var results = space.intersect_shape(query)

	# Filter out enemies --- only block on walls
	var blocked = false
	for r in results:
		if not r.collider.is_in_group("enemy"):
			blocked = true
			break

	if not blocked:
		target_pos = next_pos
		is_stepping = true
		step_timer = step_rate

		# Send step to server
		var net = get_node_or_null("/root/Network")
		if net != null and net.is_network_connected():
			net.send_step.rpc_id(1, input)

		var walk_anim = "walk_" + facing_dir
		if $AnimatedSprite2D.animation != walk_anim:
			$AnimatedSprite2D.play(walk_anim)

func _play_idle() -> void:
	var idle_anim = "idle_" + facing_dir
	if $AnimatedSprite2D.animation != idle_anim:
		$AnimatedSprite2D.play(idle_anim)

# ------ COMBAT ------------------------------------------------------------------------------------------------------------------------------------------------------

func _do_attack() -> void:
	is_attacking = true
	attack_timer = attack_cooldown
	$AnimatedSprite2D.play("attack_" + facing_dir)
	var dir_vec := _facing_vec()

	# Send attack to server for authoritative hit detection
	var net = get_node_or_null("/root/Network")
	if net != null and net.is_network_connected():
		net.send_attack.rpc_id(1, dir_vec)

	# Local hit detection vs enemies (wolf AI etc)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var to_enemy = enemy.global_position - global_position
		var forward_dist = to_enemy.dot(dir_vec)
		var lateral_dist = abs(to_enemy.dot(Vector2(-dir_vec.y, dir_vec.x)))
		if forward_dist > 0 and forward_dist < attack_range * 1.5 and lateral_dist < attack_width:
			if enemy.has_method("take_damage"):
				enemy.take_damage(attack_damage, dir_vec, attack_knockback)
				_spawn_damage_number(enemy.global_position, attack_damage)

func _facing_vec() -> Vector2:
	match facing_dir:
		"up":    return Vector2.UP
		"down":  return Vector2.DOWN
		"left":  return Vector2.LEFT
		"right": return Vector2.RIGHT
	return Vector2.DOWN

func apply_stats(stats: Dictionary) -> void:
	stat_hp       = stats.hp
	stat_chakra   = stats.chakra
	stat_strength = stats.strength
	stat_dex      = stats.dex
	stat_int      = stats.int
	stat_points   = 0

	# Recalculate derived stats
	max_hp     = 100 + stat_hp * 5
	max_chakra = 100 + stat_chakra * 3
	dodge_chance  = stat_dex * 0.002
	cd_reduction  = stat_dex * 0.001

	# Clamp current values
	current_hp     = min(current_hp, max_hp)
	current_chakra = min(current_chakra, max_chakra)
	_update_hud()

func level_up() -> void:
	level += 1
	stat_points += 3
	max_exp = int(max_exp * 1.5)
	current_exp = 0
	_update_hud()
	if stat_panel != null:
		stat_panel.set_player(self)

func _on_animation_finished() -> void:
	if $AnimatedSprite2D.animation.begins_with("attack_"):
		is_attacking = false
		_play_idle()

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

# ------ TAKE DAMAGE ---------------------------------------------------------------------------------------------------------------------------------------

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO, kb_force: float = 0.0) -> void:
	if is_dead or invuln_ticks > 0:
		return
	current_hp = max(0, current_hp - amount)
	invuln_ticks = 0.6
	_spawn_damage_number(global_position, amount, Color("ff3333"))
	if kb_force > 0:
		# Step 2 tiles in knockback direction smoothly
		var kb_target = _snap_to_grid(global_position + knockback_dir * tile_size * 2)
		var space = get_world_2d().direct_space_state
		var shape = $CollisionShape2D.shape
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0, kb_target)
		query.exclude = [self]
		query.collision_mask = collision_mask
		var results = space.intersect_shape(query)
		var blocked = results.any(func(r): return not r.collider.is_in_group("enemy"))
		if blocked:
			kb_target = _snap_to_grid(global_position + knockback_dir * tile_size)
		target_pos = kb_target
		grid_pos = _snap_to_grid(global_position)
		is_stepping = true
		step_timer = walk_step_rate * 0.5
	_update_hud()
	if current_hp <= 0:
		is_dead = true
		modulate = Color(0.3, 0.3, 0.3)
