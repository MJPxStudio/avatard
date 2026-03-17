extends AbilityBase
class_name AbilitySubstitution

# ============================================================
# SUBSTITUTION JUTSU — Negate next hit, teleport near attacker
# Targeted (primed state)
# ============================================================

const TELEPORT_RADIUS: float = 48.0

func _init() -> void:
	ability_name = "Substitution"
	description  = "Negate the next hit and teleport near your attacker."
	cooldown     = 15.0
	cast_time    = 0.1
	chakra_cost  = 30
	activation   = "targeted"
	icon_color   = Color("f39c12")

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if is_primed:
		return false
	if player.current_chakra < chakra_cost:
		print("[ABILITY] Not enough chakra for Substitution")
		return false
	is_primed = true
	current_cooldown = cooldown
	# Server handles chakra deduction and broadcasts primed visual to all clients
	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "substitution_prime", {})
	return true

# Called by player.gd when taking damage while primed
func try_substitute(player: Node, attacker_position: Vector2) -> bool:
	if not is_primed:
		return false
	is_primed        = false
	current_cooldown = cooldown
	# Teleport to random position around attacker
	var angle    = randf() * TAU
	var offset   = Vector2(cos(angle), sin(angle)) * TELEPORT_RADIUS
	var new_pos  = attacker_position + offset
	# Snap to grid
	var tile     = player.tile_size if "tile_size" in player else 16
	new_pos      = Vector2(round(new_pos.x / tile) * tile, round(new_pos.y / tile) * tile)
	player.global_position = new_pos
	player.grid_pos        = new_pos
	player.target_pos      = new_pos
	# Notify server of teleport so it can broadcast the visual and update position
	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "substitution_triggered", {"new_pos": new_pos})
	return true
