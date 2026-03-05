extends Node

# ============================================================
# NETWORK MANAGER — Pure transport layer
# Handles connection setup and RPC routing only.
# No game logic lives here.
# ============================================================

const MAX_CLIENTS    = 128
const LOCAL_CONFIG   = "res://server_config.json"
const DEV_CONFIG     = "res://local_dev.cfg"
const REMOTE_CONFIG  = "https://raw.githubusercontent.com/MJPxStudio/avatard/main/server_config.json"

var PORT:       int    = 7777
var SERVER_IP:  String = "0.0.0.0"
var LOCAL_IP:   String = "127.0.0.1"
var is_server:  bool   = false
var dev_mode:   bool   = false
var config_loaded: bool = false   # true once config is ready

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
signal step_received(peer_id, direction)
signal attack_received(peer_id, direction)
signal players_synced_client(states)
signal damage_received_client(amount, knockback_dir)
signal enemies_synced_client(states)
signal hit_confirmed(position, amount)

# Tracks connected peers (server only)
var players: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Dev mode: skip remote fetch, use local config immediately
	if FileAccess.file_exists(DEV_CONFIG):
		_load_config(DEV_CONFIG, true)
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
	var data = json.get_data()
	SERVER_IP = data.get("server_ip", SERVER_IP)
	LOCAL_IP  = data.get("local_ip",  LOCAL_IP)
	PORT      = data.get("port",      PORT)
	dev_mode  = is_dev
	print("[NETWORK] Config loaded (%s): %s | local: %s | port: %d" % [
		"DEV" if is_dev else "release", SERVER_IP, LOCAL_IP, PORT])

func _fetch_remote_config() -> void:
	var http = HTTPRequest.new()
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
			var data = json.get_data()
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

# --- Server / Client launch ---

func launch_as_server() -> void:
	is_server = true
	var peer = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_CLIENTS) != OK:
		push_error("[NETWORK] Failed to start server on port %d" % PORT)
		return
	multiplayer.multiplayer_peer = peer
	print("[SERVER] Started on port %d" % PORT)

func launch_as_client() -> void:
	is_server = false
	var ip = LOCAL_IP if (dev_mode or "--local" in OS.get_cmdline_args()) else SERVER_IP
	print("[CLIENT] Connecting to %s:%d" % [ip, PORT])
	var peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		push_error("[NETWORK] Failed to connect to %s:%d" % [ip, PORT])
		return
	multiplayer.multiplayer_peer = peer

# --- Multiplayer callbacks ---

func _on_peer_connected(peer_id: int) -> void:
	if is_server:
		players[peer_id] = {"username": "", "zone": "world", "position": Vector2.ZERO}
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
func send_step(direction: Vector2) -> void:
	if not is_server:
		return
	step_received.emit(multiplayer.get_remote_sender_id(), direction)

@rpc("any_peer", "reliable")
func send_attack(direction: Vector2) -> void:
	if not is_server:
		return
	attack_received.emit(multiplayer.get_remote_sender_id(), direction)

@rpc("authority", "unreliable_ordered")
func sync_players(states: Dictionary) -> void:
	players_synced_client.emit(states)

@rpc("authority", "reliable")
func sync_damage(target_peer_id: int, amount: int, knockback_dir: Vector2) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		damage_received_client.emit(amount, knockback_dir)

@rpc("authority", "unreliable_ordered")
func sync_enemies(states: Dictionary) -> void:
	enemies_synced_client.emit(states)

@rpc("authority", "reliable")
func confirm_hit(hit_position: Vector2, amount: int) -> void:
	hit_confirmed.emit(hit_position, amount)

# --- Helpers ---

func accept_login(peer_id: int, data: Dictionary) -> void:
	notify_login_accepted.rpc_id(peer_id, data)

func deny_login(peer_id: int, reason: String) -> void:
	notify_login_denied.rpc_id(peer_id, reason)

func get_my_id() -> int:
	return multiplayer.get_unique_id()

func is_network_connected() -> bool:
	return multiplayer.multiplayer_peer != null
