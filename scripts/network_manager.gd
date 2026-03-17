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
signal chakra_synced(current: int, maximum: int)
signal byakugan_enemy_chakra_received(enemy_id: String, current: int, maximum: int)
signal byakugan_state_received(caster_peer_id: int, active: bool)
signal air_palm_visual_received(caster_peer_id: int, from_pos: Vector2, to_pos: Vector2)
signal air_palm_stop_received(caster_peer_id: int, hit_pos: Vector2)
signal chakra_drain_visual_received(pos: Vector2, amount: int)
signal palms_cinematic_received(caster_peer_id: int, target_id_str: String, hit_count: int, interval: float, icon_path: String)
signal palms_prime_expired_received()
signal palms_cinematic_end_received(caster_peer_id: int, target_pos: Vector2, knockback_dir: Vector2)
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
signal rank_up_client(new_rank)
signal hit_confirmed(position, amount)
signal enemy_hit_flash_received(enemy_id)
signal dungeon_floor_start_received(floor_num, total_floors, room_count, difficulty)
signal dungeon_room_enter_received(room_id, label, room_type, connections, floor_num, tiles_w, tiles_h, spawn_pos)
signal dungeon_room_cleared_received(room_id, connections, door_rewards)
signal dungeon_boon_offer_received(boon_ids)
signal dungeon_boon_chosen_received(boon_id, boon_name)
signal dungeon_rest_received(hp, max_hp, chakra, max_chakra)
signal dungeon_reward_room_received(reward_type)
signal dungeon_stat_sync_received(max_hp, max_chakra)
signal dungeon_boon_props_received(props)
signal dungeon_door_vote_received(voter_peer_id, votes_so_far, living_count)
signal ability_failed(ability_name, reason)

# Server-side cooldown durations (seconds) — authoritative
# Client UI uses AbilityBase.cooldown for display; this is what the server enforces
const ABILITY_COOLDOWNS: Dictionary = {
	"fire_burst":             8.0,
	"shadow_possession_start": 12.0,
	"shadow_strangle":         6.0,
	"shadow_pull":             5.0,
	"mass_shadow_start":      18.0,
	"gentle_fist":             1.5,
	"prime_palms":            20.0,
	"palm_rotation":          15.0,
	"byakugan_toggle":         2.0,
	"air_palm":                4.0,
	"bug_swarm":               6.0,
	"parasite_prime":         10.0,
	"insect_cocoon":           8.0,
	"hive_burst":             12.0,
	"bug_cloak_toggle":        2.0,
	"medical_jutsu":           8.0,
	"substitution_prime":     20.0,
	"c1_spiders":              1.5,
	"c2_owl":                 25.0,
	"c3_bomb":                20.0,
	"c4_karura":              45.0,
	"katsu":                  60.0,
}
signal ability_hit_confirmed(position, amount)
signal equip_update_received(peer_id, equipped)
signal appearance_update_received(peer_id, appearance)
signal gold_synced(amount)
signal item_granted(item_id, quantity)
signal mission_board_received(rank, available, active_id, progress)
signal mission_accepted_received(mission_data, progress)
signal mission_abandoned_received()
signal mission_completed_received(mission_id, xp, gold)
signal mission_progress_received(current, required)
signal npc_talk_received(peer_id, npc_name)
signal intro_needed(needed)
signal quest_accepted_received(quest_id)
signal escort_started_received()
signal escort_completed_received()
signal training_complete_received()
signal notify_quest_accepted_received(quest_id)
signal dungeon_enter_requested(peer_id, dungeon_id)
signal dungeon_exit_requested(peer_id)
signal dungeon_ready_check_requested(peer_id, dungeon_id, difficulty)
signal mission_board_requested(peer_id, rank)
signal escort_started_server(peer_id)
signal escort_completed_server(peer_id)
signal training_complete_server(peer_id)
signal mission_accept_requested(peer_id, mission_id)
signal mission_abandon_requested(peer_id)
signal mission_complete_requested(peer_id)
signal dungeon_player_ready(peer_id, is_ready)
signal dungeon_cancel_ready(peer_id)
signal wave_start_received(wave, total, objective)
signal dungeon_complete_received()
signal dungeon_failed_received()
signal ready_check_updated(members, dungeon_id)
signal ready_check_cancelled_received(reason)
signal dungeon_launching_received(countdown)
signal player_became_ghost_received(peer_id)
signal checkpoint_revived(peer_ids, revive_pos)
signal dungeon_wiped_received(exit_scene, exit_pos)
signal dungeon_portal_locked_received(dungeon_id, locked)
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
func sync_chakra(target_peer_id: int, current: int, maximum: int) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		chakra_synced.emit(current, maximum)

