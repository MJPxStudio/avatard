extends Node

signal login_accepted(player_data)
signal login_denied(reason)
signal players_synced(states)
signal damage_received(amount, knockback_dir)
signal player_left(peer_id, username)
signal server_player_joined(peer_id, player_data)

var my_username: String = ""
var my_player_data: Dictionary = {}
var remote_players: Dictionary = {}
var server_players: Dictionary = {}
var sync_timer: float = 0.0
const SYNC_RATE: float = 0.05

func _ready() -> void:
	# Use call_deferred so Network is guaranteed to exist
	call_deferred("_connect_signals")

var remote_enemy_nodes: Dictionary = {}  # enemy_id -> Node2D

func _connect_signals() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net == null:
		push_error("Network autoload not found")
		return
	net.login_accepted_client.connect(_on_login_accepted)
	net.login_denied_client.connect(_on_login_denied)
	net.players_synced_client.connect(_on_players_synced)
	net.damage_received_client.connect(_on_damage_received)
	net.step_received.connect(server_handle_step)
	net.attack_received.connect(server_handle_attack)
	net.player_disconnected.connect(_on_player_disconnected)
	net.enemies_synced_client.connect(_on_enemies_synced)

func _on_enemies_synced(states: Dictionary) -> void:
	if world_node == null:
		return
	for enemy_id in states:
		var state = states[enemy_id]
		if not remote_enemy_nodes.has(enemy_id):
			var re = Node2D.new()
			re.set_script(load("res://scripts/remote_enemy.gd"))
			world_node.add_child(re)
			re.global_position = state.get("position", Vector2.ZERO)
			remote_enemy_nodes[enemy_id] = re
		else:
			remote_enemy_nodes[enemy_id].update_position(state.get("position", Vector2.ZERO))
	for enemy_id in remote_enemy_nodes.keys():
		if not states.has(enemy_id):
			remote_enemy_nodes[enemy_id].queue_free()
			remote_enemy_nodes.erase(enemy_id)


func _on_login_accepted(player_data: Dictionary) -> void:
	my_username = player_data.get("username", "")
	my_player_data = player_data
	login_accepted.emit(player_data)

func _on_login_denied(reason: String) -> void:
	login_denied.emit(reason)

var remote_player_nodes: Dictionary = {}
var world_node = null

func _on_players_synced(states: Dictionary) -> void:
	remote_players = states
	players_synced.emit(states)
	_update_remote_player_nodes(states)

func _update_remote_player_nodes(states: Dictionary) -> void:
	if world_node == null:
		return
	var my_id = get_tree().root.get_node_or_null("Network")
	var my_peer_id = my_id.get_my_id() if my_id else -1

	# Spawn or update remote players
	for peer_id in states:
		if peer_id == my_peer_id:
			continue
		var state = states[peer_id]
		if not remote_player_nodes.has(peer_id):
			# Spawn new remote player
			var rp = Node2D.new()
			rp.set_script(load("res://scripts/remote_player.gd"))
			rp.peer_id = peer_id
			world_node.add_child(rp)
			rp.set_username(state.get("username", "?"))
			rp.global_position = state.get("position", Vector2.ZERO)
			rp.target_position = rp.global_position
			remote_player_nodes[peer_id] = rp
		else:
			# Update position
			remote_player_nodes[peer_id].update_position(state.get("position", Vector2.ZERO))

	# Remove disconnected players
	for peer_id in remote_player_nodes.keys():
		if not states.has(peer_id):
			remote_player_nodes[peer_id].queue_free()
			remote_player_nodes.erase(peer_id)

func _on_damage_received(amount: int, knockback_dir: Vector2) -> void:
	damage_received.emit(amount, knockback_dir)

func _on_player_disconnected(peer_id: int) -> void:
	if server_players.has(peer_id):
		var sp = server_players[peer_id]
		var db = get_tree().root.get_node_or_null("Database")
		db.save_player(sp.username, sp.get_save_data())
		sp.queue_free()
		server_players.erase(peer_id)
	remote_players.erase(peer_id)

func server_handle_step(peer_id: int, direction: Vector2) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].request_step(direction)

func server_handle_attack(peer_id: int, direction: Vector2) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].request_attack(direction)

func _process(delta: float) -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net == null or not net.is_server:
		return
	sync_timer += delta
	if sync_timer >= SYNC_RATE:
		sync_timer = 0.0
		_broadcast_player_states()

func _broadcast_player_states() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net == null:
		return
	var states = {}
	for peer_id in net.players:
		var p = net.players[peer_id]
		if p["username"] != "":
			states[peer_id] = {
				"username": p["username"],
				"position": p["position"],
				"zone": p["zone"]
			}
	if states.size() > 0:
		net.sync_players.rpc(states)
