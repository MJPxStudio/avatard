extends EnemyBase
class_name EnemyWolf

# ============================================================
# WOLF — Pack animal with proper attack commitment
#
# Attack sequence:
#   1. WINDUP  — wolf stops, crouches briefly (0.25s)
#   2. LUNGE   — fast dash toward player's position (0.25s)
#   3. HIT     — damage check at end of lunge (strict distance)
#   4. RECOVER — brief pause before resuming orbit (0.3s)
#
# Circling: orbit outside CIRCLE_RADIUS, approach to attack range
# Pack:     first hit alerts nearby wolves, spread at flank angles
# ============================================================

const PACK_CALL_RADIUS    = 350.0
const PACK_CHASE_RADIUS   = 700.0
const NORMAL_CHASE_RADIUS = 700.0
const CIRCLE_RADIUS       = 80.0
const MAX_ORBIT_WOLVES    = 2

const WINDUP_TIME   = 0.25
const LUNGE_TIME    = 0.25
const RECOVER_TIME  = 0.3
const LUNGE_SPEED   = 320.0
const HIT_RADIUS    = 40.0

var _pack_called:    bool    = false
var _fleeing:        bool    = false
var _flank_angle:    float   = 0.0
var _strafe_dir:     float   = 1.0
var _strafe_timer:   float   = 0.0

enum AttackPhase { NONE, WINDUP, LUNGE, RECOVER }
var _attack_phase:       AttackPhase = AttackPhase.NONE
var _attack_timer_local: float       = 0.0
var _lunge_dir:          Vector2     = Vector2.ZERO
var _lunge_origin:       Vector2     = Vector2.ZERO

func _ready() -> void:
	enemy_name       = "Wolf"
	max_hp           = 40
	attack_damage    = 12
	attack_range     = 28.0
	attack_cooldown  = 2.2
	detection_radius = 100.0
	chase_radius     = NORMAL_CHASE_RADIUS
	move_speed       = 75.0
	xp_reward        = 15
	gold_reward      = 3
	drop_chance      = 0.10
	super._ready()

# ── Damage ────────────────────────────────────────────────────────────────────

func take_damage(amount: int, knockback_dir: Vector2, attacker_id = null) -> void:
	super.take_damage(amount, knockback_dir, attacker_id)
	if _attack_phase == AttackPhase.WINDUP or _attack_phase == AttackPhase.LUNGE:
		_attack_phase       = AttackPhase.RECOVER
		_attack_timer_local = RECOVER_TIME
		velocity            = Vector2.ZERO
	if not _pack_called and not is_dead:
		_pack_called  = true
		chase_radius  = PACK_CHASE_RADIUS
		_call_pack(attacker_id)

# ── Pack call ─────────────────────────────────────────────────────────────────

func _call_pack(_attacker_id) -> void:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return
	# target is already switched to the attacker by base take_damage
	var aggro_target: Node = target
	if aggro_target == null:
		return

	var net = get_tree().root.get_node_or_null("Network")

	# Show "!" on the howling wolf
	if net:
		for pid in sm.server_players:
			if sm.server_players[pid].zone == zone_name:
				net.enemy_indicator.rpc_id(pid, enemy_id, "!", 1.0, 0.85, 0.0)

	# Alert nearby idle wolves
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
		var dist = global_position.distance_to(other.global_position)
		if dist <= PACK_CALL_RADIUS and other.hp > other.max_hp * 0.30:
			other.chase_radius = PACK_CHASE_RADIUS
			other.target       = aggro_target
			other.state        = "aggro"
			other._pack_called = true
			other._fleeing     = false   # clear any active flee so _update_state doesn't override
			if net:
				for pid in sm.server_players:
					if sm.server_players[pid].zone == zone_name:
						net.enemy_indicator.rpc_id(pid, id, "?", 0.9, 0.9, 1.0)
			print("[WOLF] Pack call: %s alerted %s" % [enemy_id, id])
			alerted.append(other)

	_assign_flank_angles(alerted)

func _assign_flank_angles(wolves: Array) -> void:
	# Spread wolves across ±75° max — never enough to send anyone backward
	var count = wolves.size()
	_flank_angle = 0.0
	if count == 0:
		return
	var spread = deg_to_rad(75.0)
	for i in range(count):
		var t = float(i) / float(count)  # 0.0 to <1.0
		wolves[i]._flank_angle = lerp(-spread, spread, t) if count > 1 else 0.0

# ── Physics ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if _attack_phase != AttackPhase.NONE:
		_process_attack_phase(delta)
		move_and_slide()
		return
	super._physics_process(delta)

# ── State overrides ───────────────────────────────────────────────────────────

func _update_state() -> void:
	if _fleeing:
		if state == "idle":
			_fleeing = false
		return
	super._update_state()

