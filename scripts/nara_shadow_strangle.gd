extends AbilityBase

# ============================================================
# SHADOW STRANGLE JUTSU
# Requires target to already be rooted by Shadow Possession.
# Server: applies a DoT for duration.
# Client: pulsing dark aura on caster, damage numbers tick on target.
# ============================================================

const RANGE:         float = 320.0
const DAMAGE_PER_TICK: int   = 12
const TICK_INTERVAL:  float  = 1.0
const TOTAL_TICKS:    int    = 4

func _init() -> void:
	ability_name    = "Shadow Strangle"
	description     = "Choke a shadow-bound enemy for %d damage over %d seconds." % [DAMAGE_PER_TICK * TOTAL_TICKS, TOTAL_TICKS]
	cooldown        = 5.0
	chakra_cost     = 20
	activation      = "instant"
	icon_color      = Color("6030a0")
	apply_knockback = false

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
	if player.global_position.distance_to(target.global_position) > RANGE:
		if player.chat: player.chat.add_system_message("Target out of range.")
		return false
	# Require target to be caught by Shadow Possession
	var has_shadow = false
	if player.hotbar != null:
		for slot in player.hotbar.slots:
			if slot != null and slot.has_method("is_active") and slot.is_active():
				has_shadow = true
				break
	if not has_shadow:
		if player.chat: player.chat.add_system_message("Target must be caught by Shadow Possession first.")
		return false

	player.current_chakra -= chakra_cost
	current_cooldown = cooldown
	player._update_hud()

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "shadow_strangle", {
			"caster_pos":    player.global_position,
			"target_id":     player.locked_target_id,
			"range":         RANGE,
			"damage":        DAMAGE_PER_TICK,
			"tick_interval": TICK_INTERVAL,
			"ticks":         TOTAL_TICKS,
		})
	return true


