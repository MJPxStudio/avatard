extends AbilityBase

# ============================================================
# AIR PALM
# Fires a compressed chakra blast at the locked target.
# Fast travel animation on clients. Low-moderate damage + knockback.
# ============================================================

const RANGE:     float = 320.0
const DAMAGE:    int   = 22
const KB_FORCE:  float = 1.0   # normalized, server applies directional knockback

func _init() -> void:
	ability_name    = "Air Palm"
	description     = "Launch a concentrated burst of chakra that blasts the enemy backwards."
	cooldown        = 6.0
	cast_time    = 0.4
	chakra_cost     = 25
	activation      = "instant"
	icon_color      = Color("90d8ff")
	apply_knockback = true

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	current_cooldown = cooldown

	# Aim toward locked target if available, otherwise use facing direction
	var aim_dir: Vector2
	var locked = player.locked_target
	if locked != null and is_instance_valid(locked):
		aim_dir = (locked.global_position - player.global_position).normalized()
	else:
		match player.get("facing_dir"):
			"up":    aim_dir = Vector2.UP
			"down":  aim_dir = Vector2.DOWN
			"left":  aim_dir = Vector2.LEFT
			_:       aim_dir = Vector2.RIGHT

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "air_palm", {
			"caster_pos": player.global_position,
			"aim_dir":    aim_dir,
			"damage":     DAMAGE,
			"range":      RANGE,
			"splash":     24.0,
			"target_id":  player.locked_target_id if player.locked_target != null else "",
		})
	return true
