extends Node2D

# ============================================================
# MAIN — Persistent root scene
# Owns the player, all UI, and the current world zone.
# Zone transitions swap _world_node only, UI never reloads.
# ============================================================

var _world_node: Node = null

func _ready() -> void:
	# Dedicated server check
	if OS.has_feature("dedicated_server"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/server_main.tscn")
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	$Player.visible = false
	$Player.set_physics_process(false)
	_setup_login_screen()

func _setup_login_screen() -> void:
	var login = load("res://scenes/login_screen.tscn").instantiate()
	add_child(login)

# Called by login_screen.gd after successful login
func on_player_logged_in(player_data: Dictionary) -> void:
	var player = $Player
	player.stat_hp       = player_data.get("stat_hp", 5)
	player.stat_chakra   = player_data.get("stat_chakra", 5)
	player.stat_strength = player_data.get("stat_str", 5)
	player.stat_dex      = player_data.get("stat_dex", 5)
	player.stat_int      = player_data.get("stat_int", 5)
	player.stat_points   = player_data.get("stat_points", 0)
	player.level         = player_data.get("level", 1)
	player.current_exp   = player_data.get("exp", 0)
	player.apply_stats({
		"hp":       player.stat_hp,
		"chakra":   player.stat_chakra,
		"strength": player.stat_strength,
		"dex":      player.stat_dex,
		"int":      player.stat_int
	})
	var saved_pos = player_data.get("position", Vector2.ZERO)
	player.global_position = saved_pos if saved_pos != Vector2.ZERO else Vector2.ZERO
	player.grid_pos   = player.global_position
	player.target_pos = player.global_position
	player.visible    = true
	player.set_physics_process(true)
	player.connect_network_signals()

	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.send_step.rpc_id(1, Vector2.ZERO)

	_setup_hud()
	_setup_inventory()
	_setup_hotbar()
	_setup_equip_panel()
	_setup_stat_panel()

	# Load starting zone
	load_zone("res://scenes/village.tscn")

# ── Zone loading ─────────────────────────────────────────────

func transition_to_zone(scene_path: String, spawn: Vector2 = Vector2.ZERO) -> void:
	# Fade out
	var fade = _get_fade()
	var tween = get_tree().create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.4)
	tween.tween_callback(func(): load_zone(scene_path, spawn))

func load_zone(scene_path: String, spawn: Vector2 = Vector2.ZERO) -> void:
	print("[MAIN] Loading zone: %s" % scene_path)
	# Clear remote nodes
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.clear_world()
	# Swap world
	if _world_node != null:
		_world_node.queue_free()
		_world_node = null
	var world_scene = load(scene_path)
	if world_scene == null:
		push_error("[MAIN] Failed to load zone: %s" % scene_path)
		return
	_world_node = world_scene.instantiate()
	add_child(_world_node)
	# Apply spawn
	var player = $Player
	if spawn != Vector2.ZERO:
		player.global_position = spawn
		player.grid_pos        = spawn
		player.target_pos      = spawn
	# Update GameState
	if gs:
		gs.world_node = _world_node
	# Fade in
	var fade = _get_fade()
	var tween = get_tree().create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 0), 0.4)
	tween.tween_callback(fade.queue_free)

func _get_fade() -> ColorRect:
	var existing = get_node_or_null("FadeOverlay")
	if existing:
		return existing
	var fade          = ColorRect.new()
	fade.name         = "FadeOverlay"
	fade.color        = Color(0, 0, 0, 0)
	fade.z_index      = 100
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.size         = get_viewport().get_visible_rect().size
	# Position relative to camera
	var camera = get_tree().get_first_node_in_group("camera")
	if camera:
		fade.position = camera.global_position - fade.size / 2.0
	add_child(fade)
	return fade

# ── UI Setup ─────────────────────────────────────────────────

func _setup_hud() -> void:
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child(hud)
	$Player.hud = hud
	$Player._update_hud()

func _setup_inventory() -> void:
	var inventory = load("res://scenes/inventory.tscn").instantiate()
	add_child(inventory)
	$Player.inventory = inventory

func _setup_hotbar() -> void:
	var hotbar = load("res://scenes/hotbar.tscn").instantiate()
	add_child(hotbar)
	$Player.hotbar = hotbar
	hotbar.set_player($Player)
	hotbar.set_ability(0, AbilityMedical.new())
	hotbar.set_ability(1, AbilityFireBurst.new())
	hotbar.set_ability(2, AbilitySubstitution.new())

func _setup_equip_panel() -> void:
	var equip = load("res://scenes/equip_panel.tscn").instantiate()
	add_child(equip)
	$Player.equip_panel = equip

func _setup_stat_panel() -> void:
	var stat = load("res://scenes/stat_panel.tscn").instantiate()
	add_child(stat)
	$Player.stat_panel = stat
	stat.set_player($Player)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
