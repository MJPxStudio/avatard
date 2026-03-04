extends Node2D

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	Arena.build(self, true)
	# Set world_node immediately so remote spawning works
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.world_node = self
	# Hide player until logged in
	$Player.visible = false
	$Player.set_physics_process(false)
	# Remove local wolf - server owns all enemy simulation
	if has_node("Wolf"):
		$Wolf.queue_free()
	# Show login screen
	_setup_login_screen()

func _setup_login_screen() -> void:
	var login_scene = load("res://scenes/login_screen.tscn")
	var login = login_scene.instantiate()
	add_child(login)

func on_player_logged_in(player_data: Dictionary) -> void:
	# Apply saved player data
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

	# Restore position
	var saved_pos = player_data.get("position", Vector2.ZERO)
	player.global_position = saved_pos if saved_pos != Vector2.ZERO else Vector2.ZERO
	player.grid_pos = player.global_position
	player.target_pos = player.global_position

	# Show player and enable input
	player.visible = true
	player.set_physics_process(true)

	# Let player connect to network signals directly
	player.connect_network_signals()

	# Tell server our actual starting position
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.send_step.rpc_id(1, Vector2.ZERO)

	# Setup UI
	_setup_hud()
	_setup_inventory()
	_setup_hotbar()
	_setup_equip_panel()
	_setup_stat_panel()

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
