extends Node

var enemy_sync_timer: float = 0.0
const ENEMY_SYNC_RATE: float = 0.05
var wolf_node = null

func _ready() -> void:
	print("[SERVER] Starting...")
	Network.launch_as_server()
	Network.login_request_received.connect(_on_login_request)
	# Build arena collision geometry (no visuals on server)
	Arena.build(self, false)
	# Spawn wolf - deferred so scene tree is ready
	call_deferred("_spawn_wolf")

func _spawn_wolf() -> void:
	var wolf_scene = load("res://scenes/wolf.tscn")
	if wolf_scene:
		wolf_node = wolf_scene.instantiate()
		wolf_node.global_position = Vector2(200, 100)
		add_child(wolf_node)
		print("[SERVER] Wolf spawned")

func _on_login_request(peer_id: int, username: String) -> void:
	if username.is_empty():
		Network.deny_login(peer_id, "Invalid username.")
		return
	for pid in Network.players:
		if Network.players[pid]["username"] == username and pid != peer_id:
			Network.deny_login(peer_id, "Already logged in.")
			return
	Network.players[peer_id]["username"] = username
	var player_data = Database.load_player(username)
	Network.accept_login(peer_id, player_data)
	print("[SERVER] Player logged in: %s (peer %d)" % [username, peer_id])
	var sp = ServerPlayer.new()
	sp.peer_id = peer_id
	sp.username = username
	sp.world_pos = player_data.get("position", Vector2.ZERO)
	add_child(sp)
	GameState.server_players[peer_id] = sp
	# Update wolf target to nearest server player
	_update_wolf_target()
	print("[SERVER] ServerPlayer spawned for %s, total: %d" % [username, GameState.server_players.size()])

func _update_wolf_target() -> void:
	if wolf_node == null or GameState.server_players.size() == 0:
		return
	# Find nearest server player and give wolf a proper target node
	var nearest: Node = null
	var nearest_dist = INF
	for pid in GameState.server_players:
		var sp = GameState.server_players[pid]
		var d = wolf_node.global_position.distance_to(sp.world_pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = sp
	if nearest:
		wolf_node.player = nearest

func _process(delta: float) -> void:
	# Keep wolf targeting nearest server player
	if wolf_node and GameState.server_players.size() > 0:
		_update_wolf_target()
	enemy_sync_timer += delta
	if enemy_sync_timer >= ENEMY_SYNC_RATE:
		enemy_sync_timer = 0.0
		_broadcast_enemies()

func _broadcast_enemies() -> void:
	if Network.players.size() == 0:
		return
	var states = {}
	var enemies = get_tree().get_nodes_in_group("enemy")
	for i in range(enemies.size()):
		states[i] = {"position": enemies[i].global_position, "type": "wolf"}
	if states.size() > 0:
		Network.sync_enemies.rpc(states)
