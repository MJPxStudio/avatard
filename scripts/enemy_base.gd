extends CharacterBody2D
class_name EnemyBase

# ============================================================
# ENEMY BASE — Server-side. enemy_id is a stable String.
# On death, notifies ServerMain.on_enemy_died() for respawn.
# ============================================================

@export var enemy_name:       String  = "Enemy"
@export var zone_name:        String  = "open_world"
@export var max_hp:           int     = 50
@export var detection_radius: float   = 120.0
@export var chase_radius:     float   = 200.0
@export var attack_range:     float   = 32.0
@export var attack_damage:    int     = 10
@export var attack_cooldown:  float   = 1.5
@export var move_speed:       float   = 60.0
@export var xp_reward:        int     = 20
@export var gold_reward:      int     = 5
@export var drop_chance:      float   = 0.15

var enemy_id:      String  = ""       # Set by server_main, e.g. "wolf_0"
var level:         int     = 1
var stagger_timer: float  = 0.0       # When > 0, movement frozen (hit stagger)
var hitbox_size:   Vector2 = Vector2(14, 14)
var hp:            int     = 50
var is_dead:       bool    = false
var spawn_point:   Vector2 = Vector2.ZERO
var target:        Node    = null
var _last_attacker: Node    = null   # most recent player to deal damage — becomes new target
var state:         String  = "idle"
var attack_timer:  float   = 0.0
var wander_timer:  float   = 0.0
var wander_target: Vector2 = Vector2.ZERO

const WANDER_RADIUS   = 40.0
const WANDER_INTERVAL = 3.0

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("enemy_" + zone_name)
	hp            = max_hp
	spawn_point   = global_position
	wander_target = global_position
	_setup_collision()

func _setup_collision() -> void:
	var shape   = CollisionShape2D.new()
	var rect    = RectangleShape2D.new()
	rect.size   = Vector2(14, 14)
	shape.shape = rect
	add_child(shape)
	collision_layer = 4
	collision_mask  = 5   # 1 = player, 4 = other enemies
	var vis      = ColorRect.new()
	vis.size     = Vector2(14, 14)
	vis.position = Vector2(-7, -7)
	vis.color    = Color("e74c3c") if enemy_name == "Wolf" else Color("8e44ad")
	vis.z_index  = 2
	add_child(vis)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	attack_timer -= delta
	if stagger_timer > 0:
		stagger_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_update_state()
	_process_state(delta)
	move_and_slide()

func _update_state() -> void:
	match state:
		"idle", "return":
			var nearest = _find_nearest_player()
			if nearest != null:
				target = nearest
				state  = "aggro"
		"aggro":
			if target == null or not is_instance_valid(target):
				state  = "return"
				target = null
				return
			# Drop target if they've zoned out — prevents cross-zone damage
			if target.zone != zone_name:
				state  = "return"
				target = null
				return
			var dist = global_position.distance_to(target.world_pos)
			if dist > chase_radius:
				state  = "return"
				target = null

func _process_state(delta: float) -> void:
	match state:
		"idle":   _process_idle(delta)
		"aggro":  _process_aggro(delta)
		"return": _process_return(delta)

