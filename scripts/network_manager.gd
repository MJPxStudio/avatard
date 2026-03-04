extends Node

const PORT = 7777
const MAX_CLIENTS = 128
const SERVER_IP = "127.0.0.1"

# All signals declared at top
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

var players: Dictionary = {}
var is_server: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func launch_as_server() -> void:
	is_server = true
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("Failed to start server")
		return
	multiplayer.multiplayer_peer = peer
	print("[SERVER] Started on port %d" % PORT)

func launch_as_client(ip: String = SERVER_IP) -> void:
	is_server = false
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, PORT)
	if err != OK:
		push_error("Failed to connect")
		return
	multiplayer.multiplayer_peer = peer
	print("[CLIENT] Connecting to %s:%d" % [ip, PORT])

func _on_peer_connected(peer_id: int) -> void:
	if is_server:
		players[peer_id] = {"username": "", "zone": "world", "position": Vector2.ZERO}
		player_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if is_server:
		if players.has(peer_id):
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

@rpc("any_peer", "reliable")
func request_login(username: String) -> void:
	if not is_server:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	username = username.strip_edges().left(24)
	login_request_received.emit(peer_id, username)

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
	var peer_id = multiplayer.get_remote_sender_id()
	step_received.emit(peer_id, direction)

@rpc("authority", "unreliable_ordered")
func sync_players(player_states: Dictionary) -> void:
	players_synced_client.emit(player_states)

@rpc("any_peer", "reliable")
func send_attack(direction: Vector2) -> void:
	if not is_server:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	attack_received.emit(peer_id, direction)

@rpc("authority", "reliable")
func sync_damage(target_peer_id: int, amount: int, knockback_dir: Vector2) -> void:
	if target_peer_id == multiplayer.get_unique_id():
		damage_received_client.emit(amount, knockback_dir)

func accept_login(peer_id: int, player_data: Dictionary) -> void:
	notify_login_accepted.rpc_id(peer_id, player_data)

func deny_login(peer_id: int, reason: String) -> void:
	notify_login_denied.rpc_id(peer_id, reason)

@rpc("authority", "unreliable_ordered")
func sync_enemies(enemy_states: Dictionary) -> void:
	enemies_synced_client.emit(enemy_states)

@rpc("authority", "reliable")
func confirm_hit(hit_position: Vector2, amount: int) -> void:
	hit_confirmed.emit(hit_position, amount)

func get_my_id() -> int:
	return multiplayer.get_unique_id()

func is_network_connected() -> bool:
	return multiplayer.multiplayer_peer != null