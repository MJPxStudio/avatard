extends CharacterBody2D
class_name ServerPlayer

const TILE_SIZE = 16

func _ready() -> void:
	add_to_group("player")
	# Add collision shape matching the player scene
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(10, 14)
	shape.shape = rect
	add_child(shape)
	collision_layer = 2
	collision_mask = 3  # hits walls (layer 1) and other players/enemies (layer 2)
var peer_id: int = -1
var username: String = ""
var world_pos: Vector2 = Vector2.ZERO
var zone: String = "world"
var hp: int = 100
var max_hp: int = 100
var stat_strength: int = 5

# Wolf compat properties
var invuln_ticks: float = 0.0
var is_dead: bool = false
var bleed_ticks: int = 0
var bleed_damage: int = 2
var bleed_timer: float = 1.0

func request_step(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		Network.players[peer_id]["position"] = world_pos
		global_position = world_pos
		return
	var next = world_pos + Vector2(sign(dir.x) * TILE_SIZE, sign(dir.y) * TILE_SIZE)
	if abs(next.x) < 750 and abs(next.y) < 500:
		world_pos = next
		global_position = world_pos
		move_and_slide()
		world_pos = global_position
		Network.players[peer_id]["position"] = world_pos

func request_attack(dir: Vector2) -> void:
	var d = dir.normalized()
	# Hit other players
	for oid in GameState.server_players:
		if oid == peer_id:
			continue
		var other = GameState.server_players[oid]
		if other.zone != zone:
			continue
		var to_o = other.world_pos - world_pos
		var fwd = to_o.dot(d)
		var lat = abs(to_o.dot(Vector2(-d.y, d.x)))
		if fwd > 0 and fwd < 42.0 and lat < 24.0:
			other.take_damage(15 + int(stat_strength * 0.4), d, peer_id)
	# Hit wolves/enemies
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		var to_e = enemy.global_position - world_pos
		var fwd = to_e.dot(d)
		var lat = abs(to_e.dot(Vector2(-d.y, d.x)))
		if fwd > 0 and fwd < 42.0 and lat < 24.0:
			var dmg = 15 + int(stat_strength * 0.4)
			if enemy.has_method("take_damage"):
				enemy.take_damage(dmg, d)
			# Confirm hit to client so it can show damage number
			Network.confirm_hit.rpc_id(peer_id, enemy.global_position, dmg)

func take_damage(amount: int, knockback_dir: Vector2, attacker = null) -> void:
	if invuln_ticks > 0 or is_dead:
		return
	hp = max(0, hp - amount)
	invuln_ticks = 0.5
	# Send damage to client
	Network.sync_damage.rpc_id(peer_id, peer_id, amount, knockback_dir)
	if hp <= 0:
		hp = max_hp
		world_pos = Vector2.ZERO
		global_position = world_pos
		Network.players[peer_id]["position"] = world_pos

func _process(delta: float) -> void:
	# Tick invuln
	if invuln_ticks > 0:
		invuln_ticks -= delta
	# Tick bleed
	if bleed_ticks > 0:
		bleed_timer -= delta
		if bleed_timer <= 0:
			bleed_timer = 1.0
			take_damage(bleed_damage, Vector2.ZERO)
			bleed_ticks -= 1

func get_save_data() -> Dictionary:
	return {
		"username": username, "level": 1, "exp": 0,
		"stat_hp": 5, "stat_chakra": 5, "stat_str": stat_strength,
		"stat_dex": 5, "stat_int": 5, "stat_points": 0,
		"position": world_pos, "zone": zone
	}
