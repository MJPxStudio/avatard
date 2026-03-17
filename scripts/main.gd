extends Node2D

# ============================================================
# MAIN — Persistent root scene
# Owns the player, all UI, and the current world zone.
# Zone transitions swap _world_node only, UI never reloads.
# ============================================================

const DungeonData = preload("res://scripts/dungeon_data.gd")
const QuestDB     = preload("res://scripts/quest_db.gd")

var _world_node: Node = null

func _ready() -> void:
	# Dedicated server check
	if OS.has_feature("dedicated_server"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/server_main.tscn")
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	$Player.visible = false
	$Player.set_physics_process(false)
	_setup_login_screen()

func _setup_login_screen() -> void:
	var login = load("res://scenes/login_screen.tscn").instantiate()
	add_child(login)

func on_player_logged_in(player_data: Dictionary) -> void:
	var player = $Player
	player.username     = player_data.get("username", "")
	player.stat_hp       = player_data.get("stat_hp", 5)
	player.stat_chakra   = player_data.get("stat_chakra", 5)
	player.stat_strength = player_data.get("stat_str", 5)
	player.stat_dex      = player_data.get("stat_dex", 5)
	player.stat_int      = player_data.get("stat_int", 5)
	player.stat_points   = player_data.get("stat_points", 0)
	player.quest_state   = player_data.get("quest_state", {})
	player.clan               = player_data.get("clan", "")
	player.element            = player_data.get("element", "")
	player.element2           = player_data.get("element2", "")
	player.unlocked_abilities = player_data.get("unlocked_abilities", [])
	var hotbar_loadout = player_data.get("hotbar_loadout", [])
	player.level         = player_data.get("level", 1)
	player.current_exp   = player_data.get("exp", 0)
	player.current_hp    = player_data.get("hp", -1)  # -1 means full — resolved after apply_stats
	# max_exp must match server formula: 100 * 1.5^(level-1)
	var _me = 100
	for _i in range(player.level - 1):
		_me = int(_me * 1.5)
	player.max_exp = _me
	player.kills         = player_data.get("kills", 0)
	player.deaths        = player_data.get("deaths", 0)
	# Apply clan passive after stats are set so bonuses stack correctly
	player.apply_clan_passive()
	player.apply_stats({
		"hp":       player.stat_hp,
		"chakra":   player.stat_chakra,
		"strength": player.stat_strength,
		"dex":      player.stat_dex,
		"int":      player.stat_int
	})
	player.visible    = true
	player.set_physics_process(true)
	player.connect_network_signals()
	# Load saved appearance (hair)
	var saved_appearance = player_data.get("appearance", {})
	if saved_appearance.has("hair_folder"):
		var folder: String = saved_appearance["hair_folder"]
		# Extract style name from folder path e.g. ".../Hairs/Hair1/" → "Hair1"
		var parts = folder.rstrip("/").split("/")
		if parts.size() > 0:
			player.set_hair_style(parts[-1])
	if saved_appearance.has("hair_color"):
		var hc = saved_appearance["hair_color"]
		if hc is Array and hc.size() == 4:
			hc = Color(hc[0], hc[1], hc[2], hc[3])
		if hc is Color:
			player.set_hair_color(hc)
	# Send appearance to server so other players see it immediately
	call_deferred("_send_initial_appearance", player)

	# NOTE: send_position is called inside load_zone after player is positioned.
	# Do NOT send position here — player.global_position is still (0,0) at this point.

	_setup_hud()
	_setup_inventory()
	_setup_hotbar()
	_setup_equip_panel()
	_restore_equipped(player_data.get("equipped", {}))
	_setup_ability_menu(hotbar_loadout)
	_setup_dungeon_hud()
	_setup_dungeon_ready_ui()
	_setup_dungeon_boon_ui()
	_setup_dungeon_boon_status_ui()
	_setup_dungeon_ghost()
	_setup_mission_board()
	_setup_objective_hud()
	_setup_cast_bar()
	_connect_intro_signals()
	_setup_char_info()
	_setup_target_hud()
	_setup_chat()
	_setup_minimap()
	_setup_party_hud()
	_setup_party_invite_popup()
	_setup_damage_numbers()

	var saved_pos  = player_data.get("position", Vector2.ZERO)
	var saved_zone = player_data.get("zone", "village")
	var scene_map  = {
		"village":    "res://scenes/village.tscn",
		"open_world": "res://scenes/open_world.tscn",
	}
	var scene_path = scene_map.get(saved_zone, "res://scenes/village.tscn")
	# Village is drawn centered at origin — valid range is roughly x:±1000, y:±700
	# If saved position is outside this, use safe center spawn instead
	if saved_zone == "village":
		if abs(saved_pos.x) > 950 or abs(saved_pos.y) > 650:
			saved_pos = Vector2(40.0, 40.0)
	load_zone(scene_path, saved_pos)

func transition_to_zone(scene_path: String, spawn: Vector2 = Vector2.ZERO) -> void:
	$Player.set_physics_process(false)
	var fade = _get_fade()
	var tween = get_tree().create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.35)
	tween.tween_callback(func(): _do_load_zone(scene_path, spawn, fade))

