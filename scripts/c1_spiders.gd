extends AbilityBase

# ============================================================
# C1 SPIDERS — Clay Clan
# Throw a small clay spider in a straight line.
# Explodes on contact OR after 5 seconds.
# Kagura hook: server tracks active spiders per peer for manual detonation.
# ============================================================

const RANGE:      float = 800.0   # ~5 s at SPEED 160
const DAMAGE:     int   = 32
const SPEED:      float = 160.0

func _init() -> void:
	ability_name = "Clay Spider"
	description  = "Throw a clay spider that explodes on contact or after 5 seconds."
	cooldown     = 1.5
	chakra_cost  = 12
	activation   = "instant"
	icon_color   = Color("c8a86e")

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat:
			player.chat.add_system_message("Not enough chakra.")
		return false

	player.current_chakra -= chakra_cost
	current_cooldown = cooldown
	player._update_hud()

	# Aim toward locked target, fall back to facing direction
	var aim_dir: Vector2
	var locked = player.locked_target
	if locked != null and is_instance_valid(locked):
		aim_dir = (locked.global_position - player.global_position).normalized()
	else:
		aim_dir = player._facing_vec()

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "c1_spiders", {
			"caster_pos": player.global_position,
			"aim_dir":    aim_dir,
			"damage":     DAMAGE,
			"range":      RANGE,
			"speed":      SPEED,
			"target_id":  player.locked_target_id if player.locked_target != null else "",
		})
	return true
