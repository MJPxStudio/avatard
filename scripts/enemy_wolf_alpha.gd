extends EnemyWolf
class_name EnemyWolfAlpha

# ============================================================
# ALPHA WOLF — Pack leader
#
# Unique ability: LEAP (triggers below 50% HP)
#   1. LEAP_WINDUP  — alpha crouches, danger zone shown at target (0.8s)
#   2. LEAP_AIR     — fast arc to locked landing position (0.35s)
#   3. LEAP_LAND    — AoE damage on arrival, brief pause (0.4s)
#
# Leap cooldown: 6s after landing before it can leap again
# ============================================================

const LEAP_WINDUP_TIME  = 0.8
const LEAP_AIR_TIME     = 0.35
const LEAP_LAND_TIME    = 0.4
const LEAP_SPEED        = 600.0
const LEAP_HIT_RADIUS   = 38.0
const LEAP_DAMAGE       = 28
const LEAP_COOLDOWN     = 3.5

enum LeapPhase { NONE, WINDUP, AIR, LAND }
var _leap_phase:      LeapPhase = LeapPhase.NONE
var _leap_timer:      float     = 0.0
var _leap_cooldown:   float     = 0.0
var _leap_target_pos: Vector2   = Vector2.ZERO
var _leap_dir:        Vector2   = Vector2.ZERO
var _enraged:         bool      = false
var _alpha_pack_called: bool    = false  # separate from _pack_called so being alerted by others doesn't block our own howl

func take_damage(amount: int, knockback_dir: Vector2, attacker_id = null) -> void:
	super.take_damage(amount, knockback_dir, attacker_id)
	if not _alpha_pack_called and not is_dead:
		_alpha_pack_called = true
		_call_pack(attacker_id)

func _ready() -> void:
	super._ready()
	enemy_name       = "Alpha Wolf"
	max_hp           = 70
	attack_damage    = 20
	attack_cooldown  = 2.0
	detection_radius = 150.0
	move_speed       = 85.0
	xp_reward        = 35
	gold_reward      = 8
	drop_chance      = 1.0
	scale            = Vector2(1.3, 1.3)
	hp               = max_hp

# ── Physics ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_leap_cooldown = max(0.0, _leap_cooldown - delta)

	# Leap phase takes full control
	if _leap_phase != LeapPhase.NONE:
		_process_leap_phase(delta)
		move_and_slide()
		return

	super._physics_process(delta)

# ── Enrage check + leap trigger ───────────────────────────────────────────────

func _process_aggro(delta: float) -> void:
	# Check enrage threshold
	if not _enraged and hp <= max_hp * 0.50:
		_enraged = true
		_announce_enrage()

	# Try to leap if enraged, cooled down, and target is far enough away
	if _enraged and _leap_cooldown <= 0.0 and _leap_phase == LeapPhase.NONE and _attack_phase == AttackPhase.NONE:
		if target != null and is_instance_valid(target):
			_begin_leap()
			return

	super._process_aggro(delta)

func _announce_enrage() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	var sm  = get_tree().root.get_node_or_null("ServerMain")
	if not net or not sm:
		return
	for pid in sm.server_players:
		if sm.server_players[pid].zone == zone_name:
			net.enemy_indicator.rpc_id(pid, enemy_id, "!!", 1.0, 0.15, 0.15)

# ── Leap ──────────────────────────────────────────────────────────────────────

func _begin_leap() -> void:
	if target == null or not is_instance_valid(target):
		return
	_leap_phase      = LeapPhase.WINDUP
	_leap_timer      = LEAP_WINDUP_TIME
	_leap_target_pos = target.world_pos   # lock destination at windup start
	_leap_dir        = (target.world_pos - global_position).normalized()
	velocity         = Vector2.ZERO
	_broadcast_leap_telegraph()