func _process_idle(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0:
		wander_timer  = WANDER_INTERVAL
		var angle     = randf() * TAU
		wander_target = spawn_point + Vector2(cos(angle), sin(angle)) * randf_range(0, WANDER_RADIUS)
	var to_wander = wander_target - global_position
	if to_wander.length() > 4.0:
		velocity = to_wander.normalized() * move_speed * 0.4
	else:
		velocity = Vector2.ZERO

func _process_aggro(_delta: float) -> void:
	if target == null:
		return
	var target_pos = target.world_pos
	var to_target  = target_pos - global_position
	var dist       = to_target.length()
	if dist > attack_range:
		velocity = to_target.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
		if attack_timer <= 0:
			attack_timer = attack_cooldown
			_do_attack()

func _process_return(_delta: float) -> void:
	var to_spawn = spawn_point - global_position
	if to_spawn.length() > 8.0:
		velocity = to_spawn.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
		state    = "idle"
		_on_return_complete()

func _on_return_complete() -> void:
	# Override in subclasses to change reset behavior
	hp = max_hp

func _telegraph_attack() -> void:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return
	for peer_id in sm.server_players:
		var sp = sm.server_players[peer_id]
		if sp.zone == zone_name:
			Network.enemy_telegraph.rpc_id(peer_id, enemy_id)

func _do_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.zone != zone_name:
		target = null
		state  = "return"
		return
	# Distance guard — only deal damage if still physically in range
	if global_position.distance_to(target.world_pos) > attack_range * 1.2:
		return
	var kb_dir = (target.world_pos - global_position).normalized()
	target.take_damage(attack_damage, kb_dir, get_instance_id())

func _find_nearest_player() -> Node:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return null
	var nearest:      Node  = null
	var nearest_dist: float = detection_radius
	for pid in sm.server_players:
		var sp = sm.server_players[pid]
		if not is_instance_valid(sp):
			continue
		if sp.zone != zone_name:
			continue
		var dist = global_position.distance_to(sp.world_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest      = sp
	return nearest

func take_damage(amount: int, knockback_dir: Vector2, attacker_id = null) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	stagger_timer = 0.3   # Freeze movement briefly on hit
	if attacker_id != null:
		var net = get_tree().root.get_node_or_null("Network")
		var sm  = get_tree().root.get_node_or_null("ServerMain")
		if net and sm:
			for pid in sm.server_players:
				var sp = sm.server_players[pid]
				if sp.get_instance_id() == attacker_id:
					net.confirm_hit.rpc_id(pid, global_position, amount)
					# Switch aggro to whoever just hit us
					if sp.zone == zone_name and sp != target:
						target = sp
						state  = "aggro"
					break
	if hp <= 0:
		_die(attacker_id)

func _die(killer_id = null) -> void:
	is_dead = true
	if killer_id != null:
		_give_rewards(killer_id)
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm and sm.has_method("on_enemy_died"):
		sm.on_enemy_died(enemy_id, spawn_point, get_script().resource_path, zone_name)
	await get_tree().create_timer(0.5).timeout
	queue_free()

func _give_rewards(killer_instance_id) -> void:
	var net = get_tree().root.get_node_or_null("Network")
	var sm  = get_tree().root.get_node_or_null("ServerMain")
	if net == null or sm == null:
		return
	# Find killer peer id from instance id
	var killer_peer_id = -1
	for pid in sm.server_players:
		if sm.server_players[pid].get_instance_id() == killer_instance_id:
			killer_peer_id = pid
			break
	if killer_peer_id == -1:
		return
	var item_drop = ""
	if randf() < drop_chance:
		item_drop = _roll_item_drop()
	# Build list of XP recipients: killer + party members in same zone
	var recipients: Array = [killer_peer_id]
	if sm._party_in_party.has(killer_peer_id):
		var party_id = sm._party_in_party[killer_peer_id]
		for pid in sm._party_parties[party_id]["members"]:
			if pid != killer_peer_id and sm.server_players.has(pid):
				if sm.server_players[pid].zone == sm.server_players[killer_peer_id].zone:
					recipients.append(pid)
	# Shared XP: full reward to killer, half to party members nearby
	for pid in recipients:
		var sp = sm.server_players.get(pid, null)
		if sp == null:
			continue
		var share = xp_reward if pid == killer_peer_id else xp_reward / 2
		sp.grant_xp(share)
		sp.kills += 1 if pid == killer_peer_id else 0
		# Track kill quest progress for the killer only
		if pid == killer_peer_id:
			sp.check_kill_quest(enemy_name)
	# Notify killer of party members who received shared XP
	if recipients.size() > 1:
		var shared_names: Array = []
		for pid in recipients:
			if pid != killer_peer_id and sm.server_players.has(pid):
				shared_names.append(sm.server_players[pid].username)
		if not shared_names.is_empty():
			net.notify_party_xp_shared.rpc_id(killer_peer_id, shared_names, xp_reward / 2)
	# Item drop only goes to killer
	net.notify_enemy_killed.rpc_id(killer_peer_id, xp_reward, gold_reward, item_drop)

func _roll_item_drop() -> String:
	var rolls = ["potion", "kunai", "scroll"]
	return rolls[randi() % rolls.size()]
