extends Node

const QuestDB      = preload("res://scripts/quest_db.gd")
const ServerProjectile = preload("res://scripts/server/server_projectile.gd")
const ServerClayOwl    = preload("res://scripts/server/server_clay_owl.gd")
const ServerClayBomb   = preload("res://scripts/server/server_clay_bomb.gd")
const DungeonData  = preload("res://scripts/dungeon_data.gd")
const DungeonMgr   = preload("res://scripts/dungeon_manager.gd")

# ============================================================
# SERVER MAIN
# Enemies spawned once at startup with stable string IDs.
# Respawn handled via timer queue — no spawner nodes.
# ============================================================

const SYNC_RATE:       float = 0.05
const ENEMY_SYNC_RATE: float = 0.05
const RESPAWN_TIME:    float = 30.0
const TILE_SIZE:       float = 16.0
const SEPARATION_DIST: float = 12.0  # push players apart if closer than this

var server_players:   Dictionary = {}

# ── Party state (inlined) ─────────────────────────────────────
var _party_parties:  Dictionary = {}   # party_id -> { leader, members[] }
var _party_in_party: Dictionary = {}   # peer_id  -> party_id
var _party_next_id:  int        = 1
var _dungeon_manager: Node       = null
var _enemy_nodes:     Dictionary = {}   # "wolf_0" -> Node
var _shadow_nodes:    Dictionary = {}   # shadow_id -> ServerShadow
var _trap_nodes:      Dictionary = {}   # trap_id   -> ServerTrapBase
var _respawn_queue:   Array      = []   # [{id, script, pos, zone, timer}]
var _projectiles:       Array      = []   # active ServerProjectile instances (stepped each _process)
var _clay_spider_counter: int        = 0    # incremented per spider cast for unique IDs
var _clay_spider_projs:   Dictionary = {}   # spider_id -> proj — Kagura hook
var _clay_owl_counter:    int        = 0    # unique owl IDs
var _clay_owls:           Dictionary = {}   # owl_id -> ServerClayOwl
var _clay_bomb_counter:   int        = 0    # unique bomb IDs
var _clay_bombs:          Dictionary = {}   # bomb_id -> ServerClayBomb
var _c4_swarms:           Dictionary = {}   # swarm_id -> {timer, positions, zone, peer_id}
var _c4_counter:          int        = 0
var sync_timer:       float      = 0.0
var enemy_sync_timer: float      = 0.0

const ENEMY_DEFS = [
	{id="wolf_0",       script="res://scripts/enemy_wolf.gd",       zone="open_world", pos=Vector2(-200, 1400)},
	{id="wolf_1",       script="res://scripts/enemy_wolf.gd",       zone="open_world", pos=Vector2( 200, 1400)},
	{id="wolf_alpha_0", script="res://scripts/enemy_wolf_alpha.gd",  zone="open_world", pos=Vector2(   0, 1250)},
	{id="wolf_2",       script="res://scripts/enemy_wolf.gd",       zone="open_world", pos=Vector2(-400, 1100)},
	{id="wolf_3",       script="res://scripts/enemy_wolf.gd",       zone="open_world", pos=Vector2( 400, 1100)},
	{id="wolf_4",       script="res://scripts/enemy_wolf.gd",       zone="open_world", pos=Vector2(-150,  900)},
	{id="wolf_5",       script="res://scripts/enemy_wolf.gd",       zone="open_world", pos=Vector2( 150,  900)},
	{id="wolf_alpha_1", script="res://scripts/enemy_wolf_alpha.gd",  zone="open_world", pos=Vector2(   0, 1000)},
	{id="ninja_0", script="res://scripts/enemy_rogue_ninja.gd", zone="open_world", pos=Vector2(-350, 1300)},
	{id="ninja_1", script="res://scripts/enemy_rogue_ninja.gd", zone="open_world", pos=Vector2( 350, 1200)},
	{id="ninja_2", script="res://scripts/enemy_rogue_ninja.gd", zone="open_world", pos=Vector2(-100, 1000)},
	{id="ninja_3", script="res://scripts/enemy_rogue_ninja.gd", zone="open_world", pos=Vector2( 100,  850)},
	{id="ninja_4", script="res://scripts/enemy_rogue_ninja.gd", zone="open_world", pos=Vector2(-500,  700)},
]

func _ready() -> void:
	print("[SERVER] Starting...")
	name = "ServerMain"
	# Run boon pipeline self-test before anything else
	load("res://scripts/dungeon_boon_test.gd").run()
	Network.launch_as_server()
	Network.login_request_received.connect(_on_login_request)
	Network.player_disconnected.connect(_on_player_disconnected)
	Network.attack_received.connect(_on_attack)
	Network.zone_changed.connect(_on_zone_changed)
	Network.party_invite_sent.connect(_on_party_invite_sent)
	Network.party_response_received.connect(_on_party_response)
	Network.party_leave_received.connect(_on_party_leave)
	Network.party_kick_received.connect(_on_party_kick)
	Network.party_promote_received.connect(_on_party_promote)

	Network.position_received.connect(_on_position_received)
	Network.facing_received.connect(_on_facing_received)
	Network.target_update_received.connect(_on_target_update_received)
	Network.ability_used_received.connect(_on_ability_used)
	Network.equip_update_received.connect(_on_equip_update)
	Network.character_creation_received.connect(_on_character_creation)
	Network.mission_accept_requested.connect(_on_mission_accept)
	Network.mission_abandon_requested.connect(_on_mission_abandon)
	Network.mission_complete_requested.connect(_on_mission_complete)
	Network.mission_board_requested.connect(_on_mission_board_request)
	Network.escort_started_server.connect(_on_escort_started)
	Network.escort_completed_server.connect(_on_escort_completed)
	Network.training_complete_server.connect(_on_training_complete)
	Network.item_used_received.connect(_on_item_used)
	Network.hotbar_loadout_received.connect(_on_hotbar_loadout)
	Network.appearance_update_received.connect(_on_appearance_update)
	Network.dungeon_enter_requested.connect(_on_dungeon_enter_requested)
	Network.dungeon_exit_requested.connect(_on_dungeon_exit_requested)
	Network.dungeon_ready_check_requested.connect(_on_ready_check_requested)
	Network.dungeon_player_ready.connect(_on_player_ready)
	Network.dungeon_cancel_ready.connect(_on_cancel_ready)
	_dungeon_manager = DungeonMgr.new()
	_dungeon_manager.server_players = server_players
	add_child(_dungeon_manager)
	Network.spend_stats_server.connect(_on_spend_stats)
	Network.quest_accept_received.connect(_on_quest_accept)
	Network.quest_complete_received.connect(_on_quest_complete)
	Network.chat_received_server.connect(_on_chat)
	Network.max_hp_received.connect(_on_max_hp)
	for def in ENEMY_DEFS:
		_spawn_enemy(def.id, def.script, def.pos, def.zone)

func _spawn_enemy(id: String, script_path: String, pos: Vector2, zone: String) -> void:
	var script = load(script_path)
	if script == null:
		push_error("[SERVER] Cannot load: %s" % script_path)
		return
	var enemy          = CharacterBody2D.new()
	enemy.set_script(script)
	enemy.zone_name    = zone
	enemy.enemy_id     = id
	add_child(enemy)
	enemy.global_position = pos
	enemy.spawn_point     = pos
	enemy.wander_target   = pos
	_enemy_nodes[id]      = enemy
	print("[SERVER] Spawned %s at %s" % [id, pos])

func spawn_dungeon_enemy(id: String, script_path: String, pos: Vector2, zone: String, hp_mult: float = 1.0, dmg_mult: float = 1.0, speed_mult: float = 1.0, aggro_mult: float = 1.0) -> void:
	_spawn_enemy(id, script_path, pos, zone)
	if hp_mult != 1.0 or dmg_mult != 1.0 or speed_mult != 1.0 or aggro_mult != 1.0:
		# Deferred so it fires after _ready() sets base stats
		var enemy = _enemy_nodes.get(id, null)
		if enemy:
			enemy.call_deferred("apply_dungeon_scaling", hp_mult, dmg_mult, speed_mult, aggro_mult)

func on_enemy_died(id: String, spawn_point: Vector2, script_path: String, zone: String) -> void:
	_enemy_nodes.erase(id)
	# Notify dungeon manager if this enemy was in a dungeon instance
	if _dungeon_manager and _is_dungeon_zone(zone):
		_dungeon_manager.on_enemy_killed(id, zone)
		return   # dungeon enemies don't respawn
	_respawn_queue.append({
		"id":     id,
		"script": script_path,
		"pos":    spawn_point,
		"zone":   zone,
		"timer":  RESPAWN_TIME,
	})

func _on_ready_check_requested(peer_id: int, dungeon_id: String, difficulty: String = "easy") -> void:
	if not _dungeon_manager:
		return
	var result = _dungeon_manager.initiate_ready_check(peer_id, dungeon_id, difficulty)
	if not result["ok"]:
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			net.dungeon_enter_denied.rpc_id(peer_id, result["error"])

func _on_player_ready(peer_id: int, is_ready: bool) -> void:
	if _dungeon_manager:
		_dungeon_manager.set_ready(peer_id, is_ready)

func _on_cancel_ready(peer_id: int) -> void:
	if _dungeon_manager:
		_dungeon_manager.cancel_ready_check(peer_id)

func _on_dungeon_enter_requested(peer_id: int, dungeon_id: String) -> void:
	var net     = get_tree().root.get_node_or_null("Network")
	if not net:
		return
	var party_id = _party_in_party.get(peer_id, -1)
	var def      = DungeonData.get_dungeon(dungeon_id)
	if def.is_empty():
		net.dungeon_enter_denied.rpc_id(peer_id, "Unknown dungeon.")
		return
	# Solo-only: reject if in a party
	if def.get("solo_only", false) and party_id != -1:
		net.dungeon_enter_denied.rpc_id(peer_id, "%s is solo only." % def["display_name"])
		return
	print("[DUNGEON] Enter request: peer=%d dungeon=%s party_id=%d" % [peer_id, dungeon_id, party_id])
	var result = _dungeon_manager.player_enter(peer_id, dungeon_id, party_id)
	print("[DUNGEON] Enter result: %s" % str(result))
	if not result["ok"]:
		net.dungeon_enter_denied.rpc_id(peer_id, result["error"])
		return
	var sp = server_players.get(peer_id, null)
	if sp:
		var zone_name = result["zone_name"]   # unique per instance e.g. cave_of_trials_1
		var spawn     = def["spawn_pos"]
		sp.zone       = zone_name
		sp.world_pos  = spawn
		sp.global_position = spawn
		Network.players[peer_id]["zone"]     = zone_name
		Network.players[peer_id]["position"] = spawn
		# NOTE: do NOT send roster here — enemies aren't spawned yet.
		# Wave controller sends the roster after spawning enemies in _advance_wave().
		net.dungeon_enter_accepted.rpc_id(peer_id, dungeon_id, zone_name, spawn)
		print("[SERVER] %s entered dungeon '%s' instance %d" % [sp.username, dungeon_id, result["instance_id"]])

func _on_dungeon_exit_requested(peer_id: int) -> void:
	# Allow exit when dungeon is fully complete OR the current floor's boss is cleared
	# (the boss clear sends [-1]/leave-dungeon door only on the final floor,
	#  so this guard mainly protects against spoofed RPCs)
	var inst_id = _dungeon_manager.get_instance_id_for_peer(peer_id) if _dungeon_manager else -1
	if inst_id >= 0:
		var can_exit = _dungeon_manager.is_instance_complete(inst_id) or \
			_dungeon_manager.is_floor_boss_cleared(inst_id)
		if not can_exit:
			Network.dungeon_enter_denied.rpc_id(peer_id, "Defeat the boss before leaving!")
			return
	var net = get_tree().root.get_node_or_null("Network")
	if not net:
		return
	if not _dungeon_manager.peer_is_in_dungeon(peer_id):
		return
	_dungeon_manager.player_exit(peer_id)
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	# Find dungeon def for exit info (use zone the player was in)
	var dungeon_id = ""
	for did in DungeonData.DUNGEONS:
		var base = DungeonData.DUNGEONS[did]["zone_name"]
		if sp.zone == base or sp.zone.begins_with(base + "_"):
			dungeon_id = did
			break
	var def       = DungeonData.get_dungeon(dungeon_id)
	var exit_scene = def.get("exit_scene", "res://scenes/village.tscn")
	var exit_pos   = def.get("exit_pos",   Vector2(40, 40))
	var exit_zone  = def.get("exit_zone",  "village")
	sp.zone = exit_zone
	Network.players[peer_id]["zone"] = exit_zone
	_send_enemy_roster(peer_id, exit_zone)
	net.dungeon_exit_accepted.rpc_id(peer_id, exit_scene, exit_pos)
	print("[SERVER] %s exited dungeon back to %s" % [sp.username, exit_zone])

func _on_shadow_freed(shadow_id: String) -> void:
	_shadow_nodes.erase(shadow_id)

func _on_hotbar_loadout(peer_id: int, loadout: Array) -> void:
	var sp = server_players.get(peer_id, null)
	if sp == null:
		return
	sp.hotbar_loadout = loadout
	Database.save_player(sp.username, sp.get_save_data())

func _on_character_creation(peer_id: int, clan_id: String, element_id: String) -> void:
	var sp = server_players.get(peer_id, null)
	if sp == null or sp.clan != "":
		return
	if not ClanDB.clan_exists(clan_id) or not ClanDB.element_exists(element_id):
		return
	sp.clan    = clan_id
	sp.element = element_id
	var save_data = sp.get_save_data()
	Database.save_player(sp.username, save_data)
	print("[SERVER] Character creation: %s chose clan=%s element=%s" % [sp.username, clan_id, element_id])

func _on_equip_update(peer_id: int, equipped: Dictionary) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	const VALID_SLOTS = ["weapon", "head", "chest", "legs", "shoes", "accessory"]
	var clean: Dictionary = {}
	for k in equipped:
		if not k in VALID_SLOTS:
			continue
		var client_item = equipped[k]
		if not client_item is Dictionary:
			continue
		var item_id: String = client_item.get("id", "")
		if item_id == "":
			continue
		# Validate ownership — player must have the item in inventory or it's a starter item
		# Starter items (shirts, pants) are always allowed
		var is_starter = item_id in ["shirt1", "pants1"]
		if not is_starter and not sp.has_item(item_id):
			print("[SERVER] %s tried to equip unowned item: %s" % [sp.username, item_id])
			continue
		# Rebuild item data from ItemDB — never trust client stat values
		var fresh = ItemDB.get_item(item_id)
		if fresh.is_empty():
			continue
		# Preserve tint (cosmetic only, not a stat)
		if client_item.has("tint"):
			fresh["tint"] = client_item["tint"]
		clean[k] = fresh
	sp.equipped = clean
	sp.recalculate_gear_stats()
	Database.save_player(sp.username, sp.get_save_data())
	print("[SERVER] %s equip update: %s" % [sp.username, clean.keys()])

