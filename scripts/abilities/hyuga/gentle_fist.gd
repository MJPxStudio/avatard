extends AbilityBase

# ============================================================
# GENTLE FIST
# Melee-range instant strike. Same damage as a normal attack.
# Drains a small amount of chakra from both caster and target.
# ============================================================

const MELEE_RANGE:    float = 48.0
const DAMAGE:         int   = 18
const SELF_DRAIN:     int   = 8   # chakra drained from caster on use
const TARGET_DRAIN:   int   = 20  # chakra drained from target (PvP + enemies)

func _init() -> void:
	ability_name    = "Gentle Fist"
	description     = "A precise palm strike that disrupts the target's chakra network."
	cooldown        = 7.0
	cast_time    = 0.3
	chakra_cost     = 15
	activation      = "instant"
	icon_color      = Color("c8e6fa")
	apply_knockback = false

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false
	var target = player.locked_target
	if target == null or not is_instance_valid(target):
		if player.chat: player.chat.add_system_message("No target selected.")
		return false
	if player.global_position.distance_to(target.global_position) > MELEE_RANGE:
		if player.chat: player.chat.add_system_message("Too far away.")
		return false

	current_cooldown = cooldown

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "gentle_fist", {
			"caster_pos":   player.global_position,
			"target_id":    player.locked_target_id,
			"damage":       DAMAGE,
			"target_drain": TARGET_DRAIN,
			"range":        MELEE_RANGE,
		})
	return true
