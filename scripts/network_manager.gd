extends Node

# ============================================================
# NETWORK MANAGER — Pure transport layer
# Handles connection setup and RPC routing only.
# No game logic lives here.
# ============================================================

const MAX_CLIENTS   = 128
const LOCAL_CONFIG  = "res://server_config.json"
const DEV_CONFIG    = "res://local_dev.cfg"
const REMOTE_CONFIG = "https://raw.githubusercontent.com/MJPxStudio/avatard/main/server_config.json"

var PORT:          int    = 7777
var SERVER_IP:     String = "0.0.0.0"
var LOCAL_IP:      String = "127.0.0.1"
var is_server:     bool   = false
var dev_mode:      bool   = false
var config_loaded: bool   = false

# --- Signals ---
signal config_ready
signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
signal login_request_received(peer_id, username)
signal login_accepted_client(player_data)
signal login_denied_client(reason)
signal ability_used_received(peer_id, ability_name, data)
signal attack_received(peer_id, direction, from_pos)
signal position_received(peer_id: int, pos: Vector2)
signal facing_received(peer_id: int, dir: String)
signal zone_changed(peer_id, zone_name)
signal max_hp_received(peer_id: int, max_value: int, current_value: int)
signal players_synced_client(states)
signal enemies_synced_client(states)
signal damage_received_client(amount, knockback_dir)
signal enemy_killed_client(xp, gold, item_drop)
signal xp_gained_client(current_exp, max_exp, amount)
signal level_up_client(new_level, current_exp, max_exp, stat_points, new_max_hp, str_, hp_, chakra_, dex_, int_)
signal hit_confirmed(position, amount)
signal ability_hit_confirmed(position, amount)
signal equip_update_received(peer_id, equipped)
signal dungeon_enter_requested(peer_id, dungeon_id)
signal dungeon_exit_requested(peer_id)
signal wave_start_received(wave, total, objective)
signal dungeon_complete_received()
signal dungeon_failed_received()
signal boss_phase_received(boss_name, phase, msg)
signal boss_hp_received(hp, max_hp)
signal enemy_telegraph_received(enemy_id: String)
signal kunai_spawned(start_pos: Vector2, direction: Vector2)
signal chat_received_server(peer_id: int, channel: String, target_name: String, text: String)
signal chat_received_client(channel: String, sender_name: String, text: String)
signal party_invite_received(inviter_name: String)
signal party_update_received(party_data: Dictionary)  # { members: [], leader: "" }
signal party_msg_received(channel: String, text: String)
signal party_invite_sent(peer_id: int, target_name: String)
signal party_response_received(peer_id: int, inviter_name: String, accepted: bool)
signal party_leave_received(peer_id: int)
signal party_kick_received(peer_id: int, target_name: String)
signal party_promote_received(peer_id: int, target_name: String)

var players: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if FileAccess.file_exists(DEV_CONFIG):
		_load_config(DEV_CONFIG, true)
		_emit_config_ready()
	elif DisplayServer.get_name() == "headless":
		# Running as server — no need to fetch remote config
		_load_config(LOCAL_CONFIG, false)
		_emit_config_ready()
	else:
		_load_config(LOCAL_CONFIG, false)
		_fetch_remote_config()

func _load_config(path: String, is_dev: bool) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("[NETWORK] Config not found: %s" % path)
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		print("[NETWORK] Config parse error: %s" % path)
		file.close()
		return
	file.close()
	var data  = json.get_data()
	SERVER_IP = data.get("server_ip", SERVER_IP)
	LOCAL_IP  = data.get("local_ip",  LOCAL_IP)
	PORT      = data.get("port",      PORT)
	dev_mode  = is_dev
	print("[NETWORK] Config loaded (%s): %s | local: %s | port: %d" % [
		"DEV" if is_dev else "release", SERVER_IP, LOCAL_IP, PORT])

func _fetch_remote_config() -> void:
	var http     = HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	http.request_completed.connect(_on_remote_config_done.bind(http))
	if http.request(REMOTE_CONFIG) != OK:
		print("[NETWORK] Remote config request failed, using local")
		_emit_config_ready()