func _on_appearance_update(peer_id: int, appearance: Dictionary) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	sp.appearance = appearance
	Database.save_player(sp.username, sp.get_save_data())

func _on_item_used(peer_id: int, item_id: String) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	var result = sp.use_consumable(item_id)
	Network.notify_item_result.rpc_id(peer_id, result.get("success", false), result.get("message", ""), result.get("new_hp", -1), result.get("new_max_hp", -1))

# Resolves a target_id string ("player_<id>" or "enemy_<id>") to a server object.
# Returns a Dictionary: {type: "player"|"enemy", node: ...}
func _cancel_mass_shadows(peer_id: int) -> void:
	var prefix = "massshadow_%d_" % peer_id
	var to_cancel: Array = []
	for sid in _shadow_nodes:
		if sid.begins_with(prefix):
			to_cancel.append(sid)
	for sid in to_cancel:
		if _shadow_nodes.has(sid):
			_shadow_nodes[sid]._despawn("cancelled")
			_shadow_nodes.erase(sid)

func cancel_shadows_for_peer(peer_id: int) -> void:
	# Cancel any active shadow where this peer is caster OR target
	var to_cancel: Array = []
	for sid in _shadow_nodes:
		var sh = _shadow_nodes[sid]
		if not is_instance_valid(sh):
			continue
		if sh.caster_id == peer_id or sh.target_id_str == "player_%d" % peer_id:
			to_cancel.append(sid)
	for sid in to_cancel:
		if _shadow_nodes.has(sid):
			_shadow_nodes[sid]._despawn("cancelled")
			_shadow_nodes.erase(sid)

func cancel_shadows_for_enemy(enemy_node: Node) -> void:
	# Cancel any active shadow targeting this enemy instance
	var iid = str(enemy_node.get_instance_id())
	var to_cancel: Array = []
	for sid in _shadow_nodes:
		var sh = _shadow_nodes[sid]
		if not is_instance_valid(sh):
			continue
		if sh.target_id_str == "enemy_%s" % iid or sh.target_id_str == iid:
			to_cancel.append(sid)
	for sid in to_cancel:
		if _shadow_nodes.has(sid):
			_shadow_nodes[sid]._despawn("cancelled")
			_shadow_nodes.erase(sid)

func _resolve_target(target_id: String, zone: String) -> Dictionary:
	if target_id.begins_with("player_"):
		var tid = target_id.substr(7).to_int()
		var sp  = server_players.get(tid, null)
		if sp and sp.zone == zone and not sp.is_dead:
			return {"type": "player", "node": sp}
	elif not target_id.is_empty():
		var enemy = _enemy_nodes.get(target_id, null)
		if enemy and is_instance_valid(enemy) and enemy.zone_name == zone:
			return {"type": "enemy", "node": enemy}
	return {}


# ── Ability Validation Pipeline ───────────────────────────────────────────
# Returns "" if the ability can fire, or a human-readable reason string if not.
# Also records the cooldown on success so the server enforces it.
func _validate_ability(peer_id: int, sp, ability_name: String, chakra_cost: int) -> String:
	# 1. Player state
	if sp.is_dead:
		return "You are dead."
	if sp.is_ghost:
		return "Ghosts cannot use abilities."
	if sp.is_rooted:
		return "You are rooted."
	# 2. Server-side cooldown
	if sp.is_ability_on_cooldown(ability_name):
		var remaining = snappedf(sp.ability_cooldowns.get(ability_name, 0.0), 0.1)
		return "On cooldown (%.1fs remaining)." % remaining
	# 3. Chakra — use spend_chakra so client gets synced
	if not sp.spend_chakra(chakra_cost):
		return "Not enough chakra (%d/%d)." % [sp.current_chakra, chakra_cost]
	# 4. Passed — record server-side cooldown
	var cd = Network.ABILITY_COOLDOWNS.get(ability_name, 0.0)
	sp.set_ability_cooldown(ability_name, cd)
	return ""

func _fail_ability(peer_id: int, ability_name: String, reason: String) -> void:
	print("[ABILITY] FAIL peer=%d ability=%s reason=%s" % [peer_id, ability_name, reason])
	Network.notify_ability_failed.rpc_id(peer_id, ability_name, reason)

func _on_ability_used(peer_id: int, ability_name: String, data: Dictionary) -> void:
	if not server_players.has(peer_id):
		return
	var sp = server_players[peer_id]
	# Hard state blocks — with feedback
	# charging_start/stop bypass all state checks
	if ability_name in ["charging_start", "charging_stop"]:
		match ability_name:
			"charging_start": sp.start_charging()
			"charging_stop":  sp.stop_charging()
		return
	if sp.is_dead:
		_fail_ability(peer_id, ability_name, "You are dead.")
		return
	if sp.is_ghost:
		_fail_ability(peer_id, ability_name, "Ghosts cannot use abilities.")
		return
	if sp.is_rooted:
		_fail_ability(peer_id, ability_name, "You are rooted.")
		return
	match ability_name:
		"fire_burst":
			var _err_fire_burst = _validate_ability(peer_id, sp, "fire_burst", 35)
			if _err_fire_burst != "":
				_fail_ability(peer_id, "fire_burst", _err_fire_burst)
				return
			var origin    = data.get("position", sp.world_pos)
			var radius    = data.get("radius",   80.0)
			var dmg       = data.get("damage",   35)
			var do_kb     = data.get("knockback", true)
			# Broadcast cast visual to caster and all observers
			sp._broadcast_visual("fire_burst_cast")
			for oid in server_players:
				if oid == peer_id:
					continue
				var other = server_players[oid]
				if other.zone != sp.zone or other.is_dead:
					continue
				if are_same_party(peer_id, oid):
					continue
				if other.world_pos.distance_to(origin) <= radius:
					var kb = (other.world_pos - origin).normalized() if do_kb else Vector2.ZERO
					other.take_damage(dmg, kb, peer_id)
					Network.confirm_ability_hit.rpc_id(peer_id, other.world_pos, dmg)
					# Broadcast hit visual so ALL observers see the target react
					other._broadcast_visual("fire_burst")
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if enemy.zone_name != sp.zone:
					continue
				if enemy.global_position.distance_to(origin) <= radius:
					if enemy.has_method("take_damage"):
						var kb = (enemy.global_position - origin).normalized() if do_kb else Vector2.ZERO
						enemy.take_damage(dmg, kb, sp.get_instance_id())
					Network.confirm_ability_hit.rpc_id(peer_id, enemy.global_position, dmg)
					# Broadcast hit visual to all observers
					Network.ability_visual.rpc_id(1, enemy.enemy_id, "fire_burst")
					for pid: int in multiplayer.get_peers():
						Network.ability_visual.rpc_id(pid, enemy.enemy_id, "fire_burst")

		"shadow_possession":
			var _err_sp = _validate_ability(peer_id, sp, "shadow_possession_start", 30)
			if _err_sp != "":
				_fail_ability(peer_id, "shadow_possession", _err_sp)
				return
			var caster_pos = data.get("caster_pos", sp.world_pos)
			var target_id  = data.get("target_id", "")
			var range_sq   = pow(data.get("range", 320.0), 2)
			var duration   = data.get("duration", 4.0)
			var result     = _resolve_target(target_id, sp.zone)
			if result.is_empty():
				return
			var t = result["node"]
			var t_pos = t.world_pos if result["type"] == "player" else t.global_position
			if caster_pos.distance_squared_to(t_pos) > range_sq:
				return
			if result["type"] == "player":
				if not are_same_party(peer_id, t.peer_id):
					t.apply_rooted_visual(duration)
					Network.confirm_ability_hit.rpc_id(peer_id, t_pos, 0)
			elif t.has_method("apply_root"):
				t.apply_root(duration)
				Network.confirm_ability_hit.rpc_id(peer_id, t_pos, 0)

		"shadow_strangle":
			var _err_shadow_strangle = _validate_ability(peer_id, sp, "shadow_strangle", 20)
			if _err_shadow_strangle != "":
				_fail_ability(peer_id, "shadow_strangle", _err_shadow_strangle)
				return
			var caster_pos    = data.get("caster_pos", sp.world_pos)
			var target_id     = data.get("target_id", "")
			var range_sq      = pow(data.get("range", 320.0), 2)
			var dmg_tick      = data.get("damage", 12)
			var tick_interval = data.get("tick_interval", 1.0)
			var ticks         = data.get("ticks", 4)
			var result        = _resolve_target(target_id, sp.zone)
			if result.is_empty():
				return
			var t     = result["node"]
			var t_pos = t.world_pos if result["type"] == "player" else t.global_position
			if caster_pos.distance_squared_to(t_pos) > range_sq:
				return
			# Require target to be rooted by THIS caster's shadow (solo OR mass)
			var shadow_caught = false
			for sid in _shadow_nodes:
				var s = _shadow_nodes[sid]
				if s.caster_id == peer_id and s.get("_caught") and s.target_id_str == target_id:
					shadow_caught = true
					break
			if not shadow_caught:
				Network.notify_status.rpc_id(peer_id, peer_id, "strangle_fail", 0.0)
				return
			var target_node = result["node"]
			if not target_node.is_rooted:
				Network.notify_status.rpc_id(peer_id, peer_id, "strangle_fail", 0.0)
				return
			if result["type"] == "player":
				if not are_same_party(peer_id, t.peer_id):
					t.apply_dot(dmg_tick, tick_interval, ticks, peer_id)
					Network.confirm_ability_hit.rpc_id(peer_id, t_pos, dmg_tick)
					Network.ability_visual.rpc(str(t.peer_id), "strangle")
			elif t.has_method("apply_dot"):
				t.apply_dot(dmg_tick, tick_interval, ticks, peer_id)
				Network.ability_visual.rpc(t.enemy_id, "strangle")

		"shadow_pull":
			var _err_shadow_pull = _validate_ability(peer_id, sp, "shadow_pull", 15)
			if _err_shadow_pull != "":
				_fail_ability(peer_id, "shadow_pull", _err_shadow_pull)
				return
			var caster_pos = data.get("caster_pos", sp.world_pos)
			var target_id  = data.get("target_id", "")
			var range_sq   = pow(data.get("range", 256.0), 2)
			var pull_dist  = data.get("pull_dist", 48.0)
			# Require an active caught shadow targeting this specific target
			var shadow_caught = false
			for sid in _shadow_nodes:
				var s = _shadow_nodes[sid]
				if s.caster_id == peer_id and s.get("_caught") and s.target_id_str == target_id:
					shadow_caught = true
					break
			if not shadow_caught:
				Network.notify_status.rpc_id(peer_id, peer_id, "strangle_fail", 0.0)
				return
			var result     = _resolve_target(target_id, sp.zone)
			if result.is_empty():
				return
			var t = result["node"]
			var t_pos = t.world_pos if result["type"] == "player" else t.global_position
			var dist_sq = caster_pos.distance_squared_to(t_pos)
			if dist_sq > range_sq:
				return
			if dist_sq < pow(64.0, 2):  # min range
				return
			if result["type"] == "player":
				if not are_same_party(peer_id, t.peer_id):
					t.apply_pull(caster_pos, pull_dist)
					Network.confirm_ability_hit.rpc_id(peer_id, t_pos, 0)
			else:
				# Enemy: teleport near caster and broadcast to all clients
				var dir        = (caster_pos - t.global_position).normalized()
				var dest       = caster_pos - dir * pull_dist
				t.global_position = dest
				Network.confirm_ability_hit.rpc_id(peer_id, t_pos, 0)
				Network.enemy_pulled.rpc(target_id, dest, caster_pos)

		"debug_unlock_ability":
			var ab_id = data.get("ability_id", "")
			if ab_id != "" and ab_id not in sp.unlocked_abilities:
				sp.unlocked_abilities.append(ab_id)
				Database.save_player(sp.username, sp.get_save_data())

		"shadow_possession_start":
			var _err_shadow_possession_start = _validate_ability(peer_id, sp, "shadow_possession_start", 15)
			if _err_shadow_possession_start != "":
				_fail_ability(peer_id, "shadow_possession_start", _err_shadow_possession_start)
				return
			var caster_pos = data.get("caster_pos", sp.world_pos)
			var target_id  = data.get("target_id", "")
			var range_sq   = pow(data.get("range", 320.0), 2)
			if target_id.is_empty():
				return
			var result = _resolve_target(target_id, sp.zone)
			if result.is_empty():
				return
			var t_pos = result["node"].world_pos if result["type"] == "player" else result["node"].global_position
			if caster_pos.distance_squared_to(t_pos) > range_sq:
				return
			# Cancel any existing shadow from this caster
			var old_id = "shadow_%d" % peer_id
			if _shadow_nodes.has(old_id):
				_shadow_nodes[old_id].queue_free()
				_shadow_nodes.erase(old_id)
			# Spawn new shadow — set logical properties before add_child so _ready() sees them
			# global_position must be set AFTER add_child (node needs scene tree for world transform)
			var shadow_id = old_id
			var shadow    = Node2D.new()
			shadow.set_script(load("res://scripts/server_shadow.gd"))
			shadow.shadow_id     = shadow_id
			shadow.caster_id     = peer_id
			shadow.target_id_str = target_id
			shadow.zone          = sp.zone
			add_child(shadow)
			shadow.global_position = caster_pos
			_shadow_nodes[shadow_id] = shadow
			Network.shadow_spawn.rpc(shadow_id, peer_id, caster_pos, target_id)

		"shadow_possession_cancel":
			var sid = "shadow_%d" % peer_id
			if _shadow_nodes.has(sid):
				_shadow_nodes[sid]._despawn("cancelled")
				_shadow_nodes.erase(sid)

		"mass_shadow_start":
			var _err_mass_shadow_start = _validate_ability(peer_id, sp, "mass_shadow_start", 40)
			if _err_mass_shadow_start != "":
				_fail_ability(peer_id, "mass_shadow_start", _err_mass_shadow_start)
				return
			var origin    = data.get("caster_pos", sp.world_pos)
			var radius_sq = pow(data.get("radius", 160.0), 2)
			# Cancel any existing mass shadows from this caster
			_cancel_mass_shadows(peer_id)
			var idx = 0
			# Spawn a shadow for each nearby enemy
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if enemy.zone_name != sp.zone or enemy.is_dead:
					continue
				if enemy.global_position.distance_squared_to(origin) > radius_sq:
					continue
				var sid    = "massshadow_%d_%d" % [peer_id, idx]
				var target = enemy.enemy_id
				var shadow = Node2D.new()
				shadow.set_script(load("res://scripts/server_shadow.gd"))
				shadow.shadow_id     = sid
				shadow.caster_id     = peer_id
				shadow.target_id_str = target
				shadow.zone          = sp.zone
				add_child(shadow)
				shadow.global_position = origin
				_shadow_nodes[sid] = shadow
				Network.shadow_spawn.rpc(sid, peer_id, origin, target)
				idx += 1
			# Spawn a shadow for each nearby hostile player
			for oid in server_players:
				if oid == peer_id:
					continue
				var other = server_players[oid]
				if other.zone != sp.zone or other.is_dead:
					continue
				if are_same_party(peer_id, oid):
					continue
				if other.world_pos.distance_squared_to(origin) > radius_sq:
					continue
				var sid    = "massshadow_%d_%d" % [peer_id, idx]
				var target = "player_%d" % oid
				var shadow = Node2D.new()
				shadow.set_script(load("res://scripts/server_shadow.gd"))
				shadow.shadow_id     = sid
				shadow.caster_id     = peer_id
				shadow.target_id_str = target
				shadow.zone          = sp.zone
				add_child(shadow)
				shadow.global_position = origin
				_shadow_nodes[sid] = shadow
				Network.shadow_spawn.rpc(sid, peer_id, origin, target)
				idx += 1

		"mass_shadow_cancel":
			_cancel_mass_shadows(peer_id)

		# ── Hyuga ──────────────────────────────────────────────────────────────
		"gentle_fist":
			var _err_gentle_fist = _validate_ability(peer_id, sp, "gentle_fist", 23)
			if _err_gentle_fist != "":
				_fail_ability(peer_id, "gentle_fist", _err_gentle_fist)
				return
			_on_gentle_fist(peer_id, data, sp)

		"prime_palms":
			var byakugan_on: bool = data.get("byakugan", sp.byakugan_active)
			var cost: int = 200 if byakugan_on else 100
			var _err_palms = _validate_ability(peer_id, sp, "prime_palms", cost)
			if _err_palms != "":
				_fail_ability(peer_id, "prime_palms", _err_palms)
				return
			sp.palms_primed      = true
			sp.palms_prime_timer = 15.0
			sp.palms_byakugan    = byakugan_on

		"palm_rotation":
			var _err_palm_rotation = _validate_ability(peer_id, sp, "palm_rotation", 35)
			if _err_palm_rotation != "":
				_fail_ability(peer_id, "palm_rotation", _err_palm_rotation)
				return
			_on_palm_rotation(peer_id, data, sp)

		"byakugan_toggle":
			var byk_active = data.get("active", false)
			if byk_active:
				var _err_byk = _validate_ability(peer_id, sp, "byakugan_toggle", 10)
				if _err_byk != "":
					_fail_ability(peer_id, "byakugan_toggle", _err_byk)
					return
			sp.byakugan_active = byk_active
			Network.byakugan_state.rpc(peer_id, byk_active)

		# ── Aburame ─────────────────────────────────────────────────────────────
		"bug_swarm":
			var _err_bug_swarm = _validate_ability(peer_id, sp, "bug_swarm", 20)
			if _err_bug_swarm != "":
				_fail_ability(peer_id, "bug_swarm", _err_bug_swarm)
				return
			_on_bug_swarm(peer_id, data, sp)

		"parasite_prime":
			var _err_parasite_prime = _validate_ability(peer_id, sp, "parasite_prime", 25)
			if _err_parasite_prime != "":
				_fail_ability(peer_id, "parasite_prime", _err_parasite_prime)
				return
			sp.parasite_primed      = true
			sp.parasite_prime_timer = sp.PARASITE_PRIME_DUR

		"insect_cocoon":
			var _err_insect_cocoon = _validate_ability(peer_id, sp, "insect_cocoon", 30)
			if _err_insect_cocoon != "":
				_fail_ability(peer_id, "insect_cocoon", _err_insect_cocoon)
				return
			_on_insect_cocoon(peer_id, data, sp)

		"hive_burst":
			var _err_hive_burst = _validate_ability(peer_id, sp, "hive_burst", 45)
			if _err_hive_burst != "":
				_fail_ability(peer_id, "hive_burst", _err_hive_burst)
				return
			_on_hive_burst(peer_id, data, sp)

		"bug_cloak_toggle":
			var cloak_active = data.get("active", false)
			if cloak_active:
				var _err_cloak = _validate_ability(peer_id, sp, "bug_cloak_toggle", 35)
				if _err_cloak != "":
					_fail_ability(peer_id, "bug_cloak_toggle", _err_cloak)
					return
			sp.bug_cloak_active = cloak_active
			var vid = "bug_cloak_start" if cloak_active else "bug_cloak_end"
			_emit_visual(str(peer_id), vid)

		# ── Universal ───────────────────────────────────────────────────────────
		"charging_start":
			sp.start_charging()

		"charging_stop":
			sp.stop_charging()

		"medical_jutsu":
			var _err_medical_jutsu = _validate_ability(peer_id, sp, "medical_jutsu", 25)
			if _err_medical_jutsu != "":
				_fail_ability(peer_id, "medical_jutsu", _err_medical_jutsu)
				return
			sp.start_hot(
				data.get("heal_per_tick", 8),
				data.get("interval",      1.0),
				data.get("ticks",         5)
			)

		"substitution_prime":
			var _err_substitution_prime = _validate_ability(peer_id, sp, "substitution_prime", 30)
			if _err_substitution_prime != "":
				_fail_ability(peer_id, "substitution_prime", _err_substitution_prime)
				return
			sp.prime_substitution()

		"substitution_triggered":
			# Client reports where they teleported — server confirms and broadcasts
			if sp.is_substitution_primed:
				sp.is_substitution_primed = false
			var new_pos = data.get("new_pos", sp.world_pos)
			sp.trigger_substitution(new_pos)

		"air_palm":
			var _err_air_palm = _validate_ability(peer_id, sp, "air_palm", 25)
			if _err_air_palm != "":
				_fail_ability(peer_id, "air_palm", _err_air_palm)
				return
			_on_air_palm(peer_id, data, sp)

		"c1_spiders":
			var _err_c1_spiders = _validate_ability(peer_id, sp, "c1_spiders", 6)
			if _err_c1_spiders != "":
				_fail_ability(peer_id, "c1_spiders", _err_c1_spiders)
				return
			_on_c1_spiders(peer_id, data, sp)
			sp.set_ability_cooldown("c1_spiders", data.get("effective_cooldown", Network.ABILITY_COOLDOWNS.get("c1_spiders", 1.5)))

		"c2_owl":
			var _err_c2_owl = _validate_ability(peer_id, sp, "c2_owl", 75)
			if _err_c2_owl != "":
				_fail_ability(peer_id, "c2_owl", _err_c2_owl)
				return
			_on_c2_owl(peer_id, data, sp)
			sp.set_ability_cooldown("c2_owl", data.get("effective_cooldown", Network.ABILITY_COOLDOWNS.get("c2_owl", 25.0)))

		"c3_bomb":
			var _err_c3_bomb = _validate_ability(peer_id, sp, "c3_bomb", 150)
			if _err_c3_bomb != "":
				_fail_ability(peer_id, "c3_bomb", _err_c3_bomb)
				return
			_on_c3_bomb(peer_id, data, sp)
			sp.set_ability_cooldown("c3_bomb", data.get("effective_cooldown", Network.ABILITY_COOLDOWNS.get("c3_bomb", 20.0)))

		"c4_karura":
			var _err_c4_karura = _validate_ability(peer_id, sp, "c4_karura", 125)
			if _err_c4_karura != "":
				_fail_ability(peer_id, "c4_karura", _err_c4_karura)
				return
			_on_c4_karura(peer_id, data, sp)
			sp.set_ability_cooldown("c4_karura", data.get("effective_cooldown", Network.ABILITY_COOLDOWNS.get("c4_karura", 45.0)))

		"katsu":
			var _err_katsu = _validate_ability(peer_id, sp, "katsu", 50)
			if _err_katsu != "":
				_fail_ability(peer_id, "katsu", _err_katsu)
				return
			_on_katsu(peer_id, sp)

