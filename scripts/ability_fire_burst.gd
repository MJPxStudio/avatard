extends AbilityBase
class_name AbilityFireBurst

# ============================================================
# FIRE BURST — AoE damage ring, instant activation
# Server authoritative hit detection
# ============================================================

const BURST_RADIUS: float = 80.0
const BURST_DAMAGE: int   = 35

func _init() -> void:
	ability_name = "Fire Burst"
	description  = "Erupts in a ring of fire dealing %d damage to nearby enemies." % BURST_DAMAGE
	cooldown     = 6.0
	chakra_cost  = 35
	activation   = "instant"
	icon_color      = Color("e74c3c")
	apply_knockback = false   # AoE explosion — no directional knockback

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		print("[ABILITY] Not enough chakra for Fire Burst")
		return false
	player.current_chakra -= chakra_cost
	current_cooldown = cooldown
	player._update_hud()
	_spawn_visual(player)
	# Send to server for hit detection
	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "fire_burst", {
			"position":  player.global_position,
			"radius":    BURST_RADIUS,
			"damage":    BURST_DAMAGE,
			"knockback": false
		})
	print("[ABILITY] Fire Burst activated at %s" % player.global_position)
	return true

func _spawn_visual(player: Node) -> void:
	const ParticleBurst = preload("res://scripts/particle_burst.gd")
	ParticleBurst.spawn(player.get_tree(), player.global_position, "fire_burst")