@rpc("authority", "reliable")
func byakugan_enemy_chakra(enemy_id: String, current: int, maximum: int) -> void:
	byakugan_enemy_chakra_received.emit(enemy_id, current, maximum)

@rpc("authority", "reliable")
func byakugan_state(caster_peer_id: int, active: bool) -> void:
	byakugan_state_received.emit(caster_peer_id, active)

@rpc("authority", "reliable")
func air_palm_visual(caster_peer_id: int, from_pos: Vector2, to_pos: Vector2) -> void:
	air_palm_visual_received.emit(caster_peer_id, from_pos, to_pos)

@rpc("authority", "reliable")
func air_palm_stop(caster_peer_id: int, hit_pos: Vector2) -> void:
	air_palm_stop_received.emit(caster_peer_id, hit_pos)

@rpc("authority", "reliable")
func chakra_drain_visual(pos: Vector2, amount: int) -> void:
	chakra_drain_visual_received.emit(pos, amount)

@rpc("authority", "reliable")
func palms_cinematic(caster_peer_id: int, target_id_str: String, hit_count: int, interval: float, icon_path: String) -> void:
	palms_cinematic_received.emit(caster_peer_id, target_id_str, hit_count, interval, icon_path)

@rpc("authority", "reliable")
func palms_prime_expired() -> void:
	palms_prime_expired_received.emit()

@rpc("authority", "reliable")
func palms_cinematic_end(caster_peer_id: int, target_pos: Vector2, knockback_dir: Vector2) -> void:
	palms_cinematic_end_received.emit(caster_peer_id, target_pos, knockback_dir)

@rpc("authority", "reliable")
func sync_damage(target_peer_id: int, amount: int, knockback_dir: Vector2) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		damage_received_client.emit(amount, knockback_dir)

@rpc("authority", "unreliable")
func enemy_hit_flash(enemy_id: String) -> void:
	enemy_hit_flash_received.emit(enemy_id)

@rpc("authority", "reliable")
func notify_ability_failed(ability_name: String, reason: String) -> void:
	ability_failed.emit(ability_name, reason)

@rpc("authority", "reliable")
func confirm_hit(hit_position: Vector2, amount: int) -> void:
	hit_confirmed.emit(hit_position, amount)

@rpc("authority", "reliable")
func confirm_ability_hit(hit_position: Vector2, amount: int) -> void:
	ability_hit_confirmed.emit(hit_position, amount)

# Status effect notifications (server → target client)
# Must use target_peer_id so host-player receives their own status
@rpc("authority", "reliable")
func notify_status(target_peer_id: int, status_id: String, duration: float) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		status_applied.emit(status_id, duration)

@rpc("authority", "reliable")
func notify_status_end(target_peer_id: int, status_id: String) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		status_ended.emit(status_id)

@rpc("authority", "reliable")
func notify_pull(new_pos: Vector2) -> void:
	pull_received.emit(new_pos)

signal status_applied(status_id: String, duration: float)
signal status_ended(status_id: String)
signal pull_received(new_pos: Vector2)

# Shadow Possession projectile RPCs
@rpc("authority", "reliable")
func shadow_spawn(shadow_id: String, caster_peer_id: int, start_pos: Vector2, target_id_str: String) -> void:
	shadow_spawned.emit(shadow_id, caster_peer_id, start_pos, target_id_str)

