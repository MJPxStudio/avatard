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
const TOTAL_TICKS:    int    = 9999  # runs until possession ends — server_shadow clears it

func _init() -> void:
	ability_name    = "Shadow Strangle"
	description     = "Choke a shadow-bound enemy while they are possessed. %d damage per second." % DAMAGE_PER_TICK
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
	# Find an active possession slot — solo or mass shadow
	var possession_slot = null
	var caught_ids: Array = []
	if player.hotbar != null:
		for slot in player.hotbar.slots:
			if slot == null or not slot.has_method("is_active") or not slot.is_active():
				continue
			if "caught_target_ids" in slot:
				# Mass Shadow Possession
				possession_slot = slot
				caught_ids = slot.caught_target_ids.duplicate()
				break
			elif "caught_target_id" in slot and slot.caught_target_id != "":
				# Solo Shadow Possession
				possession_slot = slot
				caught_ids = [slot.caught_target_id]
				break
	if possession_slot == null or caught_ids.is_empty():
		if player.chat: player.chat.add_system_message("No target caught in Shadow Possession.")
		return false

	# Server handles chakra cost via spend_chakra
	current_cooldown = cooldown

	# Flag possession slot for extra chakra drain
	if "strangle_active" in possession_slot:
		possession_slot.strangle_active = true

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		for tid in caught_ids:
			net.send_ability.rpc_id(1, "shadow_strangle", {
				"caster_pos":    player.global_position,
				"target_id":     tid,
				"range":         RANGE,
				"damage":        DAMAGE_PER_TICK,
				"tick_interval": TICK_INTERVAL,
				"ticks":         TOTAL_TICKS,
			})
	return true
