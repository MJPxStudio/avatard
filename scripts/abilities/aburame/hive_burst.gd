extends AbilityBase

# ============================================================
# HIVE BURST
# Detonate a swarm of bugs in an explosion around the caster.
# Deals AoE damage to all enemies/hostile players in range.
# Chunin rank required.
# ============================================================

const RADIUS: float = 96.0   # 6 tiles
const DAMAGE: int   = 40

func _init() -> void:
	ability_name    = "Hive Burst"
	description     = "Detonate your kikaichu in a burst of chitinous fury. Deals %d damage to all nearby enemies." % DAMAGE
	cooldown        = 12.0
	cast_time    = 0.6
	chakra_cost     = 45
	activation      = "instant"
	icon_color      = Color("6a7a30")
	apply_knockback = true
	tags            = ["aoe"]

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	current_cooldown = cooldown

	player.flash_visual("hive_burst_cast")

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "hive_burst", {
			"caster_pos": player.global_position,
			"radius":     RADIUS,
			"damage":     DAMAGE,
		})
	return true
