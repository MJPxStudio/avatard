extends Node

# ============================================================
# DAMAGE NUMBERS — floating damage text at hit position
# Call spawn(position, amount, is_player_hit) from anywhere
# ============================================================

func _ready() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.hit_confirmed.connect(_on_hit_confirmed)
	var local_player = get_tree().get_first_node_in_group("local_player")
	if local_player:
		local_player.connect("tree_exiting", func(): pass)

func _on_hit_confirmed(hit_pos: Vector2, amount: int) -> void:
	spawn(hit_pos, amount, false)

func spawn(world_pos: Vector2, amount: int, is_crit: bool = false) -> void:
	var lbl             = Label.new()
	lbl.text            = str(amount)
	lbl.add_theme_font_size_override("font_size", 11 if not is_crit else 15)
	lbl.add_theme_color_override("font_color",
		Color(1.0, 0.9, 0.2, 1.0) if is_crit else Color(1.0, 0.35, 0.2, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.add_theme_constant_override("shadow_as_outline", 1)
	lbl.z_index         = 50
	lbl.global_position = world_pos + Vector2(randf_range(-8, 8), -12)
	get_tree().current_scene.add_child(lbl)

	# Float up and fade out
	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 24, 0.6)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.55).set_delay(0.15)
	tween.chain().tween_callback(lbl.queue_free)
