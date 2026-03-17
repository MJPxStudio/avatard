extends AbilityBase

# ============================================================
# C2 OWL — Clay Clan
# Launch a clay owl toward the locked target.
# On arrival it circles the target (50-60px orbit), dropping
# a spider every second for 5 seconds, then explodes.
# Can be destroyed early — explodes on death regardless.
# ============================================================

const DAMAGE_EXPLOSION: int   = 64    # 2x spider (32)
const TRAVEL_SPEED:     float = 240.0 # faster than player run (~190)

func _init() -> void:
	ability_name = "Clay Owl"
	description  = "Summon a clay owl that circles the target, dropping spiders before detonating."
	cooldown     = 5.0   # 5 for testing, change to 25 when ready
	cast_time    = 0.5
	chakra_cost  = 75
	activation   = "instant"
	icon_color   = Color("e8c898")

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	print("[C2_OWL] activate called")
	if not is_ready():
		print("[C2_OWL] not ready, cooldown=", current_cooldown)
		return false
	if player.locked_target == null or not is_instance_valid(player.locked_target):
		print("[C2_OWL] no locked target")
		if player.chat:
			player.chat.add_system_message("No target locked.")
		return false

	print("[C2_OWL] casting at target=", player.locked_target_id)
	var cost_mult: float = player.boon_chakra_cost_mult
	var actual_cost: int = max(1, int(chakra_cost * cost_mult))
	if player.current_chakra < actual_cost:
		if player.chat:
			player.chat.add_system_message("Not enough chakra.")
		return false
	player.current_chakra -= actual_cost
	var cd_bonus: float = player.boon_c2_cooldown_flat
	effective_cooldown = max(0.5, cooldown + cd_bonus)
	current_cooldown   = effective_cooldown
	player._update_hud()

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "c2_owl", {
			"caster_pos":       player.global_position,
			"target_id":        player.locked_target_id,
			"effective_cooldown": effective_cooldown,
		})
	else:
		print("[C2_OWL] network not connected")
	return true
