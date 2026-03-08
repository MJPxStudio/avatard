extends Node2D

# ============================================================
# KUNAI PROJECTILE — Server-side projectile for rogue ninja
# ============================================================

const SPEED:     float = 200.0
const LIFETIME:  float = 1.5
const HIT_RANGE: float = 12.0

var damage:    int     = 18
var direction: Vector2 = Vector2.ZERO
var owner_id:  int     = -1
var lifetime:  float   = LIFETIME

func _ready() -> void:
	damage    = get_meta("damage",    18)
	direction = get_meta("direction", Vector2.DOWN)
	owner_id  = get_meta("owner_id",  -1)
	# Broadcast to clients so they render the visual
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm:
		for peer_id in sm.server_players:
			Network.spawn_kunai.rpc_id(peer_id, global_position, direction)

func _process(delta: float) -> void:
	global_position += direction * SPEED * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return
	_check_hits()

func _check_hits() -> void:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return
	for pid in sm.server_players:
		var sp = sm.server_players[pid]
		if not is_instance_valid(sp):
			continue
		if sp.world_pos.distance_to(global_position) <= HIT_RANGE:
			sp.take_damage(damage, direction, owner_id)
			queue_free()
			return