func _do_load_zone(scene_path: String, spawn: Vector2, fade: ColorRect) -> void:
	if $Player.dungeon_hud:
		$Player.dungeon_hud.hide_dungeon()
		var status_ui = $Player.get_meta("dungeon_boon_status_ui", null)
		if status_ui and is_instance_valid(status_ui):
			status_ui.reset_for_new_run()
		# Reset boon properties to defaults for next run
		$Player._on_dungeon_boon_props({})
	print("[MAIN] Loading zone: %s" % scene_path)
	# Reset camera limits — dungeon clamps them to room bounds and they persist otherwise
	var cam = $Player.get_node_or_null("Camera2D")
	if cam:
		cam.limit_left   = -10000000
		cam.limit_right  =  10000000
		cam.limit_top    = -10000000
		cam.limit_bottom =  10000000
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.clear_world()
	# Drop target on zone transition — target may not exist in new zone
	if $Player.has_method("_set_target"):
		$Player._set_target(null)
	if _world_node != null:
		_world_node.queue_free()
		_world_node = null
	var world_scene = load(scene_path)
	if world_scene == null:
		push_error("[MAIN] Failed to load zone: %s" % scene_path)
		$Player.set_physics_process(true)
		return
	_world_node = world_scene.instantiate()
	add_child(_world_node)
	var player = $Player
	player.global_position = spawn
	player.grid_pos        = spawn
	player.target_pos      = spawn
	player.is_stepping     = false
	player.velocity        = Vector2.ZERO
	player._play_idle()
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		var zone_name = scene_path.get_file().get_basename()
		print("[MAIN] Sending zone_and_position: zone=%s pos=%s" % [zone_name, spawn])
		net.send_zone_and_position.rpc_id(1, zone_name, spawn)
	if gs:
		gs.world_node   = _world_node
		gs.current_zone = _world_node.get_meta("zone_name", "village") if _world_node.has_meta("zone_name") else _world_node.name.to_lower()
	await get_tree().process_frame
	var tween = get_tree().create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 0), 0.4)
	tween.tween_callback(func():
		if fade and is_instance_valid(fade) and fade.get_parent():
			fade.get_parent().queue_free()  # free the CanvasLayer
		$Player.set_physics_process(true)
		_try_trigger_intro()
	)

func transition_to_dungeon(dungeon_id: String, zone_name: String, spawn: Vector2) -> void:
	# Close ready check UI if still open
	if _dungeon_ready_ui:
		_dungeon_ready_ui.close()
	# Same as transition_to_zone but uses dungeon scene path from DungeonData
	var def = DungeonData.get_dungeon(dungeon_id)
	if def.is_empty():
		push_error("[MAIN] transition_to_dungeon: unknown dungeon id: " + dungeon_id)
		return
	# Set current_zone immediately so enemy sync packets during the fade don't cause mismatch
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.current_zone = zone_name
	var scene_path = def.get("scene", def.get("exit_scene", "res://scenes/village.tscn"))
	$Player.set_physics_process(false)
	var fade  = _get_fade()
	var tween = get_tree().create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 1), 0.35)
	tween.tween_callback(func(): _do_load_dungeon(scene_path, zone_name, spawn, fade))

