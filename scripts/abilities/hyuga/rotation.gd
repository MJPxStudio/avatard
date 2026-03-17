extends AbilityBase

# ============================================================
# EIGHT TRIGRAMS: PALM ROTATION
# Full damage immunity for 2 seconds. While spinning, deals
# damage to all enemies within melee range every 0.5s.
# Server sets is_immune = true and schedules the clear.
# ============================================================

const SPIN_RADIUS:    float = 52.0
const SPIN_DAMAGE:    int   = 15   # per tick
const SPIN_DURATION:  float = 2.0
const TICK_INTERVAL:  float = 0.5  # 4 hits over 2 seconds
const COOLDOWN_TIME:  float = 15.0

func _init() -> void:
	ability_name    = "Eight Trigrams: Palm Rotation"
	description     = "Spin rapidly releasing chakra. Become immune to damage and harm all nearby enemies."
	cooldown        = COOLDOWN_TIME
	cast_time    = 0.6
	chakra_cost     = 35
	activation      = "instant"
	icon_color      = Color("60b8ff")
	apply_knockback = false

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	current_cooldown = cooldown

	# Lock movement immediately on the client — don't wait for server round-trip.
	# Server owns immunity and damage; client owns its own input lock.
	player.is_spinning = true
	player.flash_visual("rotation_start")
	var t = player.get_tree().create_timer(SPIN_DURATION)
	t.timeout.connect(func() -> void:
		player.is_spinning = false
		player.flash_visual("rotation_end")
	)

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "palm_rotation", {
			"caster_pos": player.global_position,
			"radius":     SPIN_RADIUS,
			"damage":     SPIN_DAMAGE,
			"duration":   SPIN_DURATION,
			"interval":   TICK_INTERVAL,
		})
	return true