func _broadcast_leap_telegraph() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	var sm  = get_tree().root.get_node_or_null("ServerMain")
	if not net or not sm:
		return
	# Circular AoE at landing spot — use slam type so it shows as a circle
	# _build_slam_visual draws a box of (r*2 x r*2) where r = _size.x
	# so pass LEAP_HIT_RADIUS directly — the visual box will be HIT_RADIUS*2 wide
	var size = Vector2(LEAP_HIT_RADIUS, LEAP_HIT_RADIUS)
	for pid in sm.server_players:
		if sm.server_players[pid].zone == zone_name:
			net.boss_attack_telegraph.rpc_id(
				pid, enemy_id, "slam",
				_leap_target_pos, size,
				Vector2.ZERO, LEAP_WINDUP_TIME
			)

func _process_leap_phase(delta: float) -> void:
	_leap_timer -= delta

	match _leap_phase:
		LeapPhase.WINDUP:
			velocity = Vector2.ZERO
			if _leap_timer <= 0.0:
				_leap_phase = LeapPhase.AIR
				_leap_timer = LEAP_AIR_TIME

		LeapPhase.AIR:
			velocity = _leap_dir * LEAP_SPEED
			# Land early if we've reached or passed the target position —
			# avoids flying straight through the danger zone
			var to_target = _leap_target_pos - global_position
			var arrived   = to_target.dot(_leap_dir) <= 0.0 or _leap_timer <= 0.0
			if arrived:
				global_position = _leap_target_pos
				velocity        = Vector2.ZERO
				_do_leap_land()
				_leap_phase = LeapPhase.LAND
				_leap_timer = LEAP_LAND_TIME

		LeapPhase.LAND:
			velocity = Vector2.ZERO
			if _leap_timer <= 0.0:
				_leap_phase    = LeapPhase.NONE
				_leap_cooldown = LEAP_COOLDOWN

func _do_leap_land() -> void:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return
	# Rectangular hit check — matches the square danger zone visual exactly.
	# _leap_target_pos is the center; LEAP_HIT_RADIUS is the half-width.
	for pid in sm.server_players:
		var sp = sm.server_players[pid]
		if sp.zone != zone_name:
			continue
		var delta = sp.world_pos - _leap_target_pos
		if abs(delta.x) <= LEAP_HIT_RADIUS and abs(delta.y) <= LEAP_HIT_RADIUS:
			var kb = delta.normalized()
			if kb == Vector2.ZERO:
				kb = Vector2(randf() - 0.5, randf() - 0.5).normalized()
			sp.take_damage(LEAP_DAMAGE, kb, get_instance_id())

# ── Return complete ──────────────────────────────────────────────────────────

func _on_return_complete() -> void:
	super._on_return_complete()
	_alpha_pack_called = false
	_enraged           = false
	_leap_phase        = LeapPhase.NONE
	_leap_cooldown     = 0.0

# ── Pack call (red ! override) ────────────────────────────────────────────────

func _call_pack(_attacker_id) -> void:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return
	var aggro_target: Node = target
	if aggro_target == null:
		return

	var net = get_tree().root.get_node_or_null("Network")

	if net:
		for pid in sm.server_players:
			if sm.server_players[pid].zone == zone_name:
				net.enemy_indicator.rpc_id(pid, enemy_id, "!", 1.0, 0.15, 0.15)

	var alerted: Array = []
	for id in sm._enemy_nodes:
		var other = sm._enemy_nodes[id]
		if not is_instance_valid(other) or other == self:
			continue
		if not (other is EnemyWolf):
			continue
		if other.zone_name != zone_name or other.is_dead:
			continue
		if other.state == "aggro":
			continue
		if other.hp <= other.max_hp * 0.30:
			continue
		var dist = global_position.distance_to(other.global_position)
		if dist <= 550.0:
			other.chase_radius = PACK_CHASE_RADIUS
			other.target       = aggro_target
			other.state        = "aggro"
			other._pack_called = true
			other._fleeing     = false
			if net:
				for pid in sm.server_players:
					if sm.server_players[pid].zone == zone_name:
						net.enemy_indicator.rpc_id(pid, id, "?", 0.9, 0.9, 1.0)
			print("[ALPHA] Pack call: %s alerted %s" % [enemy_id, id])
			alerted.append(other)

	_assign_flank_angles(alerted)