func _do_load_dungeon(scene_path: String, zone_name: String, spawn: Vector2, fade: ColorRect) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.clear_world()
	if $Player.has_method("_set_target"):
		$Player._set_target(null)
	if _world_node != null:
		_world_node.queue_free()
		_world_node = null
	var world_scene = load(scene_path)
	if world_scene == null:
		push_error("[MAIN] Failed to load dungeon scene: %s" % scene_path)
		$Player.set_physics_process(true)
		return
	_world_node = world_scene.instantiate()
	_world_node.set_meta("zone_name", zone_name)
	add_child(_world_node)
	if $Player.dungeon_hud:
		$Player.dungeon_hud.show_dungeon()
	var player = $Player
	player.global_position = spawn
	player.grid_pos        = spawn
	player.target_pos      = spawn
	player.is_stepping     = false
	player.velocity        = Vector2.ZERO
	player._play_idle()
	if gs:
		gs.world_node   = _world_node
		gs.current_zone = zone_name
	await get_tree().process_frame
	# Upgrade the plain black fade into a styled loading screen
	# It will stay up until dungeon_floor_start fires (server is ready)
	_show_dungeon_loading_screen(fade, zone_name)

var _dungeon_loading_screen: CanvasLayer = null

func _show_dungeon_loading_screen(fade: ColorRect, zone_name: String) -> void:
	var cl = CanvasLayer.new()
	cl.layer = 90
	get_tree().root.add_child(cl)
	_dungeon_loading_screen = cl

	# Full-screen root control
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(root)

	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# Centred container — anchor to centre, offset from there
	var centre = Control.new()
	centre.set_anchor(SIDE_LEFT,   0.5)
	centre.set_anchor(SIDE_RIGHT,  0.5)
	centre.set_anchor(SIDE_TOP,    0.5)
	centre.set_anchor(SIDE_BOTTOM, 0.5)
	centre.set_offset(SIDE_LEFT,   -150.0)
	centre.set_offset(SIDE_RIGHT,   150.0)
	centre.set_offset(SIDE_TOP,    -160.0)
	centre.set_offset(SIDE_BOTTOM,  160.0)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)

	# Wolf den icon
	var icon_tex = load("res://sprites/dungeon/wolf_den_icon.png")
	var icon = TextureRect.new()
	icon.texture         = icon_tex
	icon.expand_mode     = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode    = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchor(SIDE_LEFT,   0.5)
	icon.set_anchor(SIDE_RIGHT,  0.5)
	icon.set_anchor(SIDE_TOP,    0.0)
	icon.set_anchor(SIDE_BOTTOM, 0.0)
	icon.set_offset(SIDE_LEFT,  -64.0)
	icon.set_offset(SIDE_RIGHT,  64.0)
	icon.set_offset(SIDE_TOP,     0.0)
	icon.set_offset(SIDE_BOTTOM, 128.0)
	centre.add_child(icon)

	# Dungeon name
	var name_lbl = Label.new()
	name_lbl.text = zone_name.replace("_", " ").to_upper()
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	name_lbl.add_theme_constant_override("shadow_offset_x", 2)
	name_lbl.add_theme_constant_override("shadow_offset_y", 2)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_lbl.set_offset(SIDE_TOP,    135.0)
	name_lbl.set_offset(SIDE_BOTTOM, 170.0)
	centre.add_child(name_lbl)

	# Status label
	var sub_lbl = Label.new()
	sub_lbl.name = "SubLabel"
	sub_lbl.text = "Entering dungeon..."
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub_lbl.set_offset(SIDE_TOP,    175.0)
	sub_lbl.set_offset(SIDE_BOTTOM, 200.0)
	centre.add_child(sub_lbl)

	# Dot animation via Timer
	var dot_count = 0
	var timer = Timer.new()
	timer.wait_time = 0.45
	timer.autostart = true
	centre.add_child(timer)
	timer.timeout.connect(func() -> void:
		var lbl = centre.get_node_or_null("SubLabel")
		if lbl and is_instance_valid(lbl):
			dot_count = (dot_count + 1) % 4
			lbl.text = "Entering dungeon" + ".".repeat(dot_count)
	)

	# Free the old plain fade rect
	if fade and is_instance_valid(fade) and fade.get_parent():
		fade.get_parent().queue_free()

	$Player.set_physics_process(false)

