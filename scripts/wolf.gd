extends CharacterBody2D

# ============================================================
# WOLF ENEMY --- Grid-based movement + AI states
# ============================================================

# Grid tuning --- should match player tile_size
@export var tile_size:       int   = 16
@export var walk_step_rate:  float = 0.18   # seconds between steps (slower than player)
@export var charge_speed:    float = 240.0  # charge lunge speed (stays velocity-based)

# Combat tuning
@export var detect_range:    float = 200.0
@export var chase_range:     float = 300.0
@export var strafe_range:    float = 80.0
@export var charge_cooldown: float = 4.0
@export var charge_windup:   float = 0.5
@export var charge_duration: float = 0.4
@export var charge_damage:   int   = 12
@export var knockback_force: float = 160.0
@export var max_hp:          int   = 60
@export var patrol_radius:   float = 120.0

# State machine
enum State { PATROL, CHASE, STRAFE, WINDUP, CHARGE, COOLDOWN, DEAD }
var state: State = State.PATROL

# Grid movement
var grid_pos:    Vector2
var target_pos:  Vector2
var is_stepping: bool  = false
var step_timer:  float = 0.0

# Internal vars
var current_hp:      int
var player: Node2D = null
var spawn_pos:       Vector2
var patrol_target:   Vector2
var patrol_timer:    float = 0.0
var strafe_dir:      int   = 1
var strafe_timer:    float = 0.0
var charge_cd_timer: float = 0.0
var charge_timer:    float = 0.0
var charge_dir:      Vector2 = Vector2.ZERO
var charge_hit:      bool = false

# Bleed
var bleed_ticks:  int   = 0
var bleed_damage: int   = 2
var bleed_timer:  float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	current_hp = max_hp
	spawn_pos = global_position
	grid_pos = _snap_to_grid(global_position)
	target_pos = grid_pos
	global_position = grid_pos
	_new_patrol_target()
	player = get_tree().get_first_node_in_group("player")
	collision_layer = 2
	collision_mask = 3  # hits layer 1 (walls) and layer 2 (players/enemies)

func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / tile_size) * tile_size,
		round(pos.y / tile_size) * tile_size
	)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Bleed tick
	if bleed_ticks > 0:
		bleed_timer -= delta
		if bleed_timer <= 0.0:
			bleed_timer = 1.0
			take_damage(bleed_damage, Vector2.ZERO)
			bleed_ticks -= 1

	# Charge cooldown
	if charge_cd_timer > 0:
		charge_cd_timer -= delta

	match state:
		State.WINDUP:  _state_windup(delta)
		State.CHARGE:  _state_charge(delta)
		State.COOLDOWN: _state_cooldown(delta)
		_:
			# All other states use grid stepping
			_run_grid_state(delta)

	move_and_slide()
	_after_slide()

func _run_grid_state(delta: float) -> void:
	if is_stepping:
		# Slide toward target
		var to_target = target_pos - global_position
		var dist = to_target.length()
		var slide_speed = tile_size / (walk_step_rate * 0.9)

		if dist <= slide_speed * delta:
			global_position = target_pos
			grid_pos = target_pos
			is_stepping = false
			velocity = Vector2.ZERO
			# Immediately run AI to chain next step
			_run_ai_state(delta)
		else:
			velocity = to_target.normalized() * slide_speed
	else:
		step_timer -= delta
		if step_timer <= 0:
			_run_ai_state(delta)

func _try_step(dir: Vector2) -> bool:
	if dir == Vector2.ZERO:
		return false

	var next_pos = grid_pos + Vector2(
		sign(dir.x) * tile_size,
		sign(dir.y) * tile_size
	)

	# Check if tile is clear --- skip on server if no collision shape
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node != null and shape_node.shape != null:
		var space = get_world_2d().direct_space_state
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape_node.shape
		query.transform = Transform2D(0, next_pos)
		query.exclude = [self]
		query.collision_mask = collision_mask
		var results = space.intersect_shape(query)
		for r in results:
			if not r.collider.is_in_group("enemy") and not r.collider.is_in_group("player"):
				return false

	target_pos = next_pos
	is_stepping = true
	step_timer = walk_step_rate
	return true

# ------ AI STATES ---------------------------------------------------------------------------------------------------------------------------------------------

func _run_ai_state(delta: float) -> void:
	match state:
		State.PATROL:  _state_patrol()
		State.CHASE:   _state_chase()
		State.STRAFE:  _state_strafe()

func _state_patrol() -> void:
	# Check for player
	if player and global_position.distance_to(player.global_position) < detect_range:
		state = State.CHASE
		return

	patrol_timer -= walk_step_rate
	if patrol_timer <= 0 or global_position.distance_to(patrol_target) < tile_size:
		_new_patrol_target()
		return

	var dir = (patrol_target - global_position).normalized()
	_try_step(_best_grid_dir(dir))

func _new_patrol_target() -> void:
	patrol_target = _snap_to_grid(spawn_pos + Vector2(
		randf_range(-patrol_radius, patrol_radius),
		randf_range(-patrol_radius, patrol_radius)
	))
	patrol_timer = randf_range(2.0, 5.0)
	step_timer = walk_step_rate

func _state_chase() -> void:
	if not player:
		state = State.PATROL
		return

	var dist = global_position.distance_to(player.global_position)

	if dist > chase_range:
		state = State.PATROL
		return

	if dist < strafe_range * 1.5:
		state = State.STRAFE
		strafe_timer = randf_range(1.0, 2.5)
		return

	var dir = (player.global_position - global_position).normalized()
	_try_step(_best_grid_dir(dir))
	step_timer = walk_step_rate

