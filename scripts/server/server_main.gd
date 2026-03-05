extends Node

# ============================================================
# SERVER MAIN — All server logic lives here
# Handles login, player management, enemy sync, player sync.
# ============================================================

const SYNC_RATE:       float = 0.05
const ENEMY_SYNC_RATE: float = 0.05

var server_players:     Dictionary = {}
var sync_timer:         float      = 0.0
var enemy_sync_timer:   float      = 0.0
var wolf_node:          Node       = null

func _ready() -> void:
	print("[SERVER] Starting...")
	Network.launch_as_server()
	Network.login_request_received.connect(_on_login_request)
	Network.player_disconnected.connect(_on_player_disconnected)
	Network.step_received.connect(_on_step)
	Network.attack_received.connect(_on_attack)
	print("[SERVER] Signals connected.")
	Arena.build(self, false)
	call_deferred("_spawn_wolf")

func _spawn_wolf() -> void:
	var wolf_scene = load("res://scenes/wolf.tscn")
	if wolf_scene:
		wolf_node = wolf_scene.instantiate()
		wolf_node.global_position = Vector2(200, 100)
		add_child(wolf_node)
		print("[SERVER] Wolf spawned")

func _on_login_request(peer_id: int, username: String) -> void:
	print("[SERVER] Login request — peer: %d  username: '%s'" % [peer_id, username])
	if username.is_empty():
		Network.deny_login(peer_id, "Username cannot be empty.")
		return
	for pid in Network.players:
		if Network.players[pid]["username"] == username and pid != peer_id:
			Network.deny_login(peer_id, "That name is already in use.")
			return
	var player_data = Database.load_player(username)
	Network.players[peer_id]["username"] = username
	Network.accept_login(peer_id, player_data)
	print("[SERVER] Logged in: %s (peer %d)" % [username, peer_id])

	var sp = ServerPlayer.new()
	sp.peer_id  = peer_id
	sp.username = username
	sp.world_pos = player_data.get("position", Vector2.ZERO)
	add_child(sp)
	server_players[peer_id] = sp
	_update_wolf_target()

func _on_player_disconnected(peer_id: int) -> void:
	if server_players.has(peer_id):
		var sp = server_players[peer_id]
		Database.save_player(sp.username, sp.get_save_data())
		sp.queue_free()
		server_players.erase(peer_id)
	print("[SERVER] Player disconnected: peer %d" % peer_id)

func _on_step(peer_id: int, direction: Vector2) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].request_step(direction)

func _on_attack(peer_id: int, direction: Vector2) -> void:
	if server_players.has(peer_id):
		server_players[peer_id].request_attack(direction)

func _update_wolf_target() -> void:
	if wolf_node == null or server_players.is_empty():
		return
	var nearest:      Node  = null
	var nearest_dist: float = INF
	for pid in server_players:
		var sp = server_players[pid]
		var d  = wolf_node.global_position.distance_to(sp.world_pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest      = sp
	if nearest:
		wolf_node.player = nearest

func _process(delta: float) -> void:
	if server_players.size() > 0:
		_update_wolf_target()

	sync_timer += delta
	if sync_timer >= SYNC_RATE:
		sync_timer = 0.0
		_broadcast_players()

	enemy_sync_timer += delta
	if enemy_sync_timer >= ENEMY_SYNC_RATE:
		enemy_sync_timer = 0.0
		_broadcast_enemies()

func _broadcast_players() -> void:
	if Network.players.is_empty():
		return
	var states: Dictionary = {}
	for peer_id in Network.players:
		var p = Network.players[peer_id]
		if p["username"] != "":
			states[peer_id] = {
				"username": p["username"],
				"position": p["position"],
				"zone":     p["zone"]
			}
	if not states.is_empty():
		Network.sync_players.rpc(states)

func _broadcast_enemies() -> void:
	if Network.players.is_empty():
		return
	var states: Dictionary = {}
	var enemies = get_tree().get_nodes_in_group("enemy")
	for i in range(enemies.size()):
		states[i] = {"position": enemies[i].global_position, "type": "wolf"}
	if not states.is_empty():
		Network.sync_enemies.rpc(states)