func _dismiss_dungeon_loading_screen() -> void:
	if _dungeon_loading_screen == null or not is_instance_valid(_dungeon_loading_screen):
		$Player.set_physics_process(true)
		return
	var cl = _dungeon_loading_screen
	_dungeon_loading_screen = null
	var tween = get_tree().create_tween()
	# Fade out the whole canvas layer by fading its children
	for child in cl.get_children():
		if child is Control:
			tween.parallel().tween_property(child, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		if is_instance_valid(cl):
			cl.queue_free()
		$Player.set_physics_process(true)
	)

func _restore_equipped(equipped: Dictionary) -> void:
	if equipped.is_empty():
		return
	var equip = $Player.equip_panel
	var inv   = $Player.inventory
	if equip == null:
		return
	for slot_key in equipped:
		var item = equipped[slot_key]
		if item is Dictionary and item.get("sprite_folder", "") != "":
			var idx = equip.get_slot_for_item(item)
			if idx >= 0:
				equip.equip(idx, item)
				# Remove the matching item from inventory so it isn't duplicated
				if inv != null:
					for i in range(inv.slots.size()):
						var inv_item = inv.slots[i]
						if inv_item != null and inv_item.get("id", "") == item.get("id", ""):
							inv.slots[i] = null
							inv.refresh_slot(i)
							break

func _send_initial_appearance(player: Node) -> void:
	if player.has_method("_send_appearance_to_server"):
		player._send_appearance_to_server()

func load_zone(scene_path: String, spawn: Vector2 = Vector2.ZERO) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.clear_world()
	if _world_node != null:
		_world_node.queue_free()
		_world_node = null
	var world_scene = load(scene_path)
	if world_scene == null:
		push_error("[MAIN] FAILED to load zone scene: %s" % scene_path)
		return
	_world_node = world_scene.instantiate()
	add_child(_world_node)
	var player = $Player
	player.global_position = spawn
	player.grid_pos        = spawn
	player.target_pos      = spawn
	player.is_stepping     = false
	player.velocity        = Vector2.ZERO
	player._play_idle()
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		var zone_name = scene_path.get_file().get_basename()
		net.send_zone_and_position.rpc_id(1, zone_name, spawn)
	else:
		pass
	if gs:
		gs.world_node   = _world_node
		gs.current_zone = _world_node.get_meta("zone_name", "village") if _world_node.has_meta("zone_name") else _world_node.name.to_lower()
	var fade = _get_fade()
	var tween = get_tree().create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 0), 0.4)
	tween.tween_callback(func():
		if fade and is_instance_valid(fade) and fade.get_parent():
			fade.get_parent().queue_free()
		$Player.set_physics_process(true)
		_try_trigger_intro()
	)

func _get_fade() -> ColorRect:
	var layer = get_node_or_null("FadeLayer")
	if layer:
		return layer.get_node("FadeRect")
	# Create a CanvasLayer so the overlay is always screen-space
	var cl           = CanvasLayer.new()
	cl.name          = "FadeLayer"
	cl.layer         = 128
	add_child(cl)
	var fade              = ColorRect.new()
	fade.name             = "FadeRect"
	fade.color            = Color(0, 0, 0, 1)
	fade.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(fade)
	return fade

func _setup_hud() -> void:
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child(hud)
	$Player.hud = hud
	$Player._update_hud()
	# Wire quest_hud now that HUD exists
	var qhud = hud.get_node_or_null("QuestHUD")
	if qhud:
		$Player.quest_hud = qhud
		# Restore active quest display from saved state
		for qid in $Player.quest_state:
			var qs = $Player.quest_state[qid]
			if qs.get("status") == "active":
				var qdef = QuestDB.get_quest(qid)
				if not qdef.is_empty():
					var prog = qs.get("progress", 0)
					var req  = qdef.get("required", 1)
					qhud.show_quest(qid, prog, req)
					if prog >= req:
						qhud.mark_complete()
					break  # show the first active quest only

func _setup_inventory() -> void:
	var inventory = load("res://scenes/inventory.tscn").instantiate()
	add_child(inventory)
	$Player.inventory = inventory

