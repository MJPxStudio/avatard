extends EnemyBase
class_name EnemyCaveBoss

# ============================================================
# CAVE BOSS — Telegraphed special attacks, 2-phase fight
# Special attacks: slam (AoE circle) and charge (line dash)
# Each special: windup → telegraph RPC → execute hit
# ============================================================

var _enraged:             bool  = false
var _phase2_done:         bool  = false
var _hp_sync_timer:       float = 0.0

var _special_timer:       float = 5.0
var _in_windup:           bool  = false
var _windup_timer:        float = 0.0
var _pending_attack:      String  = ""
var _pending_attack_pos:  Vector2 = Vector2.ZERO
var _pending_attack_size: Vector2 = Vector2.ZERO
var _pending_attack_dir:  Vector2 = Vector2.ZERO   # for charge rotation

const SPECIAL_INTERVAL_MIN = 4.0
const SPECIAL_INTERVAL_MAX = 7.0

const SLAM_RADIUS   = 65.0
const SLAM_DAMAGE   = 40
const SLAM_WINDUP   = 1.2

const CHARGE_WIDTH  = 32.0
const CHARGE_LENGTH = 220.0
const CHARGE_DAMAGE = 35
const CHARGE_WINDUP = 1.5

func _ready() -> void:
	enemy_name       = "Cave Troll"
	max_hp           = 300
	attack_damage    = 28
	attack_range     = 36.0
	attack_cooldown  = 1.8
	detection_radius = 160.0
	chase_radius     = 280.0
	move_speed       = 45.0
	xp_reward        = 200
	gold_reward      = 50
	drop_chance      = 1.0
	hitbox_size      = Vector2(20, 20)
	super._ready()
	for child in get_children():
		if child is ColorRect:
			child.size     = Vector2(20, 20)
			child.position = Vector2(-10, -10)
			child.color    = Color(0.15, 0.45, 0.15)
	_special_timer = randf_range(SPECIAL_INTERVAL_MIN, SPECIAL_INTERVAL_MAX)

func _physics_process(delta: float) -> void:
	_hp_sync_timer -= delta
	if _hp_sync_timer <= 0.0:
		_hp_sync_timer = 0.5
		_broadcast_hp()

	if not _phase2_done and hp <= max_hp / 2:
		_phase2_done = true
		_enter_phase2()

	# ── Windup block — boss frozen, ticking toward execution ──
	if _in_windup:
		_windup_timer -= delta
		state    = "windup"
		velocity = Vector2.ZERO
		if _windup_timer <= 0.0:
			# Reset state BEFORE execute so boss isn't stuck
			_in_windup = false
			state      = "aggro"
			_execute_special()
		move_and_slide()
		return

	# ── Special attack cooldown (only while actively chasing) ──
	if state == "aggro" and target != null:
		_special_timer -= delta
		if _special_timer <= 0.0:
			_special_timer = randf_range(
				SPECIAL_INTERVAL_MIN * (0.6 if _enraged else 1.0),
				SPECIAL_INTERVAL_MAX * (0.6 if _enraged else 1.0)
			)
			_begin_special()
			return

	super._physics_process(delta)

func _process_aggro(_delta: float) -> void:
	if target == null:
		return
	if target.is_immune or target.is_spinning:
		target = null
		state  = "return"
		return
	var to_target = target.world_pos - global_position
	var dist      = to_target.length()
	var speed     = move_speed * (1.3 if _enraged else 1.0)
	if dist > 120.0:
		speed *= 1.6
	if dist > attack_range:
		velocity = to_target.normalized() * speed
	else:
		velocity = Vector2.ZERO
		if attack_timer <= 0:
			attack_timer = attack_cooldown * (0.65 if _enraged else 1.0)
			_do_attack()
			if _enraged:
				_do_cleave()

# ── SPECIAL ATTACKS ────────────────────────────────────────

