extends EnemyBase
class_name EnemyRogueNinja

# ============================================================
# ROGUE NINJA — Ranged enemy, throws kunai projectiles
# Keeps distance from player, retreats if too close
# ============================================================

const PREFERRED_RANGE: float = 100.0
const RETREAT_RANGE:   float = 24.0   # Only flee when truly in melee range

func _ready() -> void:
	enemy_name       = "Rogue Ninja"
	max_hp           = 30
	attack_damage    = 18
	attack_range     = 130.0
	detection_radius = 150.0
	chase_radius     = 250.0
	move_speed       = 65.0
	attack_cooldown  = 2.0
	xp_reward        = 25
	gold_reward      = 8
	drop_chance      = 0.20
	hitbox_size      = Vector2(18, 18)   # Slightly larger hit target than base 14x14
	super._ready()

func _process_aggro(_delta: float) -> void:
	if target == null:
		return
	if target.is_immune or target.is_spinning:
		target = null
		state  = "return"
		return
	var to_target = (target.world_pos if "world_pos" in target else target.global_position) - global_position
	var dist      = to_target.length()

	if dist < RETREAT_RANGE:
		# Too close — back away
		velocity = -to_target.normalized() * move_speed
	elif dist > PREFERRED_RANGE:
		# Too far — move closer but not into melee
		velocity = to_target.normalized() * move_speed * 0.6
	else:
		# In preferred range — strafe sideways
		var perp = Vector2(-to_target.y, to_target.x).normalized()
		velocity = perp * move_speed * 0.4

	# Fire kunai if in range and off cooldown
	if dist <= attack_range and attack_timer <= 0:
		attack_timer = attack_cooldown
		_throw_kunai(to_target.normalized())

func _throw_kunai(direction: Vector2) -> void:
	if target == null or not is_instance_valid(target):
		return
	# Spawn server-side projectile
	var proj = Node2D.new()
	proj.set_script(load("res://scripts/kunai_projectile.gd"))
	proj.set_meta("damage",    attack_damage)
	proj.set_meta("direction", direction)
	proj.set_meta("owner_id",  get_instance_id())
	proj.set_meta("zone_name", zone_name)
	proj.global_position = global_position
	get_parent().add_child(proj)

func _do_attack() -> void:
	pass  # Attack handled by _throw_kunai in _process_aggro