# ── Hyuga Ability Handlers ────────────────────────────────────────────────

func _on_gentle_fist(peer_id: int, data: Dictionary, sp) -> void:
	var caster_pos  = data.get("caster_pos", sp.world_pos)
	var target_id   = data.get("target_id", "")
	var dmg         = data.get("damage", 18)
	var drain       = data.get("target_drain", 20)
	var range_sq    = pow(data.get("range", 48.0), 2)
	var result      = _resolve_target(target_id, sp.zone)
	if result.is_empty():
		return
	var t     = result["node"]
	var t_pos = t.world_pos if result["type"] == "player" else t.global_position
	if caster_pos.distance_squared_to(t_pos) > range_sq:
		return
	# Caster visual — everyone in zone sees the caster strike
	sp._broadcast_visual("gentle_fist_cast")
	var kb_dir = (t_pos - caster_pos).normalized()
	if result["type"] == "player":
		if not are_same_party(peer_id, t.peer_id):
			t.take_damage(dmg, kb_dir, peer_id)
			t.apply_chakra_drain(drain)
			Network.confirm_ability_hit.rpc_id(peer_id, t_pos, dmg)
			Network.ability_visual.rpc(str(t.peer_id), "gentle_fist")
			Network.chakra_drain_visual.rpc(t_pos, drain)
	else:
		t.take_damage(dmg, kb_dir, sp.get_instance_id())
		Network.confirm_ability_hit.rpc_id(peer_id, t_pos, dmg)
		Network.ability_visual.rpc(t.enemy_id, "gentle_fist")
		Network.chakra_drain_visual.rpc(t_pos, drain)

func _trigger_palms_burst(peer_id: int, target_node: Node, is_enemy: bool) -> void:
	var sp: ServerPlayer = server_players.get(peer_id, null)
	if sp == null or not is_instance_valid(target_node):
		return
	var hits:      int   = 8   if sp.palms_byakugan else 7
	var dmg:       int   = 5 + int(sp.effective_strength() * 0.3)
	var interval:  float = 0.5
	var combo_dur: float = float(hits) * interval + 1.0
	var icon_path: String = "res://sprites/Hyuga/64palms.png"
	var target_pos: Vector2
	var target_id_str: String
	if is_enemy:
		var enemy: EnemyBase = target_node as EnemyBase
		target_pos    = enemy.global_position
		target_id_str = enemy.enemy_id
		enemy.apply_root(combo_dur)
	else:
		var tgt: ServerPlayer = target_node as ServerPlayer
		target_pos    = tgt.world_pos
		target_id_str = str(tgt.peer_id)
		tgt.apply_root(combo_dur)
	# Root caster for full combo duration
	sp.apply_root(combo_dur)
	# Caster is immune for the entire combo duration — they are "invisible" doing the work
	sp.is_immune = true
	# Broadcast cinematic start to ALL peers (everyone sees it)
	for pid: int in multiplayer.get_peers():
		Network.palms_cinematic.rpc_id(pid, peer_id, target_id_str, hits, interval, icon_path)
	var attacker_id = sp.get_instance_id() if is_enemy else peer_id
	_palms_hit_chain(peer_id, target_node, target_pos, dmg, interval, hits, 0, is_enemy, attacker_id)

func _palms_hit_chain(peer_id: int, t: Node, t_pos: Vector2, dmg: int, interval: float, total: int, current: int, is_enemy: bool, attacker_id) -> void:
	# Apply this hit if target still exists (chain always runs to completion)
	if is_instance_valid(t) and not t.is_dead:
		t.take_damage(dmg, Vector2.ZERO, attacker_id)
		# Chakra drain = half damage
		var drain: int = max(1, dmg / 2)
		if not is_enemy:
			(t as ServerPlayer).apply_chakra_drain(drain)
		Network.chakra_drain_visual.rpc(t_pos, drain)
	# Damage number back to caster regardless
	Network.confirm_ability_hit.rpc_id(peer_id, t_pos, dmg)
	if current + 1 < total:
		var next: int = current + 1
		get_tree().create_timer(interval).timeout.connect(func() -> void:
			_palms_hit_chain(peer_id, t, t_pos, dmg, interval, total, next, is_enemy, attacker_id)
		)
	else:
		# Final hit — compute knockback direction away from caster, broadcast end
		var sp: ServerPlayer = server_players.get(peer_id, null)
		var caster_pos: Vector2 = sp.world_pos if sp != null else t_pos
		var final_pos: Vector2  = t.global_position if (is_enemy and is_instance_valid(t)) else \
			((t as ServerPlayer).world_pos if is_instance_valid(t) else t_pos)
		var kb_dir: Vector2 = (final_pos - caster_pos).normalized()
		if kb_dir == Vector2.ZERO:
			kb_dir = Vector2.RIGHT
		# Teleport the server entity to the knockback destination, then pause
		# broadcast so the client has time to play the visual without fighting it
		var kb_dist: float = 150.0
		if is_instance_valid(t):
			if is_enemy:
				var enemy_node := t as EnemyBase
				enemy_node.global_position = final_pos + kb_dir * kb_dist
				enemy_node.knockback_timer = 1.5
			else:
				var tgt_sp := t as ServerPlayer
				var kb_dest: Vector2 = final_pos + kb_dir * kb_dist
				tgt_sp.set_position_from_client(kb_dest, true)
				tgt_sp.knockback_timer = 1.5
		for pid: int in multiplayer.get_peers():
			Network.palms_cinematic_end.rpc_id(pid, peer_id, final_pos, kb_dir)
		# Restore caster vulnerability now that the combo is done
		if sp != null:
			sp.is_immune = false
# ── Aburame Ability Handlers ─────────────────────────────────────────────