func _setup_hotbar() -> void:
	var hotbar = load("res://scenes/hotbar.tscn").instantiate()
	add_child(hotbar)
	$Player.hotbar = hotbar
	hotbar.set_player($Player)
	# Ability loadout restored by _setup_ability_menu from saved hotbar_loadout

func _setup_ability_menu(loadout: Array = []) -> void:
	var menu = CanvasLayer.new()
	menu.set_script(load("res://scripts/ability_menu.gd"))
	add_child(menu)
	$Player.ability_menu = menu
	menu.set_player($Player)
	if not loadout.is_empty():
		menu.restore_loadout(loadout)

func _setup_dungeon_hud() -> void:
	var hud = load("res://scripts/dungeon_hud.gd").new()
	add_child(hud)
	$Player.dungeon_hud = hud
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		# Use dynamic lookup instead of capturing `hud` — guards against stale refs
		# if this ever fires after the hud is freed or replaced
		if not net.wave_start_received.is_connected(_on_wave_start_for_hud):
			net.wave_start_received.connect(_on_wave_start_for_hud)
		if not net.dungeon_complete_received.is_connected(_on_dungeon_complete_for_hud):
			net.dungeon_complete_received.connect(_on_dungeon_complete_for_hud)
		if not net.dungeon_failed_received.is_connected(_on_dungeon_failed_for_hud):
			net.dungeon_failed_received.connect(_on_dungeon_failed_for_hud)
		if not net.boss_phase_received.is_connected(_on_boss_phase_for_hud):
			net.boss_phase_received.connect(_on_boss_phase_for_hud)
		if not net.boss_hp_received.is_connected(_on_boss_hp_for_hud):
			net.boss_hp_received.connect(_on_boss_hp_for_hud)
		if not net.dungeon_floor_start_received.is_connected(_on_floor_start_for_hud):
			net.dungeon_floor_start_received.connect(_on_floor_start_for_hud)
		if not net.dungeon_room_cleared_received.is_connected(_on_room_cleared_for_hud):
			net.dungeon_room_cleared_received.connect(_on_room_cleared_for_hud)

func _on_wave_start_for_hud(w: int, t: int, o: String) -> void:
	var hud = $Player.dungeon_hud if $Player else null
	if hud and is_instance_valid(hud):
		hud.on_wave_start(w, t, o)

func _on_dungeon_complete_for_hud() -> void:
	var hud = $Player.dungeon_hud if $Player else null
	if hud and is_instance_valid(hud):
		hud.on_dungeon_complete()

func _on_dungeon_failed_for_hud() -> void:
	var hud = $Player.dungeon_hud if $Player else null
	if hud and is_instance_valid(hud):
		hud.on_dungeon_failed()

func _on_boss_phase_for_hud(n: String, ph: int, m: String) -> void:
	var hud = $Player.dungeon_hud if $Player else null
	if hud and is_instance_valid(hud):
		hud.on_boss_phase(n, ph, m)

func _on_boss_hp_for_hud(hp: int, mhp: int) -> void:
	var hud = $Player.dungeon_hud if $Player else null
	if hud and is_instance_valid(hud):
		hud.update_boss_hp(hp, mhp)

func _on_floor_start_for_hud(floor_num: int, total_floors: int, _room_count: int, difficulty: String = "easy") -> void:
	# Dismiss the dungeon loading screen now that the server is ready
	_dismiss_dungeon_loading_screen()
	var hud = $Player.dungeon_hud if $Player else null
	if hud and is_instance_valid(hud):
		var gs = get_tree().root.get_node_or_null("GameState")
		var dungeon_name = ""
		if gs:
			var DungeonData = load("res://scripts/dungeon_data.gd")
			for did in DungeonData.DUNGEONS:
				var base = DungeonData.DUNGEONS[did]["zone_name"]
				if gs.current_zone == base or gs.current_zone.begins_with(base + "_"):
					dungeon_name = DungeonData.DUNGEONS[did]["display_name"]
					break
		hud.on_floor_start(floor_num, total_floors, dungeon_name, difficulty)

func _on_room_cleared_for_hud(_room_id: int, _connections: Array, _door_rewards: Dictionary = {}) -> void:
	var hud = $Player.dungeon_hud if $Player else null
	if hud and is_instance_valid(hud):
		hud.on_room_cleared()

