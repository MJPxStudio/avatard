extends AbilityBase
class_name AbilityMedical

# ============================================================
# MEDICAL JUTSU — Heal over time, instant activation
# ============================================================

const HEAL_PER_TICK:  int   = 8
const TICK_INTERVAL:  float = 1.0
const TOTAL_TICKS:    int   = 5

func _init() -> void:
	ability_name = "Medical Jutsu"
	description  = "Heals you for %d HP over %d seconds." % [HEAL_PER_TICK * TOTAL_TICKS, TOTAL_TICKS]
	cooldown     = 12.0
	cast_time    = 0.4
	chakra_cost  = 25
	activation   = "instant"
	icon_color   = Color("2ecc71")

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		print("[ABILITY] Not enough chakra for Medical Jutsu")
		return false
	current_cooldown = cooldown
	# Server handles chakra deduction, applies HoT, and confirms via sync
	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "medical_jutsu", {
			"heal_per_tick": HEAL_PER_TICK,
			"interval":      TICK_INTERVAL,
			"ticks":         TOTAL_TICKS,
		})
	else:
		# Offline fallback
		player.start_hot(HEAL_PER_TICK, TICK_INTERVAL, TOTAL_TICKS)
	return true
