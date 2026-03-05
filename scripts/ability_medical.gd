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
	chakra_cost  = 25
	activation   = "instant"
	icon_color   = Color("2ecc71")

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		print("[ABILITY] Not enough chakra for Medical Jutsu")
		return false
	player.current_chakra -= chakra_cost
	current_cooldown = cooldown
	player.start_hot(HEAL_PER_TICK, TICK_INTERVAL, TOTAL_TICKS)
	player._update_hud()
	print("[ABILITY] Medical Jutsu — healing %d HP over %d seconds" % [HEAL_PER_TICK * TOTAL_TICKS, TOTAL_TICKS])
	return true
