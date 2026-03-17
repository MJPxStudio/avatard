extends AbilityBase

# ============================================================
# C3 BOMB — Clay Clan
# Place a massive clay bomb at the caster's feet.
# Grows over 10 seconds through 4 stages then detonates.
# Hits caster too. Kagura can detonate early at half damage.
# ============================================================

func _init() -> void:
	ability_name = "C3"
	description  = "Place a massive clay bomb that grows and detonates everything nearby."
	cooldown     = 30.0
	cast_stand_still = true
	cast_time    = 0.7
	chakra_cost  = 150
	activation   = "instant"
	icon_color   = Color("c8500a")

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	var cost_mult: float = player.boon_chakra_cost_mult
	var actual_cost: int = max(1, int(chakra_cost * cost_mult))
	if player.current_chakra < actual_cost:
		if player.chat:
			player.chat.add_system_message("Not enough chakra.")
		return false
	player.current_chakra -= actual_cost
	var cd_bonus: float = player.boon_c3_cooldown_flat
	effective_cooldown = max(1.0, cooldown + cd_bonus)
	current_cooldown   = effective_cooldown
	player._update_hud()

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "c3_bomb", {
			"caster_pos":       player.global_position,
			"effective_cooldown": effective_cooldown,
		})
	return true
