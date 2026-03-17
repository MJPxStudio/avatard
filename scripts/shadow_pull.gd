extends AbilityBase

# ============================================================
# SHADOW PULL
# Extends shadow to yank a target toward the caster.
# Server: teleports target to just in front of caster.
# Client: dark tendril line shrinking toward player.
# ============================================================

const RANGE:       float = 256.0   # 16 tiles
const PULL_DIST:   float = 48.0    # how close they end up

func _init() -> void:
	ability_name    = "Shadow Pull"
	description     = "Yank an enemy toward you with your shadow."
	cooldown        = 6.0
	cast_time    = 0.4
	chakra_cost     = 20
	activation      = "instant"
	icon_color      = Color("7040b0")
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

	player.current_chakra -= chakra_cost
	current_cooldown = cooldown
	player._update_hud()
	_spawn_visual(player, target.global_position)

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "shadow_pull", {
			"caster_pos": player.global_position,
			"target_id":  player.locked_target_id,
			"range":      RANGE,
			"pull_dist":  PULL_DIST,
		})
	return true

func _spawn_visual(player: Node, target_pos: Vector2) -> void:
	# Tendril: starts at target, shrinks to player
	var line = Line2D.new()
	line.width         = 4.0
	line.default_color = Color(0.45, 0.1, 0.7, 0.95)
	line.add_point(player.global_position)
	line.add_point(target_pos)
	line.z_index = 5
	player.get_parent().add_child(line)

	var tween = player.get_tree().create_tween()
	# Animate end point toward player
	tween.tween_method(func(t: float):
		if is_instance_valid(line):
			line.set_point_position(1, target_pos.lerp(player.global_position, t))
	, 0.0, 1.0, 0.25)
	tween.tween_property(line, "modulate:a", 0.0, 0.1)
	tween.tween_callback(line.queue_free)