func _process_aggro(delta: float) -> void:
	if target == null:
		return
	if hp <= max_hp * 0.20:
		_attack_phase = AttackPhase.NONE
		_fleeing      = true
		state         = "return"
		target        = null
		return
	var to_target = target.world_pos - global_position
	var dist      = to_target.length()

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.2, 2.5)
		_strafe_dir   = 1.0 if randf() > 0.5 else -1.0

	if dist > CIRCLE_RADIUS:
		# Direct approach at long range, blend into flank angle only near orbit
		var base_approach = to_target.normalized()
		var flanked       = base_approach.rotated(_flank_angle)
		var blend         = clampf(1.0 - (dist - CIRCLE_RADIUS) / 200.0, 0.0, 1.0)
		var approach      = base_approach.lerp(flanked, blend).normalized()
		var strafe        = Vector2(-approach.y, approach.x) * _strafe_dir
		var strafe_weight = clampf(1.0 - (dist - CIRCLE_RADIUS) / 100.0, 0.0, 0.65)
		velocity = (approach + strafe * strafe_weight).normalized() * move_speed

	elif dist > 40.0:
		if _count_orbiting_wolves() < MAX_ORBIT_WOLVES:
			var approach = to_target.normalized()
			var orbit    = Vector2(-approach.y, approach.x) * _strafe_dir
			velocity = orbit * move_speed * 0.7
			if attack_timer <= 0:
				attack_timer = attack_cooldown
				_begin_attack(to_target.normalized())
		else:
			# Orbit full — hold position at CIRCLE_RADIUS + 40px, strafe slowly
			var approach  = to_target.normalized()
			var hold_dist = CIRCLE_RADIUS + 40.0
			if dist < hold_dist:
				velocity = -approach * move_speed * 0.3
			elif dist > hold_dist + 30.0:
				velocity = approach * move_speed * 0.3
			else:
				var strafe = Vector2(-approach.y, approach.x) * _strafe_dir
				velocity = strafe * move_speed * 0.4
	else:
		velocity = -to_target.normalized() * move_speed * 0.8

func _on_return_complete() -> void:
	_pack_called  = false
	_fleeing      = false   # clear on arrival regardless of HP
	chase_radius  = NORMAL_CHASE_RADIUS
	_attack_phase = AttackPhase.NONE

func _process_return(_delta: float) -> void:
	if _fleeing:
		var sm = get_tree().root.get_node_or_null("ServerMain")
		var nearest: Node   = null
		var nearest_dist: float = 200.0
		if sm:
			for pid in sm.server_players:
				var sp = sm.server_players[pid]
				if sp.zone != zone_name:
					continue
				var d = global_position.distance_to(sp.world_pos)
				if d < nearest_dist:
					nearest_dist = d
					nearest      = sp
		if nearest != null:
			var away_from_player = (global_position - nearest.world_pos).normalized()
			var toward_spawn     = (spawn_point - global_position)
			var spawn_dist       = toward_spawn.length()
			var spawn_bias       = clampf(spawn_dist / 300.0, 0.0, 1.0)
			var flee_dir         = (away_from_player + toward_spawn.normalized() * spawn_bias).normalized()
			velocity = flee_dir * move_speed * 0.9
			move_and_slide()
			return
	super._process_return(_delta)

# ── Attack helpers ────────────────────────────────────────────────────────────

func _count_orbiting_wolves() -> int:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return 0
	var count = 0
	for id in sm._enemy_nodes:
		var other = sm._enemy_nodes[id]
		if not is_instance_valid(other) or other == self:
			continue
		if not (other is EnemyWolf) or other.is_dead:
			continue
		if other.zone_name != zone_name or other.target != target:
			continue
		if other.state != "aggro":
			continue
		var d = other.global_position.distance_to(target.world_pos)
		if d <= CIRCLE_RADIUS and d > 40.0:
			count += 1
	return count

func _begin_attack(dir: Vector2) -> void:
	_attack_phase       = AttackPhase.WINDUP
	_attack_timer_local = WINDUP_TIME
	_lunge_dir          = dir
	_lunge_origin       = global_position
	velocity            = Vector2.ZERO
	_broadcast_lunge_telegraph(dir)

func _broadcast_lunge_telegraph(dir: Vector2) -> void:
	var net = get_tree().root.get_node_or_null("Network")
	var sm  = get_tree().root.get_node_or_null("ServerMain")
	if not net or not sm:
		return
	var size = Vector2(18.0, LUNGE_SPEED * LUNGE_TIME)
	for pid in sm.server_players:
		var sp = sm.server_players[pid]
		if sp.zone == zone_name:
			net.boss_attack_telegraph.rpc_id(pid, enemy_id, "charge", global_position, size, dir, WINDUP_TIME)

func _process_attack_phase(delta: float) -> void:
	_attack_timer_local -= delta

	match _attack_phase:
		AttackPhase.WINDUP:
			velocity = Vector2.ZERO
			if _attack_timer_local <= 0.0:
				_attack_phase       = AttackPhase.LUNGE
				_attack_timer_local = LUNGE_TIME
				if target != null and is_instance_valid(target):
					_lunge_dir = (target.world_pos - global_position).normalized()

		AttackPhase.LUNGE:
			velocity = _lunge_dir * LUNGE_SPEED
			if _attack_timer_local <= 0.0:
				_do_lunge_hit()
				_attack_phase       = AttackPhase.RECOVER
				_attack_timer_local = RECOVER_TIME
				velocity            = Vector2.ZERO

		AttackPhase.RECOVER:
			velocity = Vector2.ZERO
			if _attack_timer_local <= 0.0:
				_attack_phase = AttackPhase.NONE

func _do_lunge_hit() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.zone != zone_name:
		return
	var dist = global_position.distance_to(target.world_pos)
	if dist <= HIT_RADIUS:
		target.take_damage(attack_damage, _lunge_dir, get_instance_id())
		var net = get_tree().root.get_node_or_null("Network")
		var sm  = get_tree().root.get_node_or_null("ServerMain")
		if net and sm:
			for pid in sm.server_players:
				if sm.server_players[pid] == target:
					net.confirm_hit.rpc_id(pid, global_position, attack_damage)
					break