func _on_bug_swarm(peer_id: int, data: Dictionary, sp) -> void:
	var range_val  = data.get("range", 160.0)
	var half_deg   = data.get("cone_half_deg", 30.0)
	var dmg        = data.get("damage", 6)
	var ticks      = data.get("ticks", 4)
	var interval   = data.get("tick_interval", 1.0)
	var half_rad   = deg_to_rad(half_deg)

	# Aim direction locked at cast time — points at target regardless of where player faces
	var aim_dir: Vector2 = (data.get("aim_dir", Vector2.DOWN) as Vector2).normalized()

	_emit_visual_ex(str(peer_id), "bug_swarm_cast", aim_dir)

	var tagged: Array = []

	for tick_i in range(ticks):
		var delay         = float(tick_i) * interval
		var captured_tick = tick_i
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not server_players.has(peer_id):
				return
			var sp2     = server_players[peer_id]
			var origin2 = sp2.world_pos

			# Tag any new enemies that entered the cone this tick
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if enemy in tagged or enemy.zone_name != sp2.zone or enemy.is_dead:
					continue
				var to_e = enemy.global_position - origin2
				if to_e.length() == 0 or to_e.length() > range_val:
					continue
				if abs(aim_dir.angle_to(to_e.normalized())) > half_rad:
					continue
				tagged.append(enemy)
			for oid in server_players:
				if oid == peer_id:
					continue
				var other = server_players[oid]
				if other in tagged or other.zone != sp2.zone or other.is_dead or are_same_party(peer_id, oid):
					continue
				var to_o = other.world_pos - origin2
				if to_o.length() == 0 or to_o.length() > range_val:
					continue
				if abs(aim_dir.angle_to(to_o.normalized())) > half_rad:
					continue
				tagged.append(other)

			# Damage every tagged target
			for t in tagged.duplicate():
				if not is_instance_valid(t) or t.is_dead:
					tagged.erase(t)
					continue
				t.take_damage(dmg, Vector2.ZERO, peer_id)
				var hit_pos: Vector2
				if "enemy_id" in t:
					hit_pos = t.global_position
					_emit_visual(t.enemy_id, "bug_hit")
				else:
					hit_pos = t.world_pos
					_emit_visual(str(t.peer_id), "bug_hit")
				Network.confirm_ability_hit.rpc_id(peer_id, hit_pos + Vector2(0, captured_tick * -8), dmg)
		)

func _trigger_parasite(peer_id: int, hit_node: Node, is_enemy: bool) -> void:
	var sp: ServerPlayer = server_players.get(peer_id, null)
	if sp == null or not is_instance_valid(hit_node):
		return
	print("[PARASITE] triggered — peer=%d is_enemy=%s target=%s" % [peer_id, str(is_enemy), str(hit_node)])
	var dmg         = 10 + int(sp.effective_strength() * 0.3)
	var drain_tick  = 8    # chakra/sec for players, hp/sec for enemies
	var tick_count  = 8    # 8 seconds
	var tick_int    = 1.0
	if is_enemy:
		hit_node.take_damage(dmg, Vector2.ZERO, peer_id)
		hit_node.apply_dot(drain_tick, tick_int, tick_count, peer_id)
		_emit_visual(hit_node.enemy_id, "bug_hit")
		Network.confirm_ability_hit.rpc_id(peer_id, hit_node.global_position, dmg)
	else:
		var tgt: ServerPlayer = hit_node as ServerPlayer
		tgt.take_damage(dmg, Vector2.ZERO, peer_id)
		# Chain chakra drains — 8/sec for 8 seconds
		for i in range(tick_count):
			get_tree().create_timer(float(i + 1) * tick_int).timeout.connect(func() -> void:
				if is_instance_valid(tgt) and not tgt.is_dead:
					tgt.apply_chakra_drain(drain_tick)
					_emit_visual(str(tgt.peer_id), "bug_hit")
			)
		_emit_visual(str(tgt.peer_id), "bug_hit")
		Network.confirm_ability_hit.rpc_id(peer_id, tgt.world_pos, dmg)

func _on_insect_cocoon(peer_id: int, data: Dictionary, sp) -> void:
	var pos = data.get("pos", sp.world_pos)
	var script = load("res://scripts/server_insect_trap.gd")
	if script == null:
		push_error("[TRAP] res://scripts/server_insect_trap.gd not found")
		return
	var trap_id = "trap_insect_%d_%d" % [peer_id, Time.get_ticks_msec()]
	var trap = Node2D.new()
	trap.set_script(script)
	trap.trap_id         = trap_id
	trap.caster_id       = peer_id
	trap.zone            = sp.zone
	trap.root_duration   = data.get("root_duration", 3.0)
	trap.dmg_per_tick    = data.get("damage", 8)
	trap.tick_interval   = data.get("tick_interval", 1.0)
	trap.tick_count      = data.get("ticks", 6)
	add_child(trap)
	trap.global_position = pos
	_trap_nodes[trap_id] = trap
	print("[TRAP] spawned %s at %s zone=%s" % [trap_id, str(pos), sp.zone])
	# rpc() excludes host — emit directly so host client sees the visual
	Network.trap_spawn.rpc(trap_id, peer_id, pos, "insect_trap")
	Network.trap_spawned.emit(trap_id, peer_id, pos, "insect_trap")

# ── Generic trap spawner — call this from any future trap ability ──
# script_path: "res://scripts/server_XXXX_trap.gd"
# props:       Dictionary of extra properties to set on the trap node
func _spawn_trap(peer_id: int, pos: Vector2, zone: String, trap_type: String, script_path: String, props: Dictionary = {}) -> void:
	var script = load(script_path)
	if script == null:
		push_error("[TRAP] Script not found: " + script_path)
		return
	var trap_id = "trap_%s_%d_%d" % [trap_type, peer_id, Time.get_ticks_msec()]
	var trap = Node2D.new()
	trap.set_script(script)
	trap.trap_id   = trap_id
	trap.caster_id = peer_id
	trap.zone      = zone
	for key in props:
		trap.set(key, props[key])
	add_child(trap)
	trap.global_position = pos
	_trap_nodes[trap_id] = trap
	Network.trap_spawn.rpc(trap_id, peer_id, pos, trap_type)
	Network.trap_spawned.emit(trap_id, peer_id, pos, trap_type)

func _on_hive_burst(peer_id: int, data: Dictionary, sp) -> void:
	var origin   = data.get("caster_pos", sp.world_pos)
	var radius   = data.get("radius", 96.0)
	var dmg      = data.get("damage", 40)
	var radius_sq = radius * radius
	# Broadcast cast flash to all in zone
	sp._broadcast_visual("hive_burst_cast")
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.zone_name != sp.zone or enemy.is_dead:
			continue
		if enemy.global_position.distance_squared_to(origin) <= radius_sq:
			var kb = (enemy.global_position - origin).normalized()
			enemy.take_damage(dmg, kb, peer_id)
			Network.confirm_ability_hit.rpc_id(peer_id, enemy.global_position, dmg)
	for oid in server_players:
		if oid == peer_id:
			continue
		var other = server_players[oid]
		if other.zone != sp.zone or other.is_dead or are_same_party(peer_id, oid):
			continue
		if other.world_pos.distance_squared_to(origin) <= radius_sq:
			var kb = (other.world_pos - origin).normalized()
			other.take_damage(dmg, kb, peer_id)
			Network.confirm_ability_hit.rpc_id(peer_id, other.world_pos, dmg)

func _on_palm_rotation(peer_id: int, data: Dictionary, sp) -> void:
	var origin   = data.get("caster_pos", sp.world_pos)
	var radius_sq = pow(data.get("radius", 52.0), 2)
	var dmg      = data.get("damage", 15)
	var duration = data.get("duration", 2.0)
	var interval = data.get("interval", 0.5)
	var ticks    = int(duration / interval)
	# Grant immunity + broadcast spin visual to ALL clients via server_player API
	sp.apply_spin(duration)
	# Schedule each damage tick
	for i in range(ticks):
		var tick_time = (i + 1) * interval
		var t2 = get_tree().create_timer(tick_time)
		t2.timeout.connect(func():
			if not server_players.has(peer_id):
				return
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if enemy.zone_name != sp.zone or enemy.is_dead:
					continue
				if enemy.global_position.distance_squared_to(sp.world_pos) <= radius_sq:
					enemy.take_damage(dmg, (enemy.global_position - sp.world_pos).normalized(), sp.get_instance_id())
					Network.confirm_ability_hit.rpc_id(peer_id, enemy.global_position, dmg)
			for oid in server_players:
				if oid == peer_id:
					continue
				var other = server_players[oid]
				if other.zone != sp.zone or other.is_dead or are_same_party(peer_id, oid):
					continue
				if other.world_pos.distance_squared_to(sp.world_pos) <= radius_sq:
					other.take_damage(dmg, (other.world_pos - sp.world_pos).normalized(), peer_id)
					Network.confirm_ability_hit.rpc_id(peer_id, other.world_pos, dmg)
		)
	# apply_spin() already schedules the immunity + rotation_end clear after duration

func _on_air_palm(peer_id: int, data: Dictionary, sp) -> void:
	var aim_dir:    Vector2 = (data.get("aim_dir", Vector2.RIGHT) as Vector2).normalized()
	var dmg:        int     = data.get("damage", 22)
	var proj_range: float   = data.get("range", 320.0)
	var target_id:  String  = data.get("target_id", "")
	var caster_pos: Vector2 = sp.world_pos
	var endpoint:   Vector2 = caster_pos + aim_dir * proj_range
	# Caster cast flash — broadcast to everyone in zone
	sp._broadcast_visual("air_palm_cast")
	# Tell all clients to start the orb visual travelling toward endpoint
	Network.air_palm_visual.rpc(peer_id, caster_pos, endpoint)
	# Register projectile — stepped each frame via _step_projectiles
	var proj        = ServerProjectile.new()
	proj.peer_id    = peer_id
	proj.pos        = caster_pos
	proj.dir        = aim_dir
	proj.dmg        = dmg
	proj.range      = proj_range
	proj.speed      = 500.0
	proj.hit_radius = 40.0
	proj.target_id  = target_id
	proj.zone       = sp.zone
	proj.visual_id  = "air_palm"
	proj.on_stop    = func(hit_pos: Vector2) -> void:
		for pid: int in multiplayer.get_peers():
			Network.air_palm_stop.rpc_id(pid, peer_id, hit_pos)
	_projectiles.append(proj)

func _on_position_received(peer_id: int, pos: Vector2) -> void:
	if server_players.has(peer_id):
		var sp: ServerPlayer = server_players[peer_id]
		# Drop position packets while in knockback — client's real pos hasn't moved there yet
		if sp.knockback_timer > 0.0:
			return
		sp.set_position_from_client(pos)

func _on_facing_received(peer_id: int, dir: String) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].facing_dir = dir

func _on_target_update_received(peer_id: int, target_id: String) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].locked_target_id = target_id

func _on_zone_changed(peer_id: int, zone_name: String) -> void:
	if server_players.has(peer_id):
		var sp = server_players[peer_id]
		var old_zone = sp.zone
		sp.zone = zone_name
		sp.world_pos = Vector2.ZERO  # reset so rate limiter bypass applies on first update
		Network.players[peer_id]["zone"] = zone_name
		print("[SERVER] Player %s zone: %s -> %s" % [sp.username, old_zone, zone_name])
		# Save on every zone transition
		Database.save_player(sp.username, sp.get_save_data())
		# Send static enemy data for the new zone — client needs this to spawn enemies correctly
		_send_enemy_roster(peer_id, zone_name)

func _send_enemy_roster(peer_id: int, zone_name: String) -> void:
	var roster: Dictionary = {}
	for id in _enemy_nodes:
		var enemy = _enemy_nodes[id]
		if not is_instance_valid(enemy) or enemy.zone_name != zone_name:
			continue
		roster[id] = {
			"type":        enemy.enemy_name,
			"max_hp":      enemy.max_hp,
			"hitbox_size": enemy.hitbox_size,
			"attack_range": enemy.attack_range,
			"level":       enemy.level,
		}
	Network.sync_enemy_roster.rpc_id(peer_id, zone_name, roster)
	print("[SERVER] Sent enemy roster to %d: zone=%s count=%d" % [peer_id, zone_name, roster.size()])

func _on_login_request(peer_id: int, username: String) -> void:
	print("[SERVER] Login: peer %d  user '%s'" % [peer_id, username])
	if username.is_empty():
		Network.deny_login(peer_id, "Username cannot be empty.")
		return
	for pid in Network.players:
		if Network.players[pid]["username"] == username and pid != peer_id:
			Network.deny_login(peer_id, "That name is already in use.")
			return
	var player_data      = Database.load_player(username)
	Network.players[peer_id]["username"] = username
	Network.accept_login(peer_id, player_data)
	print("[SERVER] Logged in: %s (peer %d)" % [username, peer_id])
	var sp           = ServerPlayer.new()
	sp.peer_id       = peer_id
	sp.username      = username
	# world_pos intentionally left at Vector2.ZERO — first client position update
	# will set it. The rate limiter bypasses distance check when world_pos == ZERO.
	sp.zone          = player_data.get("zone", "village")
	sp.clan          = player_data.get("clan", "")
	sp.element       = player_data.get("element", "")
	sp.element2      = player_data.get("element2", "")
	sp.unlocked_abilities = player_data.get("unlocked_abilities", [])
	sp.hotbar_loadout     = player_data.get("hotbar_loadout", [])
	sp.stat_strength = player_data.get("stat_str",    5)
	sp.stat_hp       = player_data.get("stat_hp",     5)
	sp.stat_chakra   = player_data.get("stat_chakra", 5)
	sp.stat_dex      = player_data.get("stat_dex",    5)
	sp.stat_int      = player_data.get("stat_int",    5)
	sp.level         = player_data.get("level",       1)
	sp.exp           = player_data.get("exp",         0)
	sp.max_exp       = ServerPlayer.xp_for_level(sp.level)
	sp.rank          = RankDB.get_rank_name(sp.level)
	sp.stat_points   = player_data.get("stat_points", 0)
	sp.max_hp        = player_data.get("max_hp",      100)
	sp.hp            = player_data.get("hp",          sp.max_hp)
	sp.kills         = player_data.get("kills",       0)
	sp.deaths        = player_data.get("deaths",      0)
	sp._loaded_data  = player_data
	sp.quest_state   = player_data.get("quest_state", {})
	sp.equipped      = player_data.get("equipped",     {})
	sp.gold          = player_data.get("gold",          0)
	sp.inventory     = player_data.get("inventory",     {})
	sp.has_done_intro   = player_data.get("has_done_intro",   false)
	sp.active_mission   = player_data.get("active_mission",   "")
	sp.mission_progress = player_data.get("mission_progress", 0)
	sp.mission_data     = player_data.get("mission_data",     {})
	sp.board_completed  = player_data.get("board_completed",  {})
	add_child(sp)
	sp.recalculate_gear_stats()
	sp.global_position      = sp.world_pos
	server_players[peer_id] = sp
	# Send enemy roster for the player's starting zone — same as zone change
	_send_enemy_roster(peer_id, sp.zone)
	# Sync gold and inventory to client
	var net2 = get_tree().root.get_node_or_null("Network")
	if net2:
		net2.sync_gold.rpc_id(peer_id, sp.gold)
		for item_id in sp.inventory:
			net2.grant_item.rpc_id(peer_id, item_id, sp.inventory[item_id])
		# Tell client whether to trigger intro sequence
		net2.notify_intro_needed.rpc_id(peer_id, not sp.has_done_intro)

func schedule_shadow_clear(shadow_id: String, delay: float) -> void:
	var t = get_tree().create_timer(delay)
	t.timeout.connect(func():
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			net.shadow_despawn.rpc(shadow_id + "_clear", false)
	)

