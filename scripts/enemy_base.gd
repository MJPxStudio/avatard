extends CharacterBody2D
class_name EnemyBase

# ============================================================
# ENEMY BASE — Server-side. Pixel movement via velocity.
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

var enemy_id:      String  = ""
var level:         int     = 1
var stagger_timer: float   = 0.0
var hitbox_size:   Vector2 = Vector2(14, 14)
var hp:            int     = 50
var is_dead:       bool    = false
var spawn_point:   Vector2 = Vector2.ZERO
var target:        Node    = null
var state:         String  = "idle"
var attack_timer:  float   = 0.0
var wander_timer:  float   = 0.0
var wander_target: Vector2 = Vector2.ZERO
var _spawn_grace:  float   = 2.5   # seconds before enemy can detect/aggro — covers entrance walk

const WANDER_RADIUS   = 40.0
const WANDER_INTERVAL = 3.0

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("enemy_" + zone_name)
	hp            = max_hp
	spawn_point   = global_position
	wander_target = global_position
	_setup_collision()

func apply_dungeon_scaling(hp_mult: float, dmg_mult: float, speed_mult: float, aggro_mult: float) -> void:
	max_hp           = int(max_hp * hp_mult)
	hp               = max_hp
	attack_damage    = int(attack_damage * dmg_mult)
	move_speed       = move_speed * speed_mult
	attack_cooldown  = max(0.5, attack_cooldown / aggro_mult)   # higher aggro = faster attacks
	detection_radius = detection_radius * min(aggro_mult, 2.0)  # wider detection

func _setup_collision() -> void:
	var shape   = CollisionShape2D.new()
	var rect    = RectangleShape2D.new()
	rect.size   = Vector2(14, 14)
	shape.shape = rect
	add_child(shape)
	collision_layer = 4
	collision_mask  = 5
	var vis      = ColorRect.new()
	vis.size     = Vector2(14, 14)
	vis.position = Vector2(-7, -7)
	vis.color    = Color("e74c3c") if enemy_name == "Wolf" else Color("8e44ad")
	vis.z_index  = 2
	add_child(vis)

var is_rooted:       bool  = false
var knockback_timer: float = 0.0
var is_immune:       bool  = false
var _root_timer:     float = 0.0
var _dot_damage:     int   = 0
var _dot_ticks_left: int   = 0
var _dot_interval:   float = 1.0
var _dot_timer:      float = 0.0
var _dot_caster_peer: int  = 0

func apply_root(duration: float) -> void:
	is_rooted   = true
	_root_timer = duration

func apply_dot(damage: int, interval: float, ticks: int, caster_peer: int = 0) -> void:
	_dot_damage       = damage
	_dot_interval     = interval
	_dot_ticks_left   = ticks
	_dot_timer        = interval
	_dot_caster_peer  = caster_peer

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if knockback_timer > 0.0:
		knockback_timer -= delta
	if _dot_ticks_left > 0:
		_dot_timer -= delta
		if _dot_timer <= 0.0:
			_dot_timer = _dot_interval
			var _dot_attacker_id = null
			if _dot_caster_peer > 0:
				var _sm = get_tree().root.get_node_or_null("ServerMain")
				if _sm and _sm.server_players.has(_dot_caster_peer):
					_dot_attacker_id = _sm.server_players[_dot_caster_peer].get_instance_id()
				var net = get_tree().root.get_node_or_null("Network")
				if net:
					net.confirm_ability_hit.rpc_id(_dot_caster_peer, global_position, _dot_damage)
					net.ability_visual.rpc(enemy_id, "strangle")
			take_damage(_dot_damage, Vector2.ZERO, _dot_attacker_id)
			_dot_ticks_left -= 1
	if is_rooted:
		_root_timer -= delta
		if _root_timer <= 0.0:
			is_rooted = false
		velocity = Vector2.ZERO
		move_and_slide()
		return
	attack_timer -= delta
	if _spawn_grace > 0.0:
		_spawn_grace -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if stagger_timer > 0:
		stagger_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_update_state()
	_process_state(delta)
	move_and_slide()
	# Clamp to dungeon floor bounds when in an instanced dungeon zone
	if zone_name.count("_") >= 2:  # e.g. "wolf_den_1"
		# Get bounds from the active floor controller so they match the current room size
		var d_hw := 360.0
		var d_hh := 216.0
		var sm = get_tree().root.get_node_or_null("ServerMain")
		if sm and sm._dungeon_manager:
			var inst_id = sm._dungeon_manager.get_instance_id_for_zone(zone_name)
			if inst_id >= 0:
				var fc = sm._dungeon_manager._floor_controllers.get(inst_id, null)
				if fc:
					var r = fc._floor_layout.get("rooms", {}).get(fc._current_room_id, {})
					if not r.is_empty():
						const TILE_S   = 32
						const WALL_T   = 2
						var tw = r.get("tiles_w", 28)
						var th = r.get("tiles_h", 19)
						d_hw = float(tw * TILE_S / 2 - WALL_T * TILE_S - 8)
						d_hh = float(th * TILE_S / 2 - WALL_T * TILE_S - 8)
		global_position = Vector2(
			clamp(global_position.x, -d_hw, d_hw),
			clamp(global_position.y, -d_hh, d_hh)
		)