func _begin_special() -> void:
	if target == null or not is_instance_valid(target):
		return

	var dist_to_target = global_position.distance_to(target.world_pos)
	var attack_type    = "slam" if dist_to_target < 80.0 else "charge"
	if _enraged:
		attack_type = ["slam", "charge"][randi() % 2]

	var windup = SLAM_WINDUP if attack_type == "slam" else CHARGE_WINDUP

	if attack_type == "slam":
		_pending_attack_pos  = global_position
		_pending_attack_size = Vector2(SLAM_RADIUS, SLAM_RADIUS)
		_pending_attack_dir  = Vector2.ZERO

	elif attack_type == "charge":
		var predicted        = _predict_player_pos(windup)
		var dir              = (predicted - global_position).normalized()
		_pending_attack_pos  = global_position   # origin of charge
		_pending_attack_size = Vector2(CHARGE_WIDTH, CHARGE_LENGTH)
		_pending_attack_dir  = dir               # client uses this for rotation

	_pending_attack = attack_type
	_in_windup      = true
	_windup_timer   = windup

	_broadcast_telegraph(attack_type, _pending_attack_pos, _pending_attack_size, _pending_attack_dir, windup)
	print("[BOSS] %s beginning %s (windup=%.1fs)" % [enemy_name, attack_type, windup])

func _predict_player_pos(time_ahead: float) -> Vector2:
	if target == null:
		return global_position
	var cur_pos  = target.world_pos
	var prev_pos = target.get("prev_world_pos")
	if prev_pos == null or (prev_pos as Vector2) == Vector2.ZERO:
		return cur_pos
	var vel = (cur_pos - (prev_pos as Vector2)) * 20.0
	if vel.length() > 200.0:
		vel = vel.normalized() * 200.0
	return cur_pos + vel * time_ahead

func _execute_special() -> void:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return
	match _pending_attack:
		"slam":
			for pid in sm.server_players:
				var sp = sm.server_players[pid]
				if sp.zone != zone_name:
					continue
				if global_position.distance_to(sp.world_pos) <= SLAM_RADIUS:
					var kb = (sp.world_pos - global_position).normalized()
					sp.take_damage(SLAM_DAMAGE, kb, get_instance_id())
			print("[BOSS] Slam hit at %s" % str(global_position))

		"charge":
			# Move boss along charge direction, hit anything along the path
			var end_pos = _pending_attack_pos + _pending_attack_dir * CHARGE_LENGTH
			global_position = end_pos
			for pid in sm.server_players:
				var sp = sm.server_players[pid]
				if sp.zone != zone_name:
					continue
				# Check if player is within the charge rectangle
				var local = sp.world_pos - _pending_attack_pos
				var along = local.dot(_pending_attack_dir)
				var perp  = abs(local.dot(_pending_attack_dir.orthogonal()))
				if along >= 0 and along <= CHARGE_LENGTH and perp <= CHARGE_WIDTH:
					var kb = _pending_attack_dir
					sp.take_damage(CHARGE_DAMAGE, kb, get_instance_id())
			print("[BOSS] Charge landed at %s" % str(global_position))

func _broadcast_telegraph(attack_type: String, origin: Vector2, size: Vector2, dir: Vector2, windup: float) -> void:
	var net = get_tree().root.get_node_or_null("Network")
	var sm  = get_tree().root.get_node_or_null("ServerMain")
	if not net or not sm:
		return
	for pid in sm.server_players:
		var sp = sm.server_players[pid]
		if sp.zone == zone_name:
			net.boss_attack_telegraph.rpc_id(pid, enemy_id, attack_type, origin, size, dir, windup)

func _do_cleave() -> void:
	await get_tree().create_timer(0.35).timeout
	if not is_dead and target != null:
		_do_attack()

func _broadcast_hp() -> void:
	if is_dead:
		return
	var net = get_tree().root.get_node_or_null("Network")
	var sm  = get_tree().root.get_node_or_null("ServerMain")
	if net and sm:
		for pid in sm.server_players:
			var sp = sm.server_players[pid]
			if sp.zone == zone_name:
				net.notify_boss_hp.rpc_id(pid, hp, max_hp)

func _enter_phase2() -> void:
	_enraged   = true
	move_speed = 70.0
	var net = get_tree().root.get_node_or_null("Network")
	var sm  = get_tree().root.get_node_or_null("ServerMain")
	if net and sm:
		for pid in sm.server_players:
			var sp = sm.server_players[pid]
			if sp.zone == zone_name:
				net.notify_boss_phase.rpc_id(pid, enemy_name, 2, "ENRAGED!")
	print("[BOSS] %s entered phase 2 (enraged)" % enemy_name)
