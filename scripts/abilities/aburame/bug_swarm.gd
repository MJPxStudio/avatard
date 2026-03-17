extends AbilityBase

# ============================================================
# BUG SWARM
# Release a cone of kikaichu that fan out forward.
# Server: hits all targets in a 60-degree cone, then schedules
# 3 additional DoT ticks (1s apart) as the cloud lingers.
# Client: green-brown particle flash on cast.
# ============================================================

const RANGE:          float = 160.0   # 10 tiles
const CONE_HALF_DEG:  float = 30.0    # 60 degree total cone
const DAMAGE_PER_TICK: int  = 6
const TICK_COUNT:     int   = 4       # initial hit + 3 lingering ticks
const TICK_INTERVAL:  float = 1.0

func _init() -> void:
	ability_name    = "Bug Swarm"
	description     = "Release a swarm of kikaichu in a cone. Targets are bitten for damage over time."
	cooldown        = 5.0
	cast_time    = 0.4
	chakra_cost     = 20
	activation      = "instant"
	icon_color      = Color("556b2f")
	apply_knockback = false
	tags            = ["dot"]

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	current_cooldown = cooldown

	# Aim at locked target if one exists, otherwise use facing direction
	var aim_dir: Vector2
	if player.locked_target != null and is_instance_valid(player.locked_target):
		aim_dir = (player.locked_target.global_position - player.global_position).normalized()
	else:
		aim_dir = player._facing_vec()

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "bug_swarm", {
			"caster_pos":    player.global_position,
			"aim_dir":       aim_dir,
			"range":         RANGE,
			"cone_half_deg": CONE_HALF_DEG,
			"damage":        DAMAGE_PER_TICK,
			"ticks":         TICK_COUNT,
			"tick_interval": TICK_INTERVAL,
		})
	return true
