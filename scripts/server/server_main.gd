extends Node

const QuestDB      = preload("res://scripts/quest_db.gd")
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
var _respawn_queue:   Array      = []   # [{id, script, pos, zone, timer}]
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
	Network.ability_used_received.connect(_on_ability_used)
	Network.equip_update_received.connect(_on_equip_update)
	Network.item_used_received.connect(_on_item_used)
	Network.appearance_update_received.connect(_on_appearance_update)
	Network.dungeon_enter_requested.connect(_on_dungeon_enter_requested)
	Network.dungeon_exit_requested.connect(_on_dungeon_exit_requested)
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

func spawn_dungeon_enemy(id: String, script_path: String, pos: Vector2, zone: String) -> void:
	# Same as _spawn_enemy but no respawn on death
	_spawn_enemy(id, script_path, pos, zone)

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
		_send_enemy_roster(peer_id, zone_name)
		net.dungeon_enter_accepted.rpc_id(peer_id, dungeon_id, zone_name, spawn)
		print("[SERVER] %s entered dungeon '%s' instance %d" % [sp.username, dungeon_id, result["instance_id"]])

func _on_dungeon_exit_requested(peer_id: int) -> void:
	# Block exit if waves aren't finished yet
	var inst_id = _dungeon_manager.get_instance_id_for_peer(peer_id) if _dungeon_manager else -1
	if inst_id >= 0 and not _dungeon_manager.is_instance_complete(inst_id):
		Network.dungeon_enter_denied.rpc_id(peer_id, "Clear all waves before leaving!")
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

func _on_equip_update(peer_id: int, equipped: Dictionary) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	const VALID_SLOTS = ["weapon", "head", "chest", "legs", "shoes", "accessory"]
	var clean: Dictionary = {}
	for k in equipped:
		if k in VALID_SLOTS and equipped[k] is Dictionary:
			clean[k] = equipped[k]
	sp.equipped = clean
	sp.recalculate_gear_stats()
	print("[SERVER] %s equip update: %s" % [sp.username, clean.keys()])

func _on_appearance_update(peer_id: int, appearance: Dictionary) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	sp.appearance = appearance

func _on_item_used(peer_id: int, item_id: String) -> void:
	var sp = server_players.get(peer_id, null)
	if not sp:
		return
	var result = sp.use_consumable(item_id)
	Network.notify_item_result.rpc_id(peer_id, result.get("success", false), result.get("message", ""), result.get("new_hp", -1), result.get("new_max_hp", -1))

func _on_ability_used(peer_id: int, ability_name: String, data: Dictionary) -> void:
	if not server_players.has(peer_id):
		return
	var sp = server_players[peer_id]
	match ability_name:
		"fire_burst":
			var origin    = data.get("position", sp.world_pos)
			var radius    = data.get("radius",   80.0)
			var dmg       = data.get("damage",   35)
			var do_kb     = data.get("knockback", true)
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
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if enemy.zone_name != sp.zone:
					continue
				if enemy.global_position.distance_to(origin) <= radius:
					if enemy.has_method("take_damage"):
						var kb = (enemy.global_position - origin).normalized() if do_kb else Vector2.ZERO
						enemy.take_damage(dmg, kb, sp.get_instance_id())
					Network.confirm_ability_hit.rpc_id(peer_id, enemy.global_position, dmg)

func _on_position_received(peer_id: int, pos: Vector2) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].set_position_from_client(pos)

func _on_facing_received(peer_id: int, dir: String) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].facing_dir = dir

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
	add_child(sp)
	sp.recalculate_gear_stats()
	sp.global_position      = sp.world_pos
	server_players[peer_id] = sp
	# Send enemy roster for the player's starting zone — same as zone change
	_send_enemy_roster(peer_id, sp.zone)

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
		_debug_tick = 3.0  # print every 3s
	# Tick respawn queue
	for i in range(_respawn_queue.size() - 1, -1, -1):
		_respawn_queue[i].timer -= delta
		if _respawn_queue[i].timer <= 0:
			var r = _respawn_queue[i]
			_respawn_queue.remove_at(i)
			_spawn_enemy(r.id, r.script, r.pos, r.zone)

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

func _separate_players() -> void:
	var pids = server_players.keys()
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
	sp.quest_state[quest_id] = {"status": "turned_in", "progress": qdef.get("required", 1)}
	Database.save_player(sp.username, sp.get_save_data())
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.notify_quest_turned_in.rpc_id(peer_id, quest_id, reward_xp, reward_gold)
	print("[SERVER] %s completed quest: %s (+%d xp, +%d gold)" % [sp.username, quest_id, reward_xp, reward_gold])

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