func _update_state() -> void:
	match state:
		"idle", "return":
			var nearest = _find_nearest_player()
			if nearest != null:
				print("[ENEMY %s] detected %s dist=%.1f" % [enemy_id, nearest.username, global_position.distance_to(nearest.world_pos)])
				target = nearest
				state  = "aggro"
		"aggro":
			if target == null or not is_instance_valid(target):
				state  = "return"
				target = null
				return
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
	if target.is_immune or target.is_spinning:
		target = null
		state  = "return"
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
		if sp.is_immune or sp.is_spinning or sp.is_ghost:
			continue
		var dist = global_position.distance_to(sp.world_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest      = sp
	return nearest

func take_damage(amount: int, knockback_dir: Vector2, attacker_id = null) -> void:
	if is_dead or is_immune:
		return
	hp = max(0, hp - amount)
	stagger_timer = 0.3
	if knockback_dir != Vector2.ZERO:
		var sm = get_tree().root.get_node_or_null("ServerMain")
		if sm and sm.has_method("cancel_shadows_for_enemy"):
			sm.cancel_shadows_for_enemy(self)
	if attacker_id != null:
		var net = get_tree().root.get_node_or_null("Network")
		var sm  = get_tree().root.get_node_or_null("ServerMain")
		if net and sm:
			for pid in sm.server_players:
				var sp = sm.server_players[pid]
				if sp.get_instance_id() == attacker_id:
					net.confirm_hit.rpc_id(pid, global_position, amount)
					if sp.zone == zone_name and sp != target:
						target = sp
						state  = "aggro"
					break
	var net_hf = get_tree().root.get_node_or_null("Network")
	var sm_hf  = get_tree().root.get_node_or_null("ServerMain")
	if net_hf and sm_hf:
		for pid in sm_hf.server_players:
			if sm_hf.server_players[pid].zone == zone_name:
				net_hf.enemy_hit_flash.rpc_id(pid, enemy_id)
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
	var recipients: Array = [killer_peer_id]
	if sm._party_in_party.has(killer_peer_id):
		var party_id = sm._party_in_party[killer_peer_id]
		for pid in sm._party_parties[party_id]["members"]:
			if pid != killer_peer_id and sm.server_players.has(pid):
				if sm.server_players[pid].zone == sm.server_players[killer_peer_id].zone:
					recipients.append(pid)
	for pid in recipients:
		var sp = sm.server_players.get(pid, null)
		if sp == null:
			continue
		var share = xp_reward if pid == killer_peer_id else xp_reward / 2
		sp.grant_xp(share)
		sp.kills += 1 if pid == killer_peer_id else 0
		if pid == killer_peer_id:
			sp.check_kill_quest(enemy_name)
	if recipients.size() > 1:
		var shared_names: Array = []
		for pid in recipients:
			if pid != killer_peer_id and sm.server_players.has(pid):
				shared_names.append(sm.server_players[pid].username)
		if not shared_names.is_empty():
			net.notify_party_xp_shared.rpc_id(killer_peer_id, shared_names, xp_reward / 2)
	var killer_sp = sm.server_players.get(killer_peer_id, null)
	if killer_sp:
		if gold_reward > 0:
			killer_sp.grant_gold(gold_reward)
		if item_drop != "":
			killer_sp.grant_item(item_drop, 1)
		if killer_sp.active_mission != "" and killer_sp.mission_data.get("type") == "kill":
			if killer_sp.mission_data.get("enemy_name", "") == enemy_name:
				var required = killer_sp.mission_data.get("required", 1)
				if killer_sp.mission_progress < required:
					killer_sp.mission_progress += 1
					var net_m = get_tree().root.get_node_or_null("Network")
					if net_m:
						net_m.mission_progress_update.rpc_id(killer_peer_id, killer_sp.mission_progress, required)
	net.notify_enemy_killed.rpc_id(killer_peer_id, xp_reward, gold_reward, item_drop)

func _roll_item_drop() -> String:
	var rolls = ["potion", "kunai", "scroll"]
	return rolls[randi() % rolls.size()]