func _state_strafe() -> void:
	if not player:
		state = State.PATROL
		return

	var dist = global_position.distance_to(player.global_position)

	if dist > strafe_range * 2.5:
		state = State.CHASE
		return

	strafe_timer -= walk_step_rate
	if strafe_timer <= 0:
		strafe_dir *= -1
		strafe_timer = randf_range(1.0, 2.5)

	# Start charge if ready
	if charge_cd_timer <= 0 and dist < strafe_range * 1.5:
		_begin_windup()
		return

	var to_player = (player.global_position - global_position).normalized()
	var perp = Vector2(-to_player.y, to_player.x) * strafe_dir
	var dist_correction = (dist - strafe_range) / strafe_range
	var move_dir = (to_player * dist_correction + perp).normalized()
	_try_step(_best_grid_dir(move_dir))
	step_timer = walk_step_rate

# ------ BEST GRID DIRECTION ---------------------------------------------------------------------------------------------------------------
# Converts a world direction into the best 8-directional grid step

func _best_grid_dir(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return Vector2.ZERO
	# Round to nearest 8-direction
	var angle = dir.angle()
	var snapped = round(angle / (PI / 4.0)) * (PI / 4.0)
	return Vector2(cos(snapped), sin(snapped))

# ------ CHARGE (stays velocity-based) ---------------------------------------------------------------------------------

func _begin_windup() -> void:
	state = State.WINDUP
	charge_timer = charge_windup
	charge_dir = (player.global_position - global_position).normalized()
	velocity = Vector2.ZERO
	is_stepping = false

func _state_windup(delta: float) -> void:
	charge_timer -= delta
	queue_redraw()
	if charge_timer <= 0:
		queue_redraw()
		_begin_charge()

func _begin_charge() -> void:
	state = State.CHARGE
	charge_timer = charge_duration
	charge_hit = false
	velocity = charge_dir * charge_speed

func _state_charge(delta: float) -> void:
	charge_timer -= delta

	if not charge_hit:
		for i in get_slide_collision_count():
			var collider = get_slide_collision(i).get_collider()
			if collider != null and collider.is_in_group("player"):
				player = collider
				_hit_player()
				charge_hit = true
				_end_charge()
				return

	if charge_timer <= 0:
		_end_charge()

func _end_charge() -> void:
	state = State.COOLDOWN
	charge_cd_timer = charge_cooldown
	charge_timer = 0.6
	velocity *= 0.1
	# Snap back to grid after charge
	grid_pos = _snap_to_grid(global_position)
	global_position = grid_pos
	target_pos = grid_pos

func _state_cooldown(delta: float) -> void:
	velocity *= 0.85
	charge_timer -= delta
	if charge_timer <= 0:
		if player and global_position.distance_to(player.global_position) < chase_range:
			state = State.STRAFE
			strafe_timer = randf_range(1.0, 2.0)
		else:
			state = State.PATROL

# ------ HIT PLAYER ------------------------------------------------------------------------------------------------------------------------------------------

func _hit_player() -> void:
	if not player or player.is_dead:
		return
	if player.has_method("take_damage"):
		player.take_damage(charge_damage, charge_dir, knockback_force)
	if "bleed_ticks" in player:
		player.bleed_ticks = 2
		player.bleed_damage = bleed_damage
		player.bleed_timer = 1.0

# ------ TAKE DAMAGE ---------------------------------------------------------------------------------------------------------------------------------------

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO, kb_force: float = 0.0) -> void:
	if state == State.DEAD:
		return
	current_hp -= amount
	if kb_force > 0:
		# Step 2 tiles in knockback direction smoothly
		var kb_tiles = 2
		var kb_target = _snap_to_grid(global_position + knockback_dir * tile_size * kb_tiles)
		# Check if clear, fall back 1 tile if not
		var space = get_world_2d().direct_space_state
		var shape = $CollisionShape2D.shape
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0, kb_target)
		query.exclude = [self]
		query.collision_mask = collision_mask
		var results = space.intersect_shape(query)
		var blocked = results.any(func(r): return not r.collider.is_in_group("player") and not r.collider.is_in_group("enemy"))
		if blocked:
			kb_target = _snap_to_grid(global_position + knockback_dir * tile_size)
		target_pos = kb_target
		grid_pos = _snap_to_grid(global_position)
		is_stepping = true
		step_timer = walk_step_rate * 0.5

	modulate = Color(1, 0.3, 0.3)
	await get_tree().create_timer(0.1).timeout
	if state != State.DEAD:
		modulate = Color(1, 1, 1)

	if current_hp <= 0:
		_die()
	elif state == State.PATROL:
		state = State.CHASE

func _die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	modulate = Color(0.3, 0.3, 0.3)
	await get_tree().create_timer(1.0).timeout
	queue_free()

# ------ STOP PUSHING PLAYER ---------------------------------------------------------------------------------------------------------------

func _after_slide() -> void:
	if state != State.CHARGE and state != State.WINDUP:
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_collider() == player:
				velocity = Vector2.ZERO
				break

# ------ TELEGRAPH ---------------------------------------------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if state != State.WINDUP or player == null:
		return
	var length = 80.0
	var end = charge_dir * length
	draw_line(Vector2.ZERO, end, Color(1, 0.1, 0.1, 0.8), 3.0)
	draw_circle(end, 5.0, Color(1, 0.1, 0.1, 0.8))
	draw_line(Vector2.ZERO, end, Color(1, 0.5, 0.0, 0.4), 6.0)
