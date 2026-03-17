extends AbilityBase

# ============================================================
# C4 KARURA — Clay Clan
# Rapidly fires 30 micro clay projectiles in all directions.
# Each drifts for 8 seconds then chain-detonates in spawn order
# with 0.05s between each explosion.
# ============================================================

func _init() -> void:
	ability_name = "C4 Karura"
	description  = "Release a swarm of micro clay projectiles that blanket the area before detonating."
	cooldown     = 45.0
	cast_stand_still = true
	cast_time    = 0.9
	chakra_cost  = 125
	activation   = "instant"
	icon_color   = Color("ff4400")

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
	effective_cooldown = cooldown
	current_cooldown   = effective_cooldown
	player._update_hud()

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "c4_karura", {
			"caster_pos":       player.global_position,
			"effective_cooldown": effective_cooldown,
		})
	return true
