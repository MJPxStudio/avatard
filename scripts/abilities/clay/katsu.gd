extends AbilityBase

# ============================================================
# KAGURA — KATSU
# Detonate all of your active clay simultaneously.
# Spiders, owl, bomb, and C4 dots all detonate with 0.1s
# between each piece. C3 detonates at half damage.
# ============================================================

func _init() -> void:
	ability_name = "Katsu"
	description  = "Detonate all active clay simultaneously."
	cooldown     = 60.0
	cast_stand_still = true
	cast_time    = 0.9
	chakra_cost  = 50
	activation   = "instant"
	icon_color   = Color("ff2200")

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

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "katsu", {})
	return true