func _on_party_invite_sent(peer_id: int, target_name: String) -> void:
	print("[SERVER] Party invite: peer %d -> '%s'" % [peer_id, target_name])
	_party_invite(peer_id, target_name)

func _on_party_response(peer_id: int, inviter_name: String, accepted: bool) -> void:
	if accepted:
		_party_accept(peer_id, inviter_name)
	else:
		_party_decline(peer_id, inviter_name)

func _on_party_leave(peer_id: int) -> void:
	_party_leave(peer_id)

func _on_party_kick(kicker_id: int, target_name: String) -> void:
	_party_kick(kicker_id, target_name)

func _on_party_promote(promoter_id: int, target_name: String) -> void:
	_party_promote(promoter_id, target_name)

func _on_player_disconnected(peer_id: int) -> void:
	_party_leave(peer_id, true)  # silent — peer is already disconnected
	if _dungeon_manager:
		_dungeon_manager.player_disconnected(peer_id)
	if server_players.has(peer_id):
		var sp = server_players[peer_id]
		# If player logged out inside a dungeon, save them back at village
		if _dungeon_manager and _is_dungeon_zone(sp.zone):
			sp.zone     = "village"
			sp.world_pos = Vector2(40.0, 40.0)
		Database.save_player(sp.username, sp.get_save_data())
		sp.queue_free()
		server_players.erase(peer_id)
	print("[SERVER] Disconnected: peer %d" % peer_id)

func _is_dungeon_zone(zone: String) -> bool:
	for did in DungeonData.DUNGEONS:
		var base = DungeonData.DUNGEONS[did]["zone_name"]
		if zone == base or zone.begins_with(base + "_"):
			return true
	return false

func _on_attack(peer_id: int, direction: Vector2, from_pos: Vector2) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].request_attack(direction, from_pos)

func _process(delta: float) -> void:
	_debug_tick -= delta
	if _debug_tick <= 0.0:
		_debug_tick = 3.0
	# Tick respawn queue
	for i in range(_respawn_queue.size() - 1, -1, -1):
		_respawn_queue[i].timer -= delta
		if _respawn_queue[i].timer <= 0:
			var r = _respawn_queue[i]
			_respawn_queue.remove_at(i)
			_spawn_enemy(r.id, r.script, r.pos, r.zone)

	_step_projectiles(delta)
	_step_clay_owls(delta)
	_step_clay_bombs(delta)
	_step_c4_swarms(delta)

	# Push apart any same-zone players standing on each other
	_separate_players()

	sync_timer += delta
	if sync_timer >= SYNC_RATE:
		sync_timer = 0.0
		_broadcast_players()

	enemy_sync_timer += delta
	if enemy_sync_timer >= ENEMY_SYNC_RATE:
		enemy_sync_timer = 0.0
		_broadcast_enemies()

var _debug_tick: float = 0.0

func _step_projectiles(delta: float) -> void:
	if _projectiles.is_empty():
		return
	# Segment-to-point distance squared helper (swept collision)
	var seg_dsq := func(p: Vector2, a: Vector2, b: Vector2) -> float:
		var ab: Vector2 = b - a
		var lsq: float  = ab.length_squared()
		if lsq == 0.0:
			return p.distance_squared_to(a)
		var tc: float = clampf((p - a).dot(ab) / lsq, 0.0, 1.0)
		return p.distance_squared_to(a + ab * tc)

	# Back-to-front so remove_at(i) never shifts unprocessed entries
	var i: int = _projectiles.size() - 1
	while i >= 0:
		var proj: ServerProjectile = _projectiles[i]

		# Belt-and-suspenders: already consumed this frame
		if proj.done:
			_projectiles.remove_at(i)
			i -= 1
			continue

		# Caster disconnected — discard silently
		var sp: ServerPlayer = server_players.get(proj.peer_id, null)
		if sp == null:
			_projectiles.remove_at(i)
			i -= 1
			continue

		# Advance position
		var step: float       = proj.speed * delta
		var prev_pos: Vector2 = proj.pos
		var cur_pos: Vector2  = prev_pos + proj.dir * step
		proj.pos              = cur_pos
		proj.travelled       += step

		var hit_r_sq: float  = proj.hit_radius * proj.hit_radius
		var hit_pos: Vector2 = Vector2.ZERO
		var hit: bool        = false

		# 1. Named target — check by ID first (most accurate)
		if proj.target_id != "" and not hit:
			var result: Dictionary = _resolve_target(proj.target_id, proj.zone)
			if not result.is_empty():
				if result["type"] == "enemy":
					var enemy: EnemyBase = result["node"]
					var epos: Vector2    = enemy.global_position
					if not enemy.is_dead and seg_dsq.call(epos, prev_pos, cur_pos) <= hit_r_sq:
						enemy.take_damage(proj.dmg, proj.dir, sp.get_instance_id())
						hit_pos = epos
						Network.confirm_ability_hit.rpc_id(proj.peer_id, hit_pos, proj.dmg)
						if proj.visual_id != "":
							Network.ability_visual.rpc(enemy.enemy_id, proj.visual_id)
						hit = true
				elif result["type"] == "player":
					var tgt: ServerPlayer = result["node"]
					var tpos: Vector2     = tgt.world_pos
					if not tgt.is_dead and not are_same_party(proj.peer_id, tgt.peer_id) \
							and seg_dsq.call(tpos, prev_pos, cur_pos) <= hit_r_sq:
						tgt.take_damage(proj.dmg, proj.dir, proj.peer_id)
						hit_pos = tpos
						Network.confirm_ability_hit.rpc_id(proj.peer_id, hit_pos, proj.dmg)
						if proj.visual_id != "":
							Network.ability_visual.rpc(str(tgt.peer_id), proj.visual_id)
						hit = true

		# 2. Positional sweep — untargeted cast or named target missed
		if not hit:
			for enemy: EnemyBase in get_tree().get_nodes_in_group("enemy"):
				if enemy.zone_name != proj.zone or enemy.is_dead:
					continue
				var epos: Vector2 = enemy.global_position
				if seg_dsq.call(epos, prev_pos, cur_pos) <= hit_r_sq:
					enemy.take_damage(proj.dmg, proj.dir, sp.get_instance_id())
					hit_pos = epos
					Network.confirm_ability_hit.rpc_id(proj.peer_id, hit_pos, proj.dmg)
					if proj.visual_id != "":
						Network.ability_visual.rpc(enemy.enemy_id, proj.visual_id)
					hit = true
					break
		if not hit:
			for oid: int in server_players:
				if oid == proj.peer_id or are_same_party(proj.peer_id, oid):
					continue
				var other: ServerPlayer = server_players[oid]
				if other.zone != proj.zone or other.is_dead:
					continue
				var opos: Vector2 = other.world_pos
				if seg_dsq.call(opos, prev_pos, cur_pos) <= hit_r_sq:
					other.take_damage(proj.dmg, proj.dir, proj.peer_id)
					hit_pos = opos
					Network.confirm_ability_hit.rpc_id(proj.peer_id, hit_pos, proj.dmg)
					if proj.visual_id != "":
						Network.ability_visual.rpc(str(other.peer_id), proj.visual_id)
					hit = true
					break

		# Stop on first hit (no pierce) or range exhausted
		if hit or proj.travelled >= proj.range:
			# Mark done and remove BEFORE any network calls — RPC errors must never block cleanup
			proj.done = true
			_projectiles.remove_at(i)
			if hit and proj.on_stop.is_valid():
				proj.on_stop.call(hit_pos)
		i -= 1
func _separate_players() -> void:
	var pids: Array = server_players.keys()
	for i in range(pids.size()):
		for j in range(i + 1, pids.size()):
			var a: ServerPlayer = server_players[pids[i]]
			var b: ServerPlayer = server_players[pids[j]]
			if a.is_dead or b.is_dead:
				continue
			if a.zone != b.zone:
				continue
			var delta_vec = b.world_pos - a.world_pos
			var dist = delta_vec.length()
			if dist < SEPARATION_DIST:
				# Push them apart — if exactly overlapping, use a fixed offset direction
				var push_dir = delta_vec.normalized() if dist > 0.5 else Vector2(1, 0)
				var push = push_dir * (SEPARATION_DIST - dist) * 0.5
				var new_a = _snap_to_tile(a.world_pos - push)
				var new_b = _snap_to_tile(b.world_pos + push)
				a.set_position_from_client(new_a, true)
				b.set_position_from_client(new_b, true)
				# Corrected world_pos is now in server state — broadcast will carry it
				# to remote_player nodes on the next sync tick (~50ms)

func _snap_to_tile(pos: Vector2) -> Vector2:
	return Vector2(round(pos.x / TILE_SIZE) * TILE_SIZE, round(pos.y / TILE_SIZE) * TILE_SIZE)

func _broadcast_players() -> void:
	if Network.players.is_empty():
		return
	# Build full state for all logged-in players
	var all_states: Dictionary = {}
	for peer_id in Network.players:
		var p = Network.players[peer_id]
		if p["username"] != "" and p.get("position_ready", false):
			var sp = server_players.get(peer_id, null)
			# Skip position broadcast while target is in knockback
			if sp != null and sp.knockback_timer > 0.0:
				continue
			all_states[peer_id] = {
				"username":   p["username"],
				"position":   p["position"],
				"zone":       p["zone"],
				"hp":         sp.hp         if sp else 100,
				"max_hp":     sp.max_hp     if sp else 100,
				"is_dead":    sp.is_dead    if sp else false,
				"kills":      sp.kills      if sp else 0,
				"deaths":     sp.deaths     if sp else 0,
				"level":      sp.level      if sp else 1,
				"rank":       sp.rank       if sp else "Academy Student",
				"facing_dir": sp.facing_dir if sp else "down",
				"party_id":   _party_in_party.get(peer_id, -1),
				"equipped":   sp.equipped   if sp else {},
				"gear_str":   sp._gear_str    if sp else 0,
				"gear_hp":    sp._gear_hp     if sp else 0,
				"gear_chakra":sp._gear_chakra if sp else 0,
				"gear_dex":   sp._gear_dex    if sp else 0,
				"gear_int":   sp._gear_int    if sp else 0,
				"appearance": sp.appearance if sp else {},
				"chakra":     sp.current_chakra if sp else 0,
				"max_chakra": sp.max_chakra     if sp else 100,
				"is_rooted":   sp.is_rooted   if sp else false,
				"is_spinning": sp.is_spinning if sp else false,
			}
	# Send each client only their own state + same-zone players
	# This keeps packets well under MTU regardless of player count
	for recv_id in Network.players:
		if Network.players[recv_id]["username"] == "":
			continue
		var recv_zone = Network.players[recv_id].get("zone", "")
		var states: Dictionary = {}
		var recv_party_id = _party_in_party.get(recv_id, -1)
		for peer_id in all_states:
			var s = all_states[peer_id]
			var same_zone    = s["zone"] == recv_zone
			var is_self      = peer_id == recv_id
			var is_party_member = recv_party_id != -1 and _party_in_party.get(peer_id, -2) == recv_party_id
			if is_self or same_zone or is_party_member:
				states[peer_id] = s
		if _debug_tick >= 2.95:
			for pid in states:
				var s = states[pid]
				print("[PLAYERS] %s | zone=%s | hp=%d/%d | pos=%s" % [s.get("username","?"), s.get("zone","?"), s.get("hp",0), s.get("max_hp",0), str(s.get("position", Vector2.ZERO))])
		Network.sync_players.rpc_id(recv_id, states)

func _broadcast_enemies() -> void:
	# Send each player only their zone's enemies — keeps packets under MTU
	for peer_id in Network.players:
		var p = Network.players[peer_id]
		if p["username"] == "":
			continue
		var player_zone = p.get("zone", "village")
		var zone_data: Dictionary = {}
		for id in _enemy_nodes:
			var enemy = _enemy_nodes[id]
			if not is_instance_valid(enemy):
				continue
			if enemy.zone_name != player_zone:
				continue
			# Dynamic only — position, hp, state. Static data sent once via sync_enemy_roster.
			# Skip position while in knockback — client holds the visual
			if enemy.knockback_timer > 0.0:
				continue
			zone_data[id] = {
				"position": enemy.global_position,
				"hp":       enemy.hp,
				"state":    enemy.state,
			}
		# Wrap in zone key so client can still use all_zones.get(current_zone)
		var payload = {player_zone: zone_data}
		Network.sync_enemies.rpc_id(peer_id, payload)
		# Debug: log zone + enemy count periodically
		if _debug_tick <= 0.0:
			var uname = p.get("username", str(peer_id))
			print("[SYNC] %s | zone=%s | enemies=%d" % [uname, player_zone, zone_data.size()])

func _cmd_give_all_boons(peer_id: int, text: String) -> void:
	# Usage: /boons          — give one of every boon
	#        /boons max      — give MAX_BOON_STACKS of every stackable boon
	#        /boons <id>     — give one specific boon by id
	if not _dungeon_manager:
		Network.receive_chat.rpc_id(peer_id, "system", "", "[DEBUG] Not in a dungeon.")
		return
	var inst_id = _dungeon_manager.get_instance_id_for_peer(peer_id)
	if inst_id < 0:
		Network.receive_chat.rpc_id(peer_id, "system", "", "[DEBUG] Not in a dungeon instance.")
		return
	var fc = _dungeon_manager._floor_controllers.get(inst_id, null)
	if not fc:
		Network.receive_chat.rpc_id(peer_id, "system", "", "[DEBUG] No floor controller found.")
		return

	const BoonDB = preload("res://scripts/dungeon_boon_db.gd")
	var parts = text.split(" ")
	var mode  = parts[1] if parts.size() > 1 else ""

	if mode != "" and mode != "max" and BoonDB.BOONS.has(mode):
		# Give one specific boon
		fc.player_chose_boon(peer_id, mode)
		Network.receive_chat.rpc_id(peer_id, "system", "", "[DEBUG] Gave boon: %s" % mode)
		return

	var stacks = BoonDB.MAX_BOON_STACKS if mode == "max" else 1
	var count  = 0
	for boon_id in BoonDB.BOONS:
		var boon = BoonDB.BOONS[boon_id]
		var give_stacks = stacks
		if boon.get("type") in ["passive"] and stacks > 1:
			give_stacks = 1  # passives don't meaningfully stack
		for _i in range(give_stacks):
			fc.player_chose_boon(peer_id, boon_id)
		count += 1
	Network.receive_chat.rpc_id(peer_id, "system", "", "[DEBUG] Gave %d boons (x%d stacks). Check Tab screen." % [count, stacks])

