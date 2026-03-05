extends Node

# ============================================================
# GAME STATE — Client-side state only
# Tracks the local player's data and all remote players/enemies.
# No server logic lives here.
# ============================================================

signal login_accepted(player_data)
signal login_denied(reason)
signal players_synced(states)
signal damage_received(amount, knockback_dir)

var my_username:    String     = ""
var my_player_data: Dictionary = {}
var remote_players: Dictionary = {}
var world_node:     Node       = null

var remote_player_nodes: Dictionary = {}
var remote_enemy_nodes:  Dictionary = {}

func _ready() -> void:
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	Network.login_accepted_client.connect(_on_login_accepted)
	Network.login_denied_client.connect(_on_login_denied)
	Network.players_synced_client.connect(_on_players_synced)
	Network.damage_received_client.connect(_on_damage_received)
	Network.enemies_synced_client.connect(_on_enemies_synced)
	Network.player_disconnected.connect(_on_player_disconnected)

func _on_login_accepted(player_data: Dictionary) -> void:
	my_username    = player_data.get("username", "")
	my_player_data = player_data
	login_accepted.emit(player_data)

func _on_login_denied(reason: String) -> void:
	login_denied.emit(reason)

func _on_players_synced(states: Dictionary) -> void:
	remote_players = states
	players_synced.emit(states)
	_update_remote_players(states)

func _update_remote_players(states: Dictionary) -> void:
	if world_node == null:
		return
	var my_id = Network.get_my_id()
	for peer_id in states:
		if peer_id == my_id:
			continue
		var state = states[peer_id]
		if not remote_player_nodes.has(peer_id):
			var rp = Node2D.new()
			rp.set_script(load("res://scripts/remote_player.gd"))
			world_node.add_child(rp)
			rp.peer_id = peer_id
			rp.set_username(state.get("username", "?"))
			rp.global_position = state.get("position", Vector2.ZERO)
			rp.target_position = rp.global_position
			remote_player_nodes[peer_id] = rp
		else:
			remote_player_nodes[peer_id].update_position(state.get("position", Vector2.ZERO))
	for peer_id in remote_player_nodes.keys():
		if not states.has(peer_id):
			remote_player_nodes[peer_id].queue_free()
			remote_player_nodes.erase(peer_id)

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

func _on_damage_received(amount: int, knockback_dir: Vector2) -> void:
	damage_received.emit(amount, knockback_dir)

func _on_player_disconnected(peer_id: int) -> void:
	remote_players.erase(peer_id)
	if remote_player_nodes.has(peer_id):
		remote_player_nodes[peer_id].queue_free()
		remote_player_nodes.erase(peer_id)
