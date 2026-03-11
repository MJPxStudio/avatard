extends AbilityBase

# ============================================================
# MASS SHADOW POSSESSION
# AoE root — shadow spreads in a wide radius around caster.
# Roots all enemies and hostile players within range.
# ============================================================

const RADIUS:        float = 160.0  # 10 tiles
const ROOT_DURATION: float = 3.0

func _init() -> void:
	ability_name    = "Mass Shadow Possession"
	description     = "Spread your shadow wide, binding all nearby enemies."
	cooldown        = 18.0
	chakra_cost     = 60
	activation      = "instant"
	icon_color      = Color("3a2080")
	apply_knockback = false

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	player.current_chakra -= chakra_cost
	current_cooldown = cooldown
	player._update_hud()
	_spawn_visual(player)

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "mass_shadow", {
			"caster_pos": player.global_position,
			"radius":     RADIUS,
			"duration":   ROOT_DURATION,
		})
	return true

func _spawn_visual(player: Node) -> void:
	# Expanding dark ring
	var ring = Node2D.new()
	ring.position = player.global_position
	ring.z_index  = 3
	player.get_parent().add_child(ring)

	var draw_radius: float = 10.0
	ring.draw.connect(func():
		ring.draw_arc(Vector2.ZERO, draw_radius, 0, TAU, 48,
			Color(0.3, 0.05, 0.5, 0.7), 3.0)
	)
	ring.queue_redraw()

	var tween = player.get_tree().create_tween()
	tween.tween_method(func(r: float):
		draw_radius = r
		if is_instance_valid(ring):
			ring.queue_redraw()
	, 10.0, RADIUS, 0.35)
	tween.tween_property(ring, "modulate:a", 0.0, 0.25)
	tween.tween_callback(ring.queue_free)

	# Dark flash on player
	var tween2 = player.get_tree().create_tween()
	tween2.tween_property(player, "modulate", Color(0.4, 0.1, 0.7, 1.0), 0.1)
	tween2.tween_property(player, "modulate", Color(1, 1, 1, 1), 0.3)