func _on_remote_config_done(result: int, code: int, _h, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data  = json.get_data()
			SERVER_IP = data.get("server_ip", SERVER_IP)
			LOCAL_IP  = data.get("local_ip",  LOCAL_IP)
			PORT      = data.get("port",      PORT)
			print("[NETWORK] Remote config applied: %s:%d" % [SERVER_IP, PORT])
		else:
			print("[NETWORK] Remote config parse error, using local")
	else:
		print("[NETWORK] Remote config fetch failed (code %d)" % code)
	_emit_config_ready()

func _emit_config_ready() -> void:
	config_loaded = true
	config_ready.emit()

func launch_as_server() -> void:
	is_server = true
	var peer  = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_CLIENTS) != OK:
		push_error("[NETWORK] Failed to start server on port %d" % PORT)
		return
	multiplayer.multiplayer_peer = peer
	print("[SERVER] Started on port %d" % PORT)

func launch_as_client() -> void:
	is_server  = false
	var ip     = LOCAL_IP if (dev_mode or "--local" in OS.get_cmdline_args()) else SERVER_IP
	print("[CLIENT] Connecting to %s:%d" % [ip, PORT])
	var peer   = ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		push_error("[NETWORK] Failed to connect to %s:%d" % [ip, PORT])
		return
	multiplayer.multiplayer_peer = peer

func _on_peer_connected(peer_id: int) -> void:
	if is_server:
		players[peer_id] = {"username": "", "zone": "village", "position": Vector2.ZERO, "position_ready": false}
		player_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if is_server:
		players.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	print("[CLIENT] Connected. ID: %d" % multiplayer.get_unique_id())
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("[CLIENT] Connection failed.")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

# --- RPCs ---

@rpc("any_peer", "reliable")
func request_login(username: String) -> void:
	if not is_server:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	login_request_received.emit(peer_id, username.strip_edges().left(24))

@rpc("authority", "reliable")
func notify_login_accepted(player_data: Dictionary) -> void:
	login_accepted_client.emit(player_data)

@rpc("authority", "reliable")
func notify_login_denied(reason: String) -> void:
	login_denied_client.emit(reason)

@rpc("any_peer", "unreliable_ordered")
func send_position(pos: Vector2) -> void:
	if not is_server:
		return
	# NOTE: Do NOT update players["position"] here.
	# set_position_from_client() is the single source of truth — it runs the rate
	# limiter and only updates players["position"] when the update is accepted.
	position_received.emit(multiplayer.get_remote_sender_id(), pos)

@rpc("any_peer", "unreliable_ordered")
func send_facing(dir: String) -> void:
	if not is_server:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	facing_received.emit(peer_id, dir)

@rpc("any_peer", "reliable")
func send_attack(direction: Vector2, from_pos: Vector2) -> void:
	if not is_server:
		return
	attack_received.emit(multiplayer.get_remote_sender_id(), direction, from_pos)

@rpc("any_peer", "reliable")
func send_ability(ability_name: String, data: Dictionary) -> void:
	if not is_server:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	ability_used_received.emit(peer_id, ability_name, data)