var _dungeon_ready_ui:  Node = null
var _mission_board:     Node = null
var _cast_bar:          Node = null
var _objective_hud:     Node = null
var _intro_pending:     bool = false

func _on_intro_needed(_needed: bool) -> void:
	pass  # Intro is now triggered client-side in _try_trigger_intro

func _try_trigger_intro() -> void:
	# Only trigger once — if already triggered this session, skip
	if _intro_pending:
		return
	var player = $Player
	var qs = player.quest_state if player else {}
	# Only trigger if no intro quest has started yet and clan is set
	var intro_done = qs.has("q_meet_the_jonin") or qs.has("q_basic_training") \
		or qs.has("q_enroll_academy") or qs.has("q_report_to_missions")
	if intro_done or not player or player.clan == "":
		return
	var escort = _world_node.get_node_or_null("EscortNPC") if _world_node else null
	if escort and escort.has_method("begin_escort") and not escort.get("_active"):
		_intro_pending = true   # reuse flag to prevent re-triggering
		escort.begin_escort(player)

func _connect_intro_signals() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.intro_needed.connect(_on_intro_needed)
		pass  # objective_hud handles notify_quest_accepted_received directly

func _setup_cast_bar() -> void:
	_cast_bar = load("res://scripts/cast_bar.gd").new()
	add_child(_cast_bar)
	# Pass to hotbar so it can trigger casts
	if $Player.hotbar:
		$Player.hotbar.cast_bar = _cast_bar
	# Also cancel cast on knockback
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.pull_received.connect(func(_pos): _cast_bar.cancel())

func _setup_objective_hud() -> void:
	_objective_hud = load("res://scripts/objective_hud.gd").new()
	add_child(_objective_hud)
	$Player.set_meta("objective_hud", _objective_hud)

func _setup_mission_board() -> void:
	_mission_board = load("res://scripts/mission_board_ui.gd").new()
	add_child(_mission_board)
	$Player.set_meta("mission_board", _mission_board)

func _setup_dungeon_ready_ui() -> void:
	_dungeon_ready_ui = load("res://scripts/dungeon_ready_ui.gd").new()
	add_child(_dungeon_ready_ui)
	$Player.set_meta("dungeon_ready_ui", _dungeon_ready_ui)

func _setup_dungeon_boon_ui() -> void:
	var boon_ui = load("res://scripts/dungeon_boon_ui.gd").new()
	add_child(boon_ui)
	$Player.set_meta("dungeon_boon_ui", boon_ui)

func _setup_dungeon_boon_status_ui() -> void:
	var status_ui = load("res://scripts/dungeon_boon_status_ui.gd").new()
	add_child(status_ui)
	$Player.set_meta("dungeon_boon_status_ui", status_ui)

var _dungeon_ghost: Node = null

func _setup_dungeon_ghost() -> void:
	_dungeon_ghost = load("res://scripts/dungeon_ghost.gd").new()
	add_child(_dungeon_ghost)
	$Player.set_meta("dungeon_ghost", _dungeon_ghost)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.player_became_ghost_received.connect(_on_player_became_ghost)
		net.dungeon_wiped_received.connect(_on_dungeon_wiped)

func _on_player_became_ghost(pid: int) -> void:
	if pid != multiplayer.get_unique_id():
		return
	var gs = get_tree().root.get_node_or_null("GameState")
	var living: Array = []
	if gs:
		for rpid in gs.remote_player_nodes:
			living.append(rpid)
	if _dungeon_ghost:
		_dungeon_ghost.activate(living)

func _on_dungeon_wiped(exit_scene: String, exit_pos: Vector2) -> void:
	if _dungeon_ghost:
		_dungeon_ghost.deactivate()
	transition_to_zone(exit_scene, exit_pos)

func _setup_equip_panel() -> void:
	var equip = load("res://scenes/equip_panel.tscn").instantiate()
	add_child(equip)
	$Player.equip_panel = equip
	equip.set_player($Player)
	if $Player.inventory:
		$Player.inventory.equip_panel_ref = equip