@rpc("authority", "unreliable_ordered")
func shadow_move(shadow_id: String, pos: Vector2) -> void:
	shadow_moved.emit(shadow_id, pos)

@rpc("authority", "reliable")
func shadow_despawn(shadow_id: String, hit: bool) -> void:
	shadow_despawned.emit(shadow_id, hit)

@rpc("authority", "reliable")
func ability_visual(target_id_str: String, visual_id: String, extra: Vector2 = Vector2.ZERO) -> void:
	ability_visual_received.emit(target_id_str, visual_id, extra)

@rpc("authority", "reliable")
func enemy_pulled(enemy_id: String, new_pos: Vector2, caster_pos: Vector2) -> void:
	enemy_pulled_received.emit(enemy_id, new_pos, caster_pos)

@rpc("authority", "reliable")
func mass_shadow_visual(origin: Vector2, radius: float) -> void:
	mass_shadow_visual_received.emit(origin, radius)

signal shadow_spawned(shadow_id: String, caster_peer_id: int, start_pos: Vector2, target_id_str: String)
signal ability_visual_received(target_id_str: String, visual_id: String, extra: Vector2)
signal enemy_pulled_received(enemy_id: String, new_pos: Vector2, caster_pos: Vector2)
signal mass_shadow_visual_received(origin: Vector2, radius: float)
signal shadow_moved(shadow_id: String, pos: Vector2)
signal shadow_despawned(shadow_id: String, hit: bool)

@rpc("any_peer", "reliable")
func send_equip_update(equipped: Dictionary) -> void:
	equip_update_received.emit(multiplayer.get_remote_sender_id(), equipped)

@rpc("any_peer", "reliable")
func send_appearance_update(appearance: Dictionary) -> void:
	appearance_update_received.emit(multiplayer.get_remote_sender_id(), appearance)

@rpc("any_peer", "reliable")
func send_hotbar_loadout(loadout: Array) -> void:
	if multiplayer.get_unique_id() == 1:
		# Already on server — emit directly, no RPC needed
		hotbar_loadout_received.emit(1, loadout)
	else:
		_receive_hotbar_loadout.rpc_id(1, loadout)

@rpc("any_peer", "reliable")
func _receive_hotbar_loadout(loadout: Array) -> void:
	hotbar_loadout_received.emit(multiplayer.get_remote_sender_id(), loadout)

signal hotbar_loadout_received(peer_id: int, loadout: Array)

func send_character_creation(clan_id: String, element_id: String) -> void:
	receive_character_creation.rpc_id(1, clan_id, element_id)

@rpc("any_peer", "reliable")
func receive_character_creation(clan_id: String, element_id: String) -> void:
	character_creation_received.emit(multiplayer.get_remote_sender_id(), clan_id, element_id)

func send_use_item(item_id: String) -> void:
	item_used_received.emit(multiplayer.get_remote_sender_id(), item_id)

@rpc("authority", "reliable")
func sync_gold(amount: int) -> void:
	gold_synced.emit(amount)

@rpc("authority", "reliable")
func grant_item(item_id: String, quantity: int) -> void:
	item_granted.emit(item_id, quantity)

# ── Mission RPCs ──────────────────────────────────────────────────────────
@rpc("any_peer", "reliable")
func request_mission_board(rank: String) -> void:
	mission_board_requested.emit(multiplayer.get_remote_sender_id(), rank)

@rpc("any_peer", "reliable")
func accept_mission(mission_id: String) -> void:
	mission_accept_requested.emit(multiplayer.get_remote_sender_id(), mission_id)

