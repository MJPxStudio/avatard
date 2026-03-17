extends Node

# ============================================================
# DAMAGE NUMBERS — floating damage text at hit position
# Call spawn(position, amount, is_player_hit) from anywhere
# ============================================================

# Per-frame dedup: prevents two numbers for the same hit when both
# confirm_hit and confirm_ability_hit fire in the same frame
# (e.g. player auto-attacks at the same moment an ability projectile lands).
var _frame_hits: Array = []  # [{pos, amount}] cleared each physics frame

func _ready() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.hit_confirmed.connect(_on_hit_confirmed)
		net.ability_hit_confirmed.connect(_on_ability_hit_confirmed)

func _process(_delta: float) -> void:
	_frame_hits.clear()

func _on_ability_hit_confirmed(hit_pos: Vector2, amount: int) -> void:
	if amount > 0:
		spawn(hit_pos, amount, false)

func _on_hit_confirmed(hit_pos: Vector2, amount: int) -> void:
	spawn(hit_pos, amount, false)

func spawn(world_pos: Vector2, amount: int, is_crit: bool = false, color: Color = Color(-1,-1,-1,1)) -> void:
	# Dedup: skip if a number already spawned at this exact position this frame
	for entry: Dictionary in _frame_hits:
		if entry["pos"].distance_squared_to(world_pos) < 16.0:
			return
	_frame_hits.append({"pos": world_pos, "amount": amount})
	var lbl             = Label.new()
	lbl.text            = str(amount)
	lbl.add_theme_font_size_override("font_size", 11 if not is_crit else 15)
	# Use provided color, else default: yellow for crit, orange for normal
	var final_color: Color
	if color.r >= 0:
		final_color = color
	elif is_crit:
		final_color = Color(1.0, 0.9, 0.2, 1.0)
	else:
		final_color = Color(1.0, 0.35, 0.2, 1.0)
	lbl.add_theme_color_override("font_color", final_color)
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