func _cmd_clear_boons(peer_id: int) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	# Reset all boon vars to defaults
	sp.boon_chakra_cost_mult       = 1.0; sp.boon_clay_dmg_mult          = 1.0
	sp.boon_c1_damage_flat         = 0;   sp.boon_c1_speed_mult          = 1.0
	sp.boon_c1_range_mult          = 1.0; sp.boon_c1_cooldown_flat       = 0.0
	sp.boon_c1_spider_count        = 1;   sp.boon_c2_cooldown_flat       = 0.0
	sp.boon_c2_orbit_duration_flat = 0.0; sp.boon_c2_drop_interval_mult  = 1.0
	sp.boon_c2_explosion_mult      = 1.0; sp.boon_c2_owl_count           = 1
	sp.boon_c3_cooldown_flat       = 0.0; sp.boon_c3_radius_mult         = 1.0
	sp.boon_c4_count_flat          = 0;   sp.boon_c4_dmg_mult            = 1.0
	sp.boon_c4_radius_mult         = 1.0; sp.dungeon_passives            = []
	# Sync to client
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		var empty = {}
		net.dungeon_boon_props.rpc_id(peer_id, empty)
		net.dungeon_stat_sync.rpc_id(peer_id, sp.max_hp, sp.max_chakra)
	# Also clear held_boons in floor controller
	if _dungeon_manager:
		var inst_id = _dungeon_manager.get_instance_id_for_peer(peer_id)
		var fc = _dungeon_manager._floor_controllers.get(inst_id, null)
		if fc and fc._held_boons.has(peer_id):
			fc._held_boons[peer_id] = []
	Network.receive_chat.rpc_id(peer_id, "system", "", "[DEBUG] All boons cleared.")

func _is_chat_spam(text: String) -> bool:
	# 1. 5+ consecutive identical characters (aaaaa, 11111)
	var run = 1
	for i in range(1, text.length()):
		if text[i] == text[i - 1]:
			run += 1
			if run >= 5:
				return true
		else:
			run = 1
	# 2. No spaces + long + no vowels  (pure keyboard smash)
	if " " not in text and text.length() > 8:
		var has_vowel = false
		for c in text.to_lower():
			if c in "aeiou":
				has_vowel = true
				break
		if not has_vowel:
			return true
	# 3. One character makes up >65% of message (no spaces)
	if " " not in text and text.length() > 6:
		var counts: Dictionary = {}
		for c in text:
			counts[c] = counts.get(c, 0) + 1
		for c in counts:
			if float(counts[c]) / text.length() > 0.65:
				return true
	return false

func _on_chat(peer_id: int, channel: String, target_name: String, text: String) -> void:
	var sender_data = Network.players.get(peer_id, {})
	var sender_name = sender_data.get("username", "Unknown")
	text = text.substr(0, 200)

	# ── Debug commands ────────────────────────────────────────
	if text.begins_with("/boons"):
		_cmd_give_all_boons(peer_id, text)
		return
	if text == "/clearboons":
		_cmd_clear_boons(peer_id)
		return
	# Spam filter — only applies to zone and global chat (not whispers/party/system)
	if channel in ["zone", "global"] and _is_chat_spam(text):
		Network.receive_chat.rpc_id(peer_id, "system", "", "Message blocked: looks like spam.")
		return
	match channel:
		"global":
			for pid in Network.players:
				if Network.players[pid].get("username", "") != "":
					Network.receive_chat.rpc_id(pid, "global", sender_name, text)
		"whisper":
			var target_id = -1
			for pid in Network.players:
				if Network.players[pid].get("username", "").to_lower() == target_name.to_lower():
					target_id = pid
					break
			if target_id == -1:
				Network.receive_chat.rpc_id(peer_id, "system", "", "Player '%s' not found." % target_name)
			else:
				Network.receive_chat.rpc_id(target_id, "whisper", sender_name, text)
				Network.receive_chat.rpc_id(peer_id, "whisper_out", target_name, text)
		"party":
			if _party_in_party.has(peer_id):
				var party_id = _party_in_party[peer_id]
				for pid in _party_parties[party_id]["members"]:
					Network.receive_chat.rpc_id(pid, "party", sender_name, text)
		_:
			var sender_zone = sender_data.get("zone", "village")
			for pid in Network.players:
				var pdata = Network.players[pid]
				if pdata.get("username", "") != "" and pdata.get("zone", "village") == sender_zone:
					Network.receive_chat.rpc_id(pid, "zone", sender_name, text)

func broadcast_rank_up(username: String, new_rank: String) -> void:
	var msg = "★ %s has achieved the rank of %s!" % [username, new_rank]
	for pid in Network.players:
		if Network.players[pid].get("username", "") != "":
			Network.receive_chat.rpc_id(pid, "system", "", msg)

func broadcast_kill(killer_name: String, victim_name: String) -> void:
	# Increment killer's kill count
	for pid in server_players:
		if server_players[pid].username == killer_name:
			server_players[pid].kills += 1
			break
	for pid in Network.players:
		if Network.players[pid].get("username", "") != "":
			Network.receive_chat.rpc_id(pid, "kill", killer_name, victim_name)

func _on_max_hp(peer_id: int, max_value: int, current_value: int) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].max_hp = max_value
		server_players[peer_id].hp     = current_value

# ── Party helpers ───────────────────────────────────────────

func _on_spend_stats(peer_id: int, hp: int, chakra: int, strength: int, dex: int, int_: int) -> void:
	var sp = server_players.get(peer_id, null)
	if sp == null:
		return
	# Count total points being spent and validate against available
	var prev_total = sp.stat_hp + sp.stat_chakra + sp.stat_strength + sp.stat_dex + sp.stat_int
	var new_total  = hp + chakra + strength + dex + int_
	var spent      = new_total - prev_total
	if spent < 0 or spent > sp.stat_points:
		print("[SERVER] Stat spend rejected for %s — tried to spend %d, has %d" % [sp.username, spent, sp.stat_points])
		return
	sp.stat_hp       = hp
	sp.stat_chakra   = chakra
	sp.stat_strength = strength
	sp.stat_dex      = dex
	sp.stat_int      = int_
	sp.stat_points  -= spent
	# Recalculate max_hp from stat
	sp.max_hp        = 100 + hp * 5
	sp.hp            = min(sp.hp, sp.max_hp)
	Database.save_player(sp.username, sp.get_save_data())

func _on_quest_accept(peer_id: int, quest_id: String) -> void:
	var sp = server_players.get(peer_id, null)
	if sp == null:
		return
	var qdef = QuestDB.get_quest(quest_id)
	if qdef.is_empty():
		return
	# Reject if already accepted
	if sp.quest_state.has(quest_id):
		return
	# Check prereq met
	var prereq = qdef.get("prereq", "")
	if prereq != "":
		if sp.quest_state.get(prereq, {}).get("status", "") != "turned_in":
			print("[SERVER] Quest %s rejected for %s — prereq not met" % [quest_id, sp.username])
			return
	sp.quest_state[quest_id] = {"status": "active", "progress": 0}
	Database.save_player(sp.username, sp.get_save_data())
	print("[SERVER] %s accepted quest: %s" % [sp.username, quest_id])

func _on_quest_complete(peer_id: int, quest_id: String) -> void:
	var sp = server_players.get(peer_id, null)
	if sp == null:
		return
	var qdef = QuestDB.get_quest(quest_id)
	if qdef.is_empty():
		return
	var qs = sp.quest_state.get(quest_id, {})
	if qs.get("status") != "active":
		print("[SERVER] Quest %s complete rejected — not active for %s" % [quest_id, sp.username])
		return
	# Validate kill progress
	if qdef.get("type") == "kill":
		if qs.get("progress", 0) < qdef.get("required", 1):
			print("[SERVER] Quest %s complete rejected — progress insufficient for %s" % [quest_id, sp.username])
			return
	# Grant rewards
	var reward_xp   = qdef.get("reward_xp",   0)
	var reward_gold = qdef.get("reward_gold", 0)
	if reward_xp > 0:
		sp.grant_xp(reward_xp)
	if reward_gold > 0:
		sp.grant_gold(reward_gold)
	sp.quest_state[quest_id] = {"status": "turned_in", "progress": qdef.get("required", 1)}
	# Genin promotion on academy quest
	if quest_id == "q_enroll_academy":
		sp.rank = "Genin"
		var net_r = get_tree().root.get_node_or_null("Network")
		if net_r:
			net_r.notify_rank_up.rpc_id(peer_id, "Genin")
	# Mark intro complete on final intro quest
	if quest_id == "q_report_to_missions":
		sp.has_done_intro = true
	# Auto-assign followup intro chain quests (no dialogue needed)
	var followup = QuestDB.get_auto_followup(quest_id)
	if followup != "" and not sp.quest_state.has(followup):
		sp.quest_state[followup] = {"status": "active", "progress": 0}
	Database.save_player(sp.username, sp.get_save_data())
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.notify_quest_turned_in.rpc_id(peer_id, quest_id, reward_xp, reward_gold)
		if followup != "":
			net.notify_quest_accepted.rpc_id(peer_id, followup)
	print("[SERVER] %s completed quest: %s (+%d xp, +%d gold)" % [sp.username, quest_id, reward_xp, reward_gold])

# ── Intro / Escort / Training Handlers ───────────────────────────────────

func _on_escort_started(peer_id: int) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	# Auto-accept intro quest and notify client
	if not sp.quest_state.has("q_meet_the_jonin"):
		sp.quest_state["q_meet_the_jonin"] = {"status": "active", "progress": 0}
		Database.save_player(sp.username, sp.get_save_data())
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			net.notify_quest_accepted.rpc_id(peer_id, "q_meet_the_jonin")

func _on_escort_completed(peer_id: int) -> void:
	# Escort is done — quest advances when player talks to Jonin (handled by quest system)
	pass

func _on_training_complete(peer_id: int) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	if sp.quest_state.get("q_basic_training", {}).get("status") == "active":
		sp.quest_state["q_basic_training"]["progress"] = 1
		Database.save_player(sp.username, sp.get_save_data())
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			net.notify_quest_progress.rpc_id(peer_id, "q_basic_training", 1, 1)

# ── Mission Handlers ──────────────────────────────────────────────────────

func _on_mission_board_request(peer_id: int, rank: String) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	var pool: Array = MissionDB.get_rank_pool(rank)
	var completed: Array = sp.board_completed.get(rank, [])
	# Check if all missions in pool are completed — if so, refresh
	var all_done = pool.size() > 0
	for mid in pool:
		if mid not in completed:
			all_done = false
			break
	if all_done:
		sp.board_completed[rank] = []
		completed = []
	# Available = pool minus completed and current active
	var available: Array = []
	for mid in pool:
		if mid not in completed and mid != sp.active_mission:
			available.append(mid)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.mission_board_data.rpc_id(peer_id, rank, available, sp.active_mission, sp.mission_progress)

func _on_mission_accept(peer_id: int, mission_id: String) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	if sp.active_mission != "":
		return  # already has one
	var mdef = MissionDB.get_mission(mission_id)
	if mdef.is_empty():
		return
	# Rank gate check
	var min_rank = mdef.get("min_rank", "Academy Student")
	if not RankDB.meets_rank_requirement(sp.rank, min_rank):
		return
	var mission_data = mdef.duplicate()
	# For deliver missions — assign a random target from pool
	if mdef["type"] == "deliver":
		var pool: Array = mdef.get("target_pool", [])
		if not pool.is_empty():
			mission_data["assigned_target"] = pool[randi() % pool.size()]
		# Grant the letter item
		sp.grant_item(mdef.get("letter_item", "mission_letter"), 1)
	sp.active_mission   = mission_id
	sp.mission_progress = 0
	sp.mission_data     = mission_data
	Database.save_player(sp.username, sp.get_save_data())
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.mission_accepted.rpc_id(peer_id, mission_data, 0)
	print("[MISSION] %s accepted: %s" % [sp.username, mission_id])

func _on_mission_abandon(peer_id: int) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp or sp.active_mission == "":
		return
	# Remove letter if it was a deliver mission
	var mdef = sp.mission_data
	if mdef.get("type") == "deliver":
		sp.consume_item(mdef.get("letter_item", "mission_letter"))
	sp.active_mission   = ""
	sp.mission_progress = 0
	sp.mission_data     = {}
	Database.save_player(sp.username, sp.get_save_data())
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.mission_abandoned.rpc_id(peer_id)

func _on_mission_complete(peer_id: int) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp or sp.active_mission == "":
		return
	var mdef    = sp.mission_data
	var mid     = sp.active_mission
	var mtype   = mdef.get("type", "")
	var required = mdef.get("required", 1)
	# Validate completion
	var valid = false
	match mtype:
		"kill":
			valid = sp.mission_progress >= required
		"collect":
			# Check current inventory — not delta since accept
			var item_id = mdef.get("item_id", "")
			valid = sp.inventory.get(item_id, 0) >= required
		"deliver":
			valid = sp.mission_progress >= 1  # set when talk to assigned NPC
	if not valid:
		return
	# Consume collected items
	if mtype == "collect":
		var item_id = mdef.get("item_id", "")
		for i in range(required):
			sp.consume_item(item_id)
	# Grant rewards
	var xp   = mdef.get("reward_xp",   0)
	var gold = mdef.get("reward_gold", 0)
	if xp   > 0: sp.grant_xp(xp)
	if gold > 0: sp.grant_gold(gold)
	# Mark board completed
	var rank = mdef.get("rank", "D")
	if not sp.board_completed.has(rank):
		sp.board_completed[rank] = []
	if mid not in sp.board_completed[rank]:
		sp.board_completed[rank].append(mid)
	sp.active_mission   = ""
	sp.mission_progress = 0
	sp.mission_data     = {}
	Database.save_player(sp.username, sp.get_save_data())
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.mission_completed.rpc_id(peer_id, mid, xp, gold)
	print("[MISSION] %s completed: %s (+%d xp, +%d gold)" % [sp.username, mid, xp, gold])

func _on_mission_deliver_talk(peer_id: int, npc_name: String) -> void:
	# Called when a player with an active deliver mission talks to an NPC
	var sp = server_players.get(peer_id, null)
	if not sp or sp.active_mission == "":
		return
	var mdef = sp.mission_data
	if mdef.get("type") != "deliver":
		return
	if npc_name != mdef.get("assigned_target", ""):
		return
	if not sp.has_item(mdef.get("letter_item", "mission_letter")):
		return
	sp.consume_item(mdef.get("letter_item", "mission_letter"))
	sp.mission_progress = 1
	Database.save_player(sp.username, sp.get_save_data())
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.mission_progress_update.rpc_id(peer_id, 1, 1)

func _emit_visual(target_id_str: String, visual_id: String) -> void:
	# Send to all remote clients via RPC, then fire directly on host (peer 1 never
	# receives its own authority RPCs, so rpc_id(1,...) is a no-op for the host).
	Network.ability_visual.rpc(target_id_str, visual_id)
	Network.ability_visual_received.emit(target_id_str, visual_id, Vector2.ZERO)

