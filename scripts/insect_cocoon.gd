extends AbilityBase

# ============================================================
# INSECT COCOON
# Place a hidden bug trap at your feet. Any enemy or hostile
# player that steps within ~1 tile triggers it: root 3s + DoT.
# Stays active for 45 seconds. Single use per cast.
# ============================================================

func _init() -> void:
	ability_name    = "Insect Cocoon"
	description     = "Place a bug trap. Triggers on contact: roots and poisons the target."
	cooldown        = 10.0
	chakra_cost     = 30
	activation      = "instant"
	icon_color      = Color("4e6b28")
	apply_knockback = false
	tags            = ["trap", "debuff"]

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	current_cooldown = cooldown

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "insect_cocoon", {
			"pos":           player.global_position,
			"root_duration": 3.0,
			"damage":        8,
			"tick_interval": 1.0,
			"ticks":         6,
		})
	return true