@rpc("any_peer", "reliable")
func abandon_mission() -> void:
	mission_abandon_requested.emit(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func complete_mission() -> void:
	mission_complete_requested.emit(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func notify_npc_talk(npc_name: String) -> void:
	var pid = multiplayer.get_remote_sender_id()
	npc_talk_received.emit(pid, npc_name)
	# Route to deliver mission handler
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm and sm.has_method("_on_mission_deliver_talk"):
		sm._on_mission_deliver_talk(pid, npc_name)

# ── Intro/Quest RPCs ──────────────────────────────────────────────────────
@rpc("authority", "reliable")
func notify_intro_needed(needed: bool) -> void:
	intro_needed.emit(needed)

@rpc("authority", "reliable")
func notify_quest_accepted(quest_id: String) -> void:
	notify_quest_accepted_received.emit(quest_id)

@rpc("any_peer", "reliable")
func escort_started() -> void:
	escort_started_server.emit(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func escort_completed() -> void:
	escort_completed_server.emit(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func training_complete() -> void:
	training_complete_server.emit(multiplayer.get_remote_sender_id())

@rpc("authority", "reliable")
func mission_board_data(rank: String, available: Array, active_id: String, progress: int) -> void:
	mission_board_received.emit(rank, available, active_id, progress)

@rpc("authority", "reliable")
func mission_accepted(mission_data: Dictionary, progress: int) -> void:
	mission_accepted_received.emit(mission_data, progress)

@rpc("authority", "reliable")
func mission_abandoned() -> void:
	mission_abandoned_received.emit()

@rpc("authority", "reliable")
func mission_completed(mission_id: String, xp: int, gold: int) -> void:
	mission_completed_received.emit(mission_id, xp, gold)

@rpc("authority", "reliable")
func mission_progress_update(current: int, required: int) -> void:
	mission_progress_received.emit(current, required)

@rpc("authority", "reliable")
func notify_item_result(success: bool, message: String, new_hp: int = -1, new_max_hp: int = -1) -> void:
	item_result_client.emit(success, message, new_hp, new_max_hp)

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
func dungeon_floor_start(floor_num: int, total_floors: int, room_count: int, difficulty: String = "easy") -> void:
	dungeon_floor_start_received.emit(floor_num, total_floors, room_count, difficulty)

@rpc("authority", "reliable")
func dungeon_room_enter(room_id: int, label: String, room_type: int, connections: Array, floor_num: int, tiles_w: int = 28, tiles_h: int = 19, spawn_pos: Vector2 = Vector2.ZERO) -> void:
	dungeon_room_enter_received.emit(room_id, label, room_type, connections, floor_num, tiles_w, tiles_h, spawn_pos)

@rpc("authority", "reliable")
func dungeon_room_cleared(room_id: int, connections: Array, door_rewards: Dictionary = {}) -> void:
	dungeon_room_cleared_received.emit(room_id, connections, door_rewards)

@rpc("any_peer", "reliable")
func send_boon_choice(boon_id: String) -> void:
	if not is_server: return
	var peer_id = multiplayer.get_remote_sender_id()
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm and sm._dungeon_manager:
		var inst_id = sm._dungeon_manager.get_instance_id_for_peer(peer_id)
		if inst_id >= 0:
			var fc = sm._dungeon_manager._floor_controllers.get(inst_id, null)
			if fc:
				fc.player_chose_boon(peer_id, boon_id)

@rpc("authority", "reliable")
func dungeon_boon_offer(boon_ids: Array) -> void:
	dungeon_boon_offer_received.emit(boon_ids)

@rpc("authority", "reliable")
func dungeon_boon_chosen(boon_id: String, boon_name: String) -> void:
	dungeon_boon_chosen_received.emit(boon_id, boon_name)

@rpc("authority", "reliable")
func dungeon_boon_props(props: Dictionary) -> void:
	dungeon_boon_props_received.emit(props)

@rpc("authority", "reliable")
func dungeon_rest_healed(hp: int, max_hp: int, chakra: int, max_chakra: int) -> void:
	dungeon_rest_received.emit(hp, max_hp, chakra, max_chakra)

@rpc("authority", "reliable")
func dungeon_door_vote(voter_peer_id: int, votes_so_far: int, living_count: int) -> void:
	dungeon_door_vote_received.emit(voter_peer_id, votes_so_far, living_count)

@rpc("authority", "reliable")
func dungeon_stat_sync(new_max_hp: int, new_max_chakra: int) -> void:
	dungeon_stat_sync_received.emit(new_max_hp, new_max_chakra)

@rpc("authority", "reliable")
func dungeon_reward_room(reward_type: int) -> void:
	dungeon_reward_room_received.emit(reward_type)

@rpc("any_peer", "reliable")
func send_room_move(room_id: int, reward_type: int = -1) -> void:
	if not is_server: return
	var peer_id = multiplayer.get_remote_sender_id()
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm and sm._dungeon_manager:
		# Place server player at bottom entrance — matches client walk-in start
		# Enemies detect based on world_pos, so this prevents aggro during entrance
		var sp = sm.server_players.get(peer_id, null)
		if sp:
			# Get room size from floor controller to find entrance y
			var inst_id = sm._dungeon_manager.get_instance_id_for_peer(peer_id)
			var fc = sm._dungeon_manager._floor_controllers.get(inst_id, null)
			var entrance_y = 200.0  # fallback — bottom of default room
			if fc:
				var room = fc._floor_layout["rooms"].get(room_id, {}) if fc._floor_layout else {}
				var th = room.get("tiles_h", 19)
				var tw = room.get("tiles_w", 30)
				entrance_y = (th * 32.0) / 2.0 - 64.0 - 48.0  # TF + 1.5 tiles up
			sp.world_pos        = Vector2(0.0, entrance_y)
			sp.global_position  = Vector2(0.0, entrance_y)
			players[peer_id]["position"] = Vector2(0.0, entrance_y)
		sm._dungeon_manager.player_move_to_room(peer_id, room_id, reward_type)

@rpc("authority", "reliable")
func notify_dungeon_complete() -> void:
	dungeon_complete_received.emit()

@rpc("authority", "reliable")
func notify_dungeon_failed() -> void:
	dungeon_failed_received.emit()

@rpc("any_peer", "reliable")
func request_ready_check(dungeon_id: String, difficulty: String = "easy") -> void:
	dungeon_ready_check_requested.emit(multiplayer.get_remote_sender_id(), dungeon_id, difficulty)

@rpc("any_peer", "reliable")
func send_player_ready(is_ready: bool) -> void:
	dungeon_player_ready.emit(multiplayer.get_remote_sender_id(), is_ready)

@rpc("any_peer", "reliable")
func send_cancel_ready() -> void:
	dungeon_cancel_ready.emit(multiplayer.get_remote_sender_id())

@rpc("authority", "reliable")
func ready_check_update(members: Array, dungeon_id: String) -> void:
	ready_check_updated.emit(members, dungeon_id)

@rpc("authority", "reliable")
func ready_check_cancelled(reason: String) -> void:
	ready_check_cancelled_received.emit(reason)

@rpc("authority", "reliable")
func dungeon_launching(countdown: float) -> void:
	dungeon_launching_received.emit(countdown)

@rpc("authority", "reliable")
func player_became_ghost(peer_id: int) -> void:
	player_became_ghost_received.emit(peer_id)

@rpc("authority", "reliable")
func checkpoint_revive(peer_ids: Array, revive_pos: Vector2) -> void:
	checkpoint_revived.emit(peer_ids, revive_pos)

@rpc("authority", "reliable")
func dungeon_wiped(exit_scene: String, exit_pos: Vector2) -> void:
	dungeon_wiped_received.emit(exit_scene, exit_pos)

@rpc("authority", "reliable")
func dungeon_portal_locked(dungeon_id: String, locked: bool) -> void:
	dungeon_portal_locked_received.emit(dungeon_id, locked)

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
signal item_used_received(peer_id: int, item_id: String)
signal character_creation_received(peer_id: int, clan_id: String, element_id: String)
signal item_result_client(success: bool, message: String, new_hp: int, new_max_hp: int)

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

@rpc("authority", "reliable")
func notify_rank_up(new_rank: String) -> void:
	rank_up_client.emit(new_rank)

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

# --- Trap RPCs ---

@rpc("authority", "reliable")
func trap_spawn(trap_id: String, caster_peer_id: int, pos: Vector2, trap_type: String) -> void:
	trap_spawned.emit(trap_id, caster_peer_id, pos, trap_type)

@rpc("authority", "reliable")
func trap_despawn(trap_id: String, triggered: bool) -> void:
	trap_despawned.emit(trap_id, triggered)

signal trap_spawned(trap_id: String, caster_peer_id: int, pos: Vector2, trap_type: String)
signal trap_despawned(trap_id: String, triggered: bool)

# --- Clay Spider RPCs ---

@rpc("authority", "reliable")
func clay_spider_visual(caster_peer_id: int, spider_id: String, from_pos: Vector2, to_pos: Vector2, dir_str: String, proj_speed: float = 160.0) -> void:
	clay_spider_visual_received.emit(caster_peer_id, spider_id, from_pos, to_pos, dir_str, proj_speed)

@rpc("authority", "reliable")
func clay_spider_stop(spider_id: String, hit_pos: Vector2) -> void:
	clay_spider_stop_received.emit(spider_id, hit_pos)

signal clay_spider_visual_received(caster_peer_id: int, spider_id: String, from_pos: Vector2, to_pos: Vector2, dir_str: String, proj_speed: float)
signal clay_spider_stop_received(spider_id: String, hit_pos: Vector2)

# --- Clay Owl RPCs ---

@rpc("authority", "reliable")
func clay_owl_spawn(owl_id: String, caster_peer_id: int, from_pos: Vector2, target_id: String) -> void:
	clay_owl_spawn_received.emit(owl_id, caster_peer_id, from_pos, target_id)

@rpc("authority", "unreliable")
func clay_owl_move(owl_id: String, pos: Vector2, dir_str: String) -> void:
	clay_owl_move_received.emit(owl_id, pos, dir_str)

@rpc("authority", "reliable")
func clay_owl_explode(owl_id: String, pos: Vector2) -> void:
	clay_owl_explode_received.emit(owl_id, pos)

signal clay_owl_spawn_received(owl_id: String, caster_peer_id: int, from_pos: Vector2, target_id: String)
signal clay_owl_move_received(owl_id: String, pos: Vector2, dir_str: String)
signal clay_owl_explode_received(owl_id: String, pos: Vector2)

# --- Clay Bomb RPCs ---

@rpc("authority", "reliable")
func clay_bomb_spawn(bomb_id: String, pos: Vector2, stage: int, radius: float) -> void:
	clay_bomb_spawn_received.emit(bomb_id, pos, stage, radius)

@rpc("authority", "reliable")
func clay_bomb_stage(bomb_id: String, stage: int, radius: float) -> void:
	clay_bomb_stage_received.emit(bomb_id, stage, radius)

@rpc("authority", "reliable")
func clay_bomb_explode(bomb_id: String, pos: Vector2, radius: float) -> void:
	clay_bomb_explode_received.emit(bomb_id, pos, radius)

signal clay_bomb_spawn_received(bomb_id: String, pos: Vector2, stage: int, radius: float)
signal clay_bomb_stage_received(bomb_id: String, stage: int, radius: float)
signal clay_bomb_explode_received(bomb_id: String, pos: Vector2, radius: float)

# --- C4 Karura RPCs ---

@rpc("authority", "reliable")
func c4_spawn(swarm_id: String, origin: Vector2, seed_val: int, count: int, zone: String = "") -> void:
	c4_spawn_received.emit(swarm_id, origin, seed_val, count, zone)

@rpc("authority", "reliable")
func c4_chain_explode(swarm_id: String, seed_val: int, count: int, dot_delay: float = 0.01, zone: String = "") -> void:
	c4_chain_explode_received.emit(swarm_id, seed_val, count, dot_delay, zone)

signal c4_spawn_received(swarm_id: String, origin: Vector2, seed_val: int, count: int)
signal c4_chain_explode_received(swarm_id: String, seed_val: int, count: int, dot_delay: float)

# --- Target sync ---

@rpc("any_peer", "reliable")
func send_target_update(target_id: String) -> void:
	if not is_server:
		return
	target_update_received.emit(multiplayer.get_remote_sender_id(), target_id)

signal target_update_received(peer_id: int, target_id: String)