func _emit_visual_ex(target_id_str: String, visual_id: String, extra: Vector2) -> void:
	Network.ability_visual.rpc(target_id_str, visual_id, extra)
	Network.ability_visual_received.emit(target_id_str, visual_id, extra)

func are_same_party(peer_a: int, peer_b: int) -> bool:
	# Returns true if both peers are in the same party (used for friendly fire prevention)
	if not _party_in_party.has(peer_a) or not _party_in_party.has(peer_b):
		return false
	return _party_in_party[peer_a] == _party_in_party[peer_b]

# ── Party functions (inlined from party_manager) ─────────────

func _party_invite(inviter_id: int, target_name: String) -> void:
	# Resolve target peer_id by username
	var target_id = -1
	for pid in server_players:
		if server_players[pid].username == target_name:
			target_id = pid
			break
	if target_id == -1:
		Network.receive_party_msg.rpc_id(inviter_id, "system", "Player '%s' is not online." % target_name)
		return
	if target_id == inviter_id:
		Network.receive_party_msg.rpc_id(inviter_id, "system", "You cannot invite yourself.")
		return
	if _party_in_party.has(target_id):
		Network.receive_party_msg.rpc_id(inviter_id, "system", "%s is already in a party." % target_name)
		return
	var inviter_name = server_players[inviter_id].username
	print("[PARTY] Inviting peer %d (%s) -> peer %d (%s)" % [inviter_id, inviter_name, target_id, target_name])
	Network.receive_party_invite.rpc_id(target_id, inviter_name)
	Network.receive_party_msg.rpc_id(inviter_id, "system", "Party invite sent to %s." % target_name)

func _party_accept(accepter_id: int, inviter_name: String) -> void:
	var inviter_id = -1
	for pid in server_players:
		if server_players[pid].username == inviter_name:
			inviter_id = pid
			break
	if inviter_id == -1:
		Network.receive_party_msg.rpc_id(accepter_id, "system", "Invite expired — player disconnected.")
		return
	if _party_in_party.has(accepter_id):
		Network.receive_party_msg.rpc_id(accepter_id, "system", "You are already in a party.")
		return
	var party_id: int
	if _party_in_party.has(inviter_id):
		party_id = _party_in_party[inviter_id]
		if _party_parties[party_id]["members"].size() >= 4:
			Network.receive_party_msg.rpc_id(accepter_id, "system", "That party is full (max 4).")
			return
		_party_parties[party_id]["members"].append(accepter_id)
	else:
		party_id = _party_next_id
		_party_next_id += 1
		_party_parties[party_id] = { "leader": inviter_id, "members": [inviter_id, accepter_id] }
		_party_in_party[inviter_id] = party_id
	_party_in_party[accepter_id] = party_id
	_party_broadcast(party_id)

func _party_decline(decliner_id: int, inviter_name: String) -> void:
	var inviter_id = -1
	for pid in server_players:
		if server_players[pid].username == inviter_name:
			inviter_id = pid
			break
	var decliner_name = server_players[decliner_id].username if server_players.has(decliner_id) else "?"
	if inviter_id != -1:
		Network.receive_party_msg.rpc_id(inviter_id, "system", "%s declined your party invite." % decliner_name)

func _party_leave(peer_id: int, silent: bool = false) -> void:
	if not _party_in_party.has(peer_id):
		return
	var party_id = _party_in_party[peer_id]
	var party = _party_parties[party_id]
	party["members"].erase(peer_id)
	_party_in_party.erase(peer_id)
	var leaving_name = server_players[peer_id].username if server_players.has(peer_id) else "?"
	if not silent:
		Network.receive_party_msg.rpc_id(peer_id, "system", "You left the party.")
		Network.receive_party_update.rpc_id(peer_id, { "members": [], "leader": "" })
	if party["members"].is_empty():
		_party_parties.erase(party_id)
		return
	if party["leader"] == peer_id:
		party["leader"] = party["members"][0]
		var new_leader = server_players[party["leader"]].username if server_players.has(party["leader"]) else "?"
		for pid in party["members"]:
			Network.receive_party_msg.rpc_id(pid, "system", "%s left. %s is now leader." % [leaving_name, new_leader])
	else:
		for pid in party["members"]:
			Network.receive_party_msg.rpc_id(pid, "system", "%s left the party." % leaving_name)
	if party["members"].size() == 1:
		var last = party["members"][0]
		_party_in_party.erase(last)
		_party_parties.erase(party_id)
		Network.receive_party_msg.rpc_id(last, "system", "Party disbanded.")
		Network.receive_party_update.rpc_id(last, { "members": [], "leader": "" })
		return
	_party_broadcast(party_id)

func _party_broadcast(party_id: int) -> void:
	var party = _party_parties[party_id]
	var names = []
	for pid in party["members"]:
		if server_players.has(pid):
			names.append(server_players[pid].username)
	var leader_name = server_players[party["leader"]].username if server_players.has(party["leader"]) else ""
	var data = { "members": names, "leader": leader_name }
	for pid in party["members"]:
		Network.receive_party_update.rpc_id(pid, data)

func _party_kick(kicker_id: int, target_name: String) -> void:
	if not _party_in_party.has(kicker_id):
		return
	var party_id = _party_in_party[kicker_id]
	if _party_parties[party_id]["leader"] != kicker_id:
		return  # only leader can kick
	# Find target peer
	var target_id = -1
	for pid in server_players:
		if server_players[pid].username == target_name:
			target_id = pid
			break
	if target_id == -1 or target_id == kicker_id:
		return
	if not _party_in_party.has(target_id) or _party_in_party[target_id] != party_id:
		return
	# Remove target
	_party_parties[party_id]["members"].erase(target_id)
	_party_in_party.erase(target_id)
	Network.receive_party_msg.rpc_id(target_id, "system", "You were kicked from the party.")
	Network.receive_party_update.rpc_id(target_id, { "members": [], "leader": "" })
	var kicker_name = server_players[kicker_id].username
	for pid in _party_parties[party_id]["members"]:
		Network.receive_party_msg.rpc_id(pid, "system", "%s was kicked." % target_name)
	if _party_parties[party_id]["members"].size() == 1:
		var last = _party_parties[party_id]["members"][0]
		_party_in_party.erase(last)
		_party_parties.erase(party_id)
		Network.receive_party_msg.rpc_id(last, "system", "Party disbanded.")
		Network.receive_party_update.rpc_id(last, { "members": [], "leader": "" })
		return
	_party_broadcast(party_id)

func _party_promote(promoter_id: int, target_name: String) -> void:
	if not _party_in_party.has(promoter_id):
		return
	var party_id = _party_in_party[promoter_id]
	if _party_parties[party_id]["leader"] != promoter_id:
		return  # only leader can promote
	var target_id = -1
	for pid in server_players:
		if server_players[pid].username == target_name:
			target_id = pid
			break
	if target_id == -1 or target_id == promoter_id:
		return
	if not _party_in_party.has(target_id) or _party_in_party[target_id] != party_id:
		return
	_party_parties[party_id]["leader"] = target_id
	var promoter_name = server_players[promoter_id].username
	for pid in _party_parties[party_id]["members"]:
		Network.receive_party_msg.rpc_id(pid, "system", "%s promoted %s to leader." % [promoter_name, target_name])
	_party_broadcast(party_id)

# ── Clay Clan Ability Handlers ────────────────────────────────────────────────

func _on_c1_spiders(peer_id: int, data: Dictionary, sp) -> void:
	var aim_dir:    Vector2 = (data.get("aim_dir", Vector2.RIGHT) as Vector2).normalized()
	var caster_pos: Vector2 = sp.world_pos
	var target_id:  String  = data.get("target_id", "")

	# ── Boon modifiers ────────────────────────────────────────
	var dmg:        int   = data.get("damage", 32) + sp.boon_c1_damage_flat
	var proj_speed: float = data.get("speed",  160.0) * sp.boon_c1_speed_mult
	var proj_range: float = data.get("range",  800.0) * sp.boon_c1_range_mult
	var clay_mult:  float = sp.boon_clay_dmg_mult
	dmg = int(dmg * clay_mult)
	var spider_count: int = sp.boon_c1_spider_count
	var pierce:      bool = "c1_pierce" in sp.dungeon_passives
	# ──────────────────────────────────────────────────────────

	# Snap to 4-cardinal for spider animation name
	var dir_str: String
	if abs(aim_dir.x) >= abs(aim_dir.y):
		dir_str = "right" if aim_dir.x >= 0.0 else "left"
	else:
		dir_str = "down" if aim_dir.y >= 0.0 else "up"

	# Spawn spider_count spiders, spread slightly if more than one
	for s in range(spider_count):
		var spread_angle = 0.0
		if spider_count > 1:
			spread_angle = deg_to_rad(-15.0 + (30.0 / (spider_count - 1)) * s)
		var s_dir: Vector2 = aim_dir.rotated(spread_angle)
		var s_dir_str = dir_str
		if spider_count > 1:
			if abs(s_dir.x) >= abs(s_dir.y):
				s_dir_str = "right" if s_dir.x >= 0.0 else "left"
			else:
				s_dir_str = "down" if s_dir.y >= 0.0 else "up"

		_clay_spider_counter += 1
		var spider_id: String = "spider_%d_%d" % [peer_id, _clay_spider_counter]
		var endpoint:  Vector2 = caster_pos + s_dir * proj_range

		for pid: int in multiplayer.get_peers():
			Network.clay_spider_visual.rpc_id(pid, peer_id, spider_id, caster_pos, endpoint, s_dir_str, proj_speed)

		var proj        = ServerProjectile.new()
		proj.peer_id    = peer_id
		proj.pos        = caster_pos
		proj.dir        = s_dir
		proj.dmg        = dmg
		proj.range      = proj_range
		proj.speed      = proj_speed
		proj.hit_radius = 18.0
		proj.target_id  = target_id
		proj.zone       = sp.zone
		proj.visual_id  = ""
		if pierce:
			proj.set_meta("pierce", true)

		_clay_spider_projs[spider_id] = proj

		var sid_cap = spider_id  # capture for closure
		proj.on_stop = func(hit_pos: Vector2) -> void:
			_clay_spider_projs.erase(sid_cap)
			for pid: int in multiplayer.get_peers():
				Network.clay_spider_stop.rpc_id(pid, sid_cap, hit_pos)

		_projectiles.append(proj)

# ── Kagura detonation hook — uncomment and fill damage logic when implementing Kagura ──
# func _detonate_spiders(peer_id: int) -> void:
# 	for sid in _clay_spider_projs.keys().duplicate():
# 		if not sid.begins_with("spider_%d_" % peer_id):
# 			continue
# 		var proj = _clay_spider_projs[sid]
# 		if proj.done:
# 			continue
# 		proj.done = true
# 		var hit_pos = proj.pos
# 		_clay_spider_projs.erase(sid)
# 		for pid in multiplayer.get_peers():
# 			Network.clay_spider_stop.rpc_id(pid, sid, hit_pos)
# 		# TODO: deal splash damage to enemies/players near hit_pos

func _on_c2_owl(peer_id: int, data: Dictionary, sp) -> void:
	var caster_pos: Vector2 = sp.world_pos
	var target_id:  String  = data.get("target_id", "")
	if target_id == "":
		return

	# ── Boon modifiers ────────────────────────────────────────
	var owl_count:       int   = sp.boon_c2_owl_count
	var orbit_bonus:     float = sp.boon_c2_orbit_duration_flat
	var drop_mult:       float = sp.boon_c2_drop_interval_mult
	var explode_mult:    float = sp.boon_c2_explosion_mult
	var clay_mult:       float = sp.boon_clay_dmg_mult
	var homing_dash:     bool  = "c2_homing_dash" in sp.dungeon_passives
	# ──────────────────────────────────────────────────────────

	for _owl_i in range(owl_count):
		_clay_owl_counter += 1
		var owl_id: String = "owl_%d_%d" % [peer_id, _clay_owl_counter]

		var owl       = ServerClayOwl.new()
		owl.owl_id        = owl_id
		owl.peer_id       = peer_id
		owl.zone          = sp.zone
		owl.cast_room_id  = sp.dungeon_room_id
		owl.pos           = caster_pos
		owl.target_id     = target_id
		owl.orbit_timer    += orbit_bonus
		owl.drop_timer      = ServerClayOwl.DROP_INTERVAL * max(drop_mult, 0.1)
		owl.homing_on_dash  = homing_dash

		for pid: int in multiplayer.get_peers():
			Network.clay_owl_spawn.rpc_id(pid, owl_id, peer_id, caster_pos, target_id)

		var oid_cap = owl_id
		owl.on_sync = func(pos: Vector2, dir_str: String) -> void:
			for pid: int in multiplayer.get_peers():
				Network.clay_owl_move.rpc_id(pid, oid_cap, pos, dir_str)

		owl.on_drop_spider = func(drop_pos: Vector2, aim_dir: Vector2) -> void:
			_clay_spider_counter += 1
			var spider_id: String = "spider_%d_%d" % [peer_id, _clay_spider_counter]
			var dir_str: String
			if abs(aim_dir.x) >= abs(aim_dir.y):
				dir_str = "right" if aim_dir.x >= 0.0 else "left"
			else:
				dir_str = "down" if aim_dir.y >= 0.0 else "up"
			var endpoint = drop_pos + aim_dir * 800.0
			for pid: int in multiplayer.get_peers():
				Network.clay_spider_visual.rpc_id(pid, peer_id, spider_id, drop_pos, endpoint, dir_str)
			var proj        = ServerProjectile.new()
			proj.peer_id    = peer_id
			proj.pos        = drop_pos
			proj.dir        = aim_dir
			proj.dmg        = int(16 * clay_mult)
			proj.range      = 800.0
			proj.speed      = 160.0
			proj.hit_radius = 18.0
			proj.zone       = sp.zone
			proj.visual_id  = ""
			var sid_cap2 = spider_id
			_clay_spider_projs[spider_id] = proj
			proj.on_stop = func(hit_pos: Vector2) -> void:
				_clay_spider_projs.erase(sid_cap2)
				for pid: int in multiplayer.get_peers():
					Network.clay_spider_stop.rpc_id(pid, sid_cap2, hit_pos)
			_projectiles.append(proj)

		var explode_dmg: int = int(ServerClayOwl.EXPLOSION_DMG * explode_mult * clay_mult)
		var explode_rad: float = ServerClayOwl.EXPLOSION_RADIUS
		var owl_zone_cap: String = sp.zone  # capture zone at spawn time
		owl.on_explode = func(explode_pos: Vector2) -> void:
			_clay_owls.erase(oid_cap)
			for pid: int in multiplayer.get_peers():
				Network.clay_owl_explode.rpc_id(pid, oid_cap, explode_pos)
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if enemy.zone_name != owl_zone_cap or enemy.is_dead:
					continue
				if enemy.global_position.distance_to(explode_pos) <= explode_rad:
					enemy.take_damage(explode_dmg, Vector2.ZERO, sp.get_instance_id())
					Network.confirm_ability_hit.rpc_id(peer_id, enemy.global_position, explode_dmg)
			for oid: int in server_players:
				if oid == peer_id or are_same_party(peer_id, oid):
					continue
				var other: ServerPlayer = server_players[oid]
				if other.zone != owl_zone_cap or other.is_dead:
					continue
				if other.world_pos.distance_to(explode_pos) <= explode_rad:
					other.take_damage(explode_dmg, Vector2.ZERO, peer_id)
					Network.confirm_ability_hit.rpc_id(peer_id, other.world_pos, explode_dmg)

		_clay_owls[oid_cap] = owl