func _restore_hotbar_loadout(loadout: Array) -> void:
	var player = $Player
	if player.hotbar == null or loadout.is_empty():
		return
	for i in range(min(loadout.size(), player.hotbar.slots.size())):
		var ab_id = loadout[i]
		if ab_id == "" or ab_id == null:
			continue
		var ability = AbilityDB.create_instance(ab_id)
		if ability:
			player.hotbar.slots[i] = ability
			player.hotbar._refresh_slot(i)
	player.hotbar.loadout_changed.connect(_save_hotbar_loadout)

func _save_hotbar_loadout() -> void:
	var player = $Player
	if player.hotbar == null:
		return
	var loadout: Array = []
	for slot in player.hotbar.slots:
		if slot is AbilityBase and slot.ability_id != "":
			loadout.append(slot.ability_id)
		else:
			loadout.append("")
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.send_hotbar_loadout(loadout)

func _setup_char_info() -> void:
	var ci = load("res://scenes/stat_panel.tscn").instantiate()
	ci.set_script(load("res://scripts/char_info.gd"))
	add_child(ci)
	$Player.char_info = ci
	$Player.stat_panel = ci  # keep compat alias
	ci.set_player($Player)

func _setup_damage_numbers() -> void:
	var dn = Node.new()
	dn.set_script(load("res://scripts/damage_numbers.gd"))
	dn.name = "DamageNumbers"
	add_child(dn)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# Window regained focus — release chat focus so player isn't
		# typing into chat immediately after alt-tabbing back
		var player = get_node_or_null("Player")
		if player and player.chat and player.chat.is_open():
			player.chat._set_open(false)
		get_viewport().gui_release_focus()

func _setup_party_hud() -> void:
	var ph = CanvasLayer.new()
	ph.set_script(load("res://scripts/party_hud.gd"))
	add_child(ph)
	$Player.party_hud = ph

func _setup_party_invite_popup() -> void:
	var popup = CanvasLayer.new()
	popup.set_script(load("res://scripts/party_invite_popup.gd"))
	add_child(popup)
	$Player.party_invite_popup = popup
	popup.responded.connect(func(inviter_name: String, accepted: bool):
		var net = get_tree().root.get_node_or_null("Network")
		if net and net.is_network_connected():
			net.send_party_response.rpc_id(1, inviter_name, accepted)
	)

func _setup_minimap() -> void:
	var mm = CanvasLayer.new()
	mm.set_script(load("res://scripts/minimap.gd"))
	add_child(mm)
	$Player.minimap = mm

func _setup_chat() -> void:
	var chat = CanvasLayer.new()
	chat.set_script(load("res://scripts/chat.gd"))
	add_child(chat)
	$Player.chat = chat
	chat.chat_submitted.connect(func(channel, target, text):
		var net = get_tree().root.get_node_or_null("Network")
		if net and net.is_network_connected():
			net.send_chat.rpc_id(1, channel, target, text)
		# Show bubble immediately on local player — don't wait for server echo
		if channel in ["zone", "global"]:
			var lp = get_node_or_null("Player")
			if lp and lp.has_method("show_chat_bubble"):
				lp.show_chat_bubble(text)
	)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.chat_received_client.connect(func(channel, sender, text):
			match channel:
				"global":      chat.add_global_message(sender, text)
				"whisper":     chat.add_whisper_message(sender, text, false)
				"whisper_out": chat.add_whisper_message(sender, text, true)
				"system":      chat.add_system_message(text)
				"kill":        chat.add_kill_message(sender, text)
				"party":       chat.add_party_message(sender, text)
				_:
					chat.add_zone_message(sender, text)
					# Show speech bubble above the speaking player's head
					_show_chat_bubble_for(sender, text)
		)

func _show_chat_bubble_for(sender: String, text: String) -> void:
	var gs = get_tree().root.get_node_or_null("GameState")
	# Local player's bubble is shown immediately on chat_submitted — skip here
	if gs and sender == gs.my_username:
		return
	# Remote player — find by username in the node registry
	if gs:
		for rp in gs.remote_player_nodes.values():
			if is_instance_valid(rp) and "username" in rp and rp.username == sender:
				if rp.has_method("show_chat_bubble"):
					rp.show_chat_bubble(text)
				return

func _setup_target_hud() -> void:
	var hud = CanvasLayer.new()
	hud.set_script(load("res://scripts/target_hud.gd"))
	add_child(hud)
	$Player.target_hud = hud
