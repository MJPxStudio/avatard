extends AbilityBase
class_name AbilitySubstitution

# ============================================================
# SUBSTITUTION JUTSU — Negate next hit, teleport near attacker
# Targeted (primed state)
# ============================================================

const TELEPORT_RADIUS: float = 48.0

func _init() -> void:
	ability_name = "Substitution"
	description  = "Negate the next hit and teleport near your attacker."
	cooldown     = 15.0
	chakra_cost  = 30
	activation   = "targeted"
	icon_color   = Color("f39c12")

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if is_primed:
		return false
	if player.current_chakra < chakra_cost:
		print("[ABILITY] Not enough chakra for Substitution")
		return false
	player.current_chakra -= chakra_cost
	is_primed = true
	player._update_hud()
	# Visual indicator — player flickers yellow
	_show_primed_visual(player)
	print("[ABILITY] Substitution primed — next hit will be negated")
	return true

# Called by player.gd when taking damage while primed
func try_substitute(player: Node, attacker_position: Vector2) -> bool:
	if not is_primed:
		return false
	is_primed        = false
	current_cooldown = cooldown
	# Teleport to random position around attacker
	var angle    = randf() * TAU
	var offset   = Vector2(cos(angle), sin(angle)) * TELEPORT_RADIUS
	var new_pos  = attacker_position + offset
	# Snap to grid
	var tile     = player.tile_size if "tile_size" in player else 16
	new_pos      = Vector2(round(new_pos.x / tile) * tile, round(new_pos.y / tile) * tile)
	player.global_position = new_pos
	player.grid_pos        = new_pos
	player.target_pos      = new_pos
	_show_teleport_visual(player)
	print("[ABILITY] Substitution triggered — teleported near attacker")
	return true

func _show_primed_visual(player: Node) -> void:
	var tween = player.get_tree().create_tween().set_loops(6)
	tween.tween_property(player, "modulate", Color(1.0, 0.9, 0.0, 0.6), 0.15)
	tween.tween_property(player, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)

func _show_teleport_visual(player: Node) -> void:
	var flash = ColorRect.new()
	flash.color    = Color(1.0, 0.9, 0.0, 0.8)
	flash.size     = Vector2(32, 32)
	flash.position = player.global_position - Vector2(16, 16)
	flash.z_index  = 10
	player.get_parent().add_child(flash)
	var tween = player.get_tree().create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.25)
	tween.tween_callback(flash.queue_free)