func _step_clay_owls(delta: float) -> void:
	if _clay_owls.is_empty():
		return
	for owl_id in _clay_owls.keys().duplicate():
		var owl: ServerClayOwl = _clay_owls[owl_id]
		if owl.done:
			_clay_owls.erase(owl_id)
			continue
		var sp: ServerPlayer = server_players.get(owl.peer_id, null)
		# Kill owl if caster has moved to a different room (dungeon rooms share world coords)
		if sp != null and sp.dungeon_room_id >= 0 and sp.dungeon_room_id != owl.cast_room_id:
			owl.done = true
			_clay_owls.erase(owl_id)
			for pid: int in multiplayer.get_peers():
				Network.clay_owl_explode.rpc_id(pid, owl_id, owl.pos)
			continue
		# Use caster's live locked_target_id so owl tracks target switches
		var live_target_id: String = owl.target_id
		if sp != null and sp.locked_target_id != "":
			live_target_id = sp.locked_target_id
		# Resolve target position
		var result = _resolve_target(live_target_id, owl.zone)
		var target_pos: Vector2 = owl.pos  # fallback
		if not result.is_empty():
			target_pos = result["node"].global_position if result["type"] == "enemy" \
				else result["node"].world_pos
		owl.step(delta, target_pos, live_target_id)
		if owl.done:
			_clay_owls.erase(owl_id)

# ── C3 Bomb ───────────────────────────────────────────────────────────────────

func _on_c3_bomb(peer_id: int, data: Dictionary, sp) -> void:
	var bomb_pos: Vector2 = data.get("caster_pos", sp.world_pos)

	# ── Boon modifiers ────────────────────────────────────────
	var radius_mult:   float = sp.boon_c3_radius_mult
	var clay_mult:     float = sp.boon_clay_dmg_mult
	var double_det:    bool  = "c3_double_det" in sp.dungeon_passives
	var invisible_c3:  bool  = "c3_invisible" in sp.dungeon_passives
	# ──────────────────────────────────────────────────────────

	_clay_bomb_counter += 1
	var bomb_id: String = "bomb_%d_%d" % [peer_id, _clay_bomb_counter]

	var bomb        = ServerClayBomb.new()
	bomb.bomb_id      = bomb_id
	bomb.peer_id      = peer_id
	bomb.zone         = sp.zone
	bomb.cast_room_id = sp.dungeon_room_id
	bomb.pos          = bomb_pos
	bomb.radius_mult  = radius_mult
	bomb.invisible    = invisible_c3

	var initial_radius = ServerClayBomb.STAGES[0][0] * radius_mult
	for pid: int in multiplayer.get_peers():
		Network.clay_bomb_spawn.rpc_id(pid, bomb_id, bomb_pos, 0, initial_radius)

	bomb.on_stage_change = func(stage: int, radius: float) -> void:
		for pid: int in multiplayer.get_peers():
			Network.clay_bomb_stage.rpc_id(pid, bomb_id, stage, radius)

	var bid_cap = bomb_id
	var bomb_room_id: int = sp.dungeon_room_id  # capture room at cast time
	var _c3_explode = func(explode_pos: Vector2, radius: float, damage: int, is_second: bool = false) -> void:
		if not is_second:
			_clay_bombs.erase(bid_cap)
			for pid: int in multiplayer.get_peers():
				Network.clay_bomb_explode.rpc_id(pid, bid_cap, explode_pos, radius)
		# Skip damage if caster moved to a different dungeon room
		var sp_now: ServerPlayer = server_players.get(peer_id, null)
		if sp_now != null and bomb_room_id >= 0 and sp_now.dungeon_room_id != bomb_room_id:
			return
		var final_dmg = int(damage * clay_mult)
		if is_second:
			final_dmg = int(final_dmg * 0.6)
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if enemy.zone_name != sp.zone or enemy.is_dead:
				continue
			if enemy.global_position.distance_to(explode_pos) <= radius:
				enemy.take_damage(final_dmg, Vector2.ZERO, sp.get_instance_id())
				Network.confirm_ability_hit.rpc_id(peer_id, enemy.global_position, final_dmg)
		# Deliberately skip caster and party — C3 no longer hits friendlies

	bomb.on_explode = func(explode_pos: Vector2, radius: float, damage: int) -> void:
		_c3_explode.call(explode_pos, radius, damage, false)
		if double_det:
			get_tree().create_timer(1.2).timeout.connect(
				func() -> void: _c3_explode.call(explode_pos, radius, damage, true),
				CONNECT_ONE_SHOT)

	_clay_bombs[bomb_id] = bomb

func _step_clay_bombs(delta: float) -> void:
	if _clay_bombs.is_empty():
		return
	for bomb_id in _clay_bombs.keys().duplicate():
		var bomb: ServerClayBomb = _clay_bombs[bomb_id]
		if bomb.done:
			_clay_bombs.erase(bomb_id)
			continue
		bomb.step(delta)
		if bomb.done:
			_clay_bombs.erase(bomb_id)

# ── C4 Karura ─────────────────────────────────────────────────────────────────

func _on_c4_karura(peer_id: int, data: Dictionary, sp) -> void:
	var origin: Vector2 = data.get("caster_pos", sp.world_pos)
	const DRIFT_SPEED  = 40.0
	const DRIFT_TIME   = 8.0
	const MAX_DISTANCE = DRIFT_SPEED * DRIFT_TIME * 1.5

	# ── Boon modifiers ────────────────────────────────────────
	var count:        int   = 480 + sp.boon_c4_count_flat
	var dmg_mult:     float = sp.boon_c4_dmg_mult
	var radius_mult:  float = sp.boon_c4_radius_mult
	var clay_mult:    float = sp.boon_clay_dmg_mult
	var double_det:   bool  = "c4_double_det" in sp.dungeon_passives
	var base_dmg:     int   = int(32 * dmg_mult * clay_mult)
	var hit_radius:   float = 48.0 * radius_mult
	# ──────────────────────────────────────────────────────────

	_c4_counter += 1
	var swarm_id: String = "c4_%d_%d" % [peer_id, _c4_counter]
	var seed_val: int    = randi()

	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	var positions: Array = []
	for i in range(count):
		var base_angle = (TAU / count) * i
		var jitter     = rng.randf_range(-0.18, 0.18)
		var angle      = base_angle + jitter
		var dir        = Vector2(cos(angle), sin(angle))
		var drift_dist = rng.randf_range(MAX_DISTANCE * 0.1, MAX_DISTANCE)
		positions.append(origin + dir * drift_dist)

	for pid: int in multiplayer.get_peers():
		Network.c4_spawn.rpc_id(pid, swarm_id, origin, seed_val, count, sp.zone)

	_c4_swarms[swarm_id] = {
		"timer":       DRIFT_TIME,
		"positions":   positions,
		"seed_val":    seed_val,
		"zone":        sp.zone,
		"room_id":     sp.dungeon_room_id,
		"peer_id":     peer_id,
		"base_dmg":    base_dmg,
		"hit_radius":  hit_radius,
		"double_det":  double_det,
	}

func _step_c4_swarms(delta: float) -> void:
	if _c4_swarms.is_empty():
		return
	for swarm_id in _c4_swarms.keys().duplicate():
		var swarm = _c4_swarms[swarm_id]
		swarm["timer"] -= delta
		if swarm["timer"] <= 0.0:
			_c4_swarms.erase(swarm_id)
			var positions: Array  = swarm["positions"]
			var zone:      String = swarm["zone"]
			var peer_id:   int    = swarm["peer_id"]
			var sp: ServerPlayer  = server_players.get(peer_id, null)
			# If caster moved to a different room, cancel — no damage, no visual
			var cast_room_id: int = swarm.get("room_id", -1)
			if sp != null and cast_room_id >= 0 and sp.dungeon_room_id != cast_room_id:
				continue

			# Send chain explode RPC to all clients
			for pid: int in multiplayer.get_peers():
				Network.c4_chain_explode.rpc_id(pid, swarm_id, swarm["seed_val"], positions.size(), 0.01, zone)

			# Randomize detonation order — read boon-modified values from swarm dict
			var dmg        : int   = swarm.get("base_dmg",   32)
			var hit_rad    : float = swarm.get("hit_radius", 48.0)
			var double_det : bool  = swarm.get("double_det", false)
			var indices = range(positions.size())
			indices.shuffle()
			var _do_wave = func(delay_mult: float, dmg_override: int) -> void:
				for i in range(indices.size()):
					var pos2d: Vector2 = positions[indices[i]]
					get_tree().create_timer(i * 0.01 * delay_mult).timeout.connect(func() -> void:
						for enemy in get_tree().get_nodes_in_group("enemy"):
							if enemy.zone_name != zone or enemy.is_dead:
								continue
							if enemy.global_position.distance_to(pos2d) <= hit_rad:
								enemy.take_damage(dmg_override, Vector2.ZERO, sp.get_instance_id() if sp else 0)
								if sp:
									Network.confirm_ability_hit.rpc_id(peer_id, enemy.global_position, dmg_override)
						for oid: int in server_players:
							if oid == peer_id:
								continue
							var other: ServerPlayer = server_players[oid]
							if other.zone != zone or other.is_dead:
								continue
							if other.world_pos.distance_to(pos2d) <= hit_rad:
								other.take_damage(dmg_override, Vector2.ZERO, peer_id)
								if sp:
									Network.confirm_ability_hit.rpc_id(peer_id, other.world_pos, dmg_override)
					, CONNECT_ONE_SHOT)
			_do_wave.call(1.0, dmg)
			if double_det:
				get_tree().create_timer(positions.size() * 0.01 + 1.5).timeout.connect(func() -> void:
					_do_wave.call(0.5, dmg)
			, CONNECT_ONE_SHOT)

# ── Kagura — Katsu ────────────────────────────────────────────────────────────

func _on_katsu(peer_id: int, sp) -> void:
	var delay: float = 0.0

	# 1. Spiders — stop each in place and spawn explosion
	for sid in _clay_spider_projs.keys().duplicate():
		if not sid.begins_with("spider_%d_" % peer_id):
			continue
		var proj = _clay_spider_projs[sid]
		if proj.done:
			continue
		proj.done = true
		var hit_pos: Vector2 = proj.pos
		_clay_spider_projs.erase(sid)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			for pid: int in multiplayer.get_peers():
				Network.clay_spider_stop.rpc_id(pid, sid, hit_pos)
			# AoE damage at spider position
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if enemy.zone_name != sp.zone or enemy.is_dead:
					continue
				if enemy.global_position.distance_to(hit_pos) <= 18.0:
					enemy.take_damage(32, Vector2.ZERO, sp.get_instance_id())
					Network.confirm_ability_hit.rpc_id(peer_id, enemy.global_position, 32)
			for oid: int in server_players:
				if oid == peer_id or are_same_party(peer_id, oid):
					continue
				var other: ServerPlayer = server_players[oid]
				if other.zone != sp.zone or other.is_dead:
					continue
				if other.world_pos.distance_to(hit_pos) <= 18.0:
					other.take_damage(32, Vector2.ZERO, peer_id)
					Network.confirm_ability_hit.rpc_id(peer_id, other.world_pos, 32)
		, CONNECT_ONE_SHOT)
		delay += 0.0

	# 2. Owl — trigger early explosion
	for owl_id in _clay_owls.keys().duplicate():
		var owl: ServerClayOwl = _clay_owls[owl_id]
		if owl.peer_id != peer_id or owl.done:
			continue
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			owl.take_hit()
			owl.take_hit()
			owl.take_hit()  # force HP to 0
		, CONNECT_ONE_SHOT)
		delay += 0.0

	# 3. Bomb — detonate early at half damage (Kagura)
	for bomb_id in _clay_bombs.keys().duplicate():
		var bomb: ServerClayBomb = _clay_bombs[bomb_id]
		if bomb.peer_id != peer_id or bomb.done:
			continue
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			bomb.detonate_early()
		, CONNECT_ONE_SHOT)
		delay += 0.0

	# 4. C4 swarms — chain detonate at 0.1s each dot
	for swarm_id in _c4_swarms.keys().duplicate():
		var swarm = _c4_swarms[swarm_id]
		if swarm["peer_id"] != peer_id:
			continue
		_c4_swarms.erase(swarm_id)
		var positions: Array  = swarm["positions"]
		var zone:      String = swarm["zone"]

		# Send chain explode to clients with 0.0s delay (Katsu)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			for pid: int in multiplayer.get_peers():
				Network.c4_chain_explode.rpc_id(pid, swarm_id, swarm["seed_val"], positions.size(), 0.0)
		, CONNECT_ONE_SHOT)

		# Stagger damage at 0.1s per dot
		var indices = range(positions.size())
		indices.shuffle()
		for i in range(indices.size()):
			var pos2d: Vector2 = positions[indices[i]]
			get_tree().create_timer(delay + i * 0.0).timeout.connect(func() -> void:
				const DMG = 32
				for enemy in get_tree().get_nodes_in_group("enemy"):
					if enemy.zone_name != zone or enemy.is_dead:
						continue
					if enemy.global_position.distance_to(pos2d) <= 48.0:
						enemy.take_damage(DMG, Vector2.ZERO, sp.get_instance_id() if sp else 0)
						if sp:
							Network.confirm_ability_hit.rpc_id(peer_id, enemy.global_position, DMG)
				for oid: int in server_players:
					if oid == peer_id:
						continue
					var other: ServerPlayer = server_players[oid]
					if other.zone != zone or other.is_dead:
						continue
					if other.world_pos.distance_to(pos2d) <= 48.0:
						other.take_damage(DMG, Vector2.ZERO, peer_id)
						if sp:
							Network.confirm_ability_hit.rpc_id(peer_id, other.world_pos, DMG)
			, CONNECT_ONE_SHOT)
