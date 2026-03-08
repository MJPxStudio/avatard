extends Node
class_name ParticleBurst

# ============================================================
# PARTICLE BURST — Pure-code CPUParticles2D helper
# Call ParticleBurst.spawn(...) from anywhere.
# Self-destructs after the longest lifetime completes.
# No .tscn, no editor setup required.
# ============================================================

# Presets ─────────────────────────────────────────────────────
#   "hit"          small white/orange impact flash
#   "level_up"     large golden ring explosion
#   "death_player" red dissolve burst
#   "death_enemy"  orange/grey smoke puff
#   "respawn"      soft blue-white shimmer
# ─────────────────────────────────────────────────────────────

static func _make_circle_texture(radius: int) -> ImageTexture:
	var size   = radius * 2
	var img    = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(radius, radius)
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(center)
			if dist <= radius:
				# Soft edge: fade alpha in outer 30%
				var alpha = clampf(1.0 - (dist - radius * 0.7) / (radius * 0.3), 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

static func spawn(scene_tree: SceneTree, pos: Vector2, preset: String) -> void:
	var p = CPUParticles2D.new()
	p.z_index         = 15
	p.emitting        = true
	p.one_shot        = true
	p.explosiveness   = 0.95
	p.texture         = _make_circle_texture(2)  # 4px circle — scaled down at runtime
	p.global_position = pos

	match preset:
		"hit":
			p.amount              = 30
			p.lifetime            = 0.45
			p.direction           = Vector2(0, -1)
			p.spread              = 180.0
			p.initial_velocity_min = 40.0
			p.initial_velocity_max = 90.0
			p.gravity             = Vector2(0, 180)
			p.scale_amount_min    = 0.4
			p.scale_amount_max    = 0.8
			p.color               = Color(1.0, 0.85, 0.3, 1.0)

		"level_up":
			p.amount              = 80
			p.lifetime            = 1.4
			p.direction           = Vector2(0, -1)
			p.spread              = 180.0
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 160.0
			p.gravity             = Vector2(0, 60)
			p.scale_amount_min    = 0.5
			p.scale_amount_max    = 1.0
			p.color               = Color("ffd700")

		"death_player":
			p.amount              = 60
			p.lifetime            = 1.0
			p.direction           = Vector2(0, -1)
			p.spread              = 180.0
			p.initial_velocity_min = 50.0
			p.initial_velocity_max = 130.0
			p.gravity             = Vector2(0, 120)
			p.scale_amount_min    = 0.4
			p.scale_amount_max    = 0.9
			p.color               = Color(0.9, 0.15, 0.15, 1.0)

		"death_enemy":
			p.amount              = 40
			p.lifetime            = 0.7
			p.direction           = Vector2(0, -1)
			p.spread              = 160.0
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 80.0
			p.gravity             = Vector2(0, 100)
			p.scale_amount_min    = 0.3
			p.scale_amount_max    = 0.7
			p.color               = Color(0.95, 0.45, 0.1, 1.0)

		"respawn":
			p.amount              = 50
			p.lifetime            = 1.1
			p.direction           = Vector2(0, -1)
			p.spread              = 180.0
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 90.0
			p.gravity             = Vector2(0, 30)
			p.scale_amount_min    = 0.4
			p.scale_amount_max    = 0.8
			p.color               = Color(0.5, 0.85, 1.0, 1.0)

		"fire_burst":
			# Dense ring of fire radiating outward — doubled particle count for explosion feel
			p.amount               = 180
			p.lifetime             = 0.75
			p.emission_shape       = CPUParticles2D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 18.0
			p.direction            = Vector2(0, 0)
			p.spread               = 180.0
			p.initial_velocity_min = 90.0
			p.initial_velocity_max = 220.0
			p.gravity              = Vector2(0, -30)  # fire rises
			p.scale_amount_min     = 0.8
			p.scale_amount_max     = 2.0
			var grad = Gradient.new()
			grad.set_color(0, Color(1.0, 0.98, 0.6, 1.0))    # hot white-yellow core
			grad.add_point(0.3, Color(1.0, 0.5, 0.05, 1.0))  # orange
			grad.add_point(0.7, Color(0.8, 0.1, 0.0, 0.8))   # deep red
			grad.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))   # dark ember, faded
			p.color_ramp           = grad

		"chakra_charge":
			# Soft blue-white particles spiraling inward toward player
			p.amount               = 50
			p.lifetime             = 0.9
			p.emission_shape       = CPUParticles2D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 40.0
			p.direction            = Vector2(0, -1)
			p.spread               = 180.0
			p.initial_velocity_min = 20.0
			p.initial_velocity_max = 60.0
			p.gravity              = Vector2(0, -30)
			p.scale_amount_min     = 0.3
			p.scale_amount_max     = 0.7
			var grad2 = Gradient.new()
			grad2.set_color(0, Color(0.5, 0.9, 1.0, 1.0))   # light blue
			grad2.add_point(1.0, Color(0.2, 0.4, 1.0, 0.0)) # deep blue, faded
			p.color_ramp           = grad2

	scene_tree.current_scene.add_child(p)

	# Auto-free after particles finish (lifetime + small buffer)
	var timer = scene_tree.create_timer(p.lifetime + 0.2)
	timer.timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)