@rpc("any_peer", "reliable")
func send_max_hp(max_value: int, current_value: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	max_hp_received.emit(peer_id, max_value, current_value)

@rpc("any_peer", "reliable")
func send_zone_and_position(zone_name: String, pos: Vector2) -> void:
	if not is_server:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if players.has(peer_id):
		players[peer_id]["zone"] = zone_name
	zone_changed.emit(peer_id, zone_name)
	# Deliver position through the normal validated path
	position_received.emit(peer_id, pos)

@rpc("any_peer", "reliable")
func send_zone_change(zone_name: String) -> void:
	if not is_server:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if players.has(peer_id):
		players[peer_id]["zone"] = zone_name
	zone_changed.emit(peer_id, zone_name)

@rpc("authority", "reliable")
func sync_players(states: Dictionary) -> void:
	players_synced_client.emit(states)

@rpc("authority", "unreliable_ordered")
func sync_enemies(all_zones: Dictionary) -> void:
	if not is_server:
		enemies_synced_client.emit(all_zones)

@rpc("authority", "reliable")
func sync_enemy_roster(zone: String, roster: Dictionary) -> void:
	# Static enemy data sent once on zone entry — type, max_hp, hitbox_size, level
	if not is_server:
		enemy_roster_client.emit(zone, roster)

signal enemy_roster_client(zone, roster)

# ── Quest RPCs ──────────────────────────────────────────────
# Client → Server
@rpc("any_peer", "reliable")
func send_quest_accept(quest_id: String) -> void:
	if is_server:
		quest_accept_received.emit(multiplayer.get_remote_sender_id(), quest_id)

@rpc("any_peer", "reliable")
func send_quest_complete(quest_id: String) -> void:
	if is_server:
		quest_complete_received.emit(multiplayer.get_remote_sender_id(), quest_id)

signal quest_accept_received(peer_id, quest_id)
signal quest_complete_received(peer_id, quest_id)

# Server → Client
@rpc("authority", "reliable")
func notify_quest_progress(quest_id: String, progress: int, required: int) -> void:
	if not is_server:
		quest_progress_client.emit(quest_id, progress, required)

@rpc("authority", "reliable")
func notify_quest_turned_in(quest_id: String, reward_xp: int, reward_gold: int) -> void:
	if not is_server:
		quest_turned_in_client.emit(quest_id, reward_xp, reward_gold)

signal quest_progress_client(quest_id, progress, required)
signal quest_turned_in_client(quest_id, reward_xp, reward_gold)

@rpc("authority", "reliable")
func sync_damage(target_peer_id: int, amount: int, knockback_dir: Vector2) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		damage_received_client.emit(amount, knockback_dir)

@rpc("authority", "reliable")
func confirm_hit(hit_position: Vector2, amount: int) -> void:
	hit_confirmed.emit(hit_position, amount)

@rpc("authority", "reliable")
func confirm_ability_hit(hit_position: Vector2, amount: int) -> void:
	ability_hit_confirmed.emit(hit_position, amount)

@rpc("any_peer", "reliable")
func send_equip_update(equipped: Dictionary) -> void:
	equip_update_received.emit(multiplayer.get_remote_sender_id(), equipped)

# ── Dungeon RPCs ───────────────────────────────────────────────────────────
@rpc("any_peer", "reliable")
func request_dungeon_enter(dungeon_id: String) -> void:
	dungeon_enter_requested.emit(multiplayer.get_remote_sender_id(), dungeon_id)

@rpc("any_peer", "reliable")
func request_dungeon_exit() -> void:
	dungeon_exit_requested.emit(multiplayer.get_remote_sender_id())

@rpc("authority", "reliable")
func dungeon_enter_accepted(dungeon_id: String, zone_name: String, spawn: Vector2) -> void:
	# Server approved entry — client transitions to dungeon scene
	var main = get_tree().root.get_node_or_null("Main")
	if main and main.has_method("transition_to_dungeon"):
		main.transition_to_dungeon(dungeon_id, zone_name, spawn)

@rpc("authority", "reliable")
func dungeon_enter_denied(reason: String) -> void:
	var lp = get_tree().get_first_node_in_group("local_player")
	if lp and lp.chat:
		lp.chat.add_system_message("[DUNGEON] " + reason)

@rpc("authority", "reliable")
func dungeon_exit_accepted(exit_scene: String, exit_pos: Vector2) -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if main and main.has_method("transition_to_zone"):
		main.transition_to_zone(exit_scene, exit_pos)

@rpc("authority", "reliable")
func notify_wave_start(wave: int, total: int, objective: String) -> void:
	wave_start_received.emit(wave, total, objective)

@rpc("authority", "reliable")
func notify_dungeon_complete() -> void:
	dungeon_complete_received.emit()

@rpc("authority", "reliable")
func notify_dungeon_failed() -> void:
	dungeon_failed_received.emit()

@rpc("authority", "reliable")
func notify_boss_phase(boss_name: String, phase: int, msg: String) -> void:
	boss_phase_received.emit(boss_name, phase, msg)

@rpc("authority", "reliable")
func boss_attack_telegraph(enemy_id: String, attack_type: String, origin: Vector2, size: Vector2, dir: Vector2, windup_time: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs and gs.has_method("on_boss_telegraph"):
		gs.on_boss_telegraph(enemy_id, attack_type, origin, size, dir, windup_time)

@rpc("authority", "reliable")
func notify_boss_hp(hp: int, max_hp: int) -> void:
	boss_hp_received.emit(hp, max_hp)

@rpc("authority", "reliable")
func enemy_telegraph(enemy_id: String) -> void:
	enemy_telegraph_received.emit(enemy_id)

@rpc("authority", "reliable")
func enemy_telegraph_color(enemy_id: String, r: float, g: float, b: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs and gs.has_method("on_enemy_telegraph_color"):
		gs.on_enemy_telegraph_color(enemy_id, Color(r, g, b, 0.9))

@rpc("authority", "reliable")
func enemy_indicator(enemy_id: String, text: String, r: float, g: float, b: float) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs and gs.has_method("on_enemy_indicator"):
		gs.on_enemy_indicator(enemy_id, text, Color(r, g, b, 1.0))

@rpc("authority", "reliable")
func spawn_kunai(start_pos: Vector2, direction: Vector2) -> void:
	kunai_spawned.emit(start_pos, direction)

@rpc("authority", "reliable")
func notify_enemy_killed(xp: int, gold: int, item_drop: String) -> void:
	enemy_killed_client.emit(xp, gold, item_drop)

@rpc("any_peer", "reliable")
func send_spend_stats(hp: int, chakra: int, strength: int, dex: int, int_: int) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return  # only accept from clients
	spend_stats_server.emit(multiplayer.get_remote_sender_id(), hp, chakra, strength, dex, int_)

signal spend_stats_server(peer_id, hp, chakra, strength, dex, int_)

@rpc("authority", "reliable")
func notify_party_xp_shared(members: Array, amount: int) -> void:
	party_xp_shared_client.emit(members, amount)

signal party_xp_shared_client(members, amount)

@rpc("authority", "reliable")
func notify_xp_gained(current_exp: int, max_exp: int, amount: int) -> void:
	xp_gained_client.emit(current_exp, max_exp, amount)

@rpc("authority", "reliable")
func notify_level_up(new_level: int, current_exp: int, max_exp: int, stat_points: int, new_max_hp: int,
		str_: int, hp_: int, chakra_: int, dex_: int, int__: int) -> void:
	level_up_client.emit(new_level, current_exp, max_exp, stat_points, new_max_hp,
		str_, hp_, chakra_, dex_, int__)

@rpc("any_peer", "reliable")
func send_chat(channel: String, target_name: String, text: String) -> void:
	# Received on server — route via server_main
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	chat_received_server.emit(peer_id, channel, target_name, text)

@rpc("any_peer", "reliable")
func send_party_invite(target_name: String) -> void:
	if not is_server:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	party_invite_sent.emit(peer_id, target_name)

@rpc("any_peer", "reliable")
func send_party_response(inviter_name: String, accepted: bool) -> void:
	if not is_server:
		return
	party_response_received.emit(multiplayer.get_remote_sender_id(), inviter_name, accepted)

@rpc("any_peer", "reliable")
func send_party_leave() -> void:
	if not is_server:
		return
	party_leave_received.emit(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func send_party_kick(target_name: String) -> void:
	if not is_server:
		return
	party_kick_received.emit(multiplayer.get_remote_sender_id(), target_name)

@rpc("any_peer", "reliable")
func send_party_promote(target_name: String) -> void:
	if not is_server:
		return
	party_promote_received.emit(multiplayer.get_remote_sender_id(), target_name)

@rpc("authority", "reliable")
func receive_party_invite(inviter_name: String) -> void:
	print("[CLIENT] receive_party_invite fired — inviter: ", inviter_name)
	party_invite_received.emit(inviter_name)

@rpc("authority", "reliable")
func receive_party_update(party_data: Dictionary) -> void:
	party_update_received.emit(party_data)

@rpc("authority", "reliable")
func receive_party_msg(channel: String, text: String) -> void:
	party_msg_received.emit(channel, text)

@rpc("authority", "reliable")
func receive_chat(channel: String, sender_name: String, text: String) -> void:
	# Received on client
	chat_received_client.emit(channel, sender_name, text)

# --- Helpers ---

func accept_login(peer_id: int, data: Dictionary) -> void:
	notify_login_accepted.rpc_id(peer_id, data)

func deny_login(peer_id: int, reason: String) -> void:
	notify_login_denied.rpc_id(peer_id, reason)

func get_my_id() -> int:
	return multiplayer.get_unique_id()

func is_network_connected() -> bool:
	return multiplayer.multiplayer_peer != null
