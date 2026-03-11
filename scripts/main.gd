extends Node2D

# ============================================================
# MAIN — Persistent root scene
# Owns the player, all UI, and the current world zone.
# Zone transitions swap _world_node only, UI never reloads.
# ============================================================

const DungeonData = preload("res://scripts/dungeon_data.gd")

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
	print("[MAIN] on_player_logged_in called")
	print("[MAIN] player_data keys: %s" % str(player_data.keys()))
	print("[MAIN] saved zone: %s" % str(player_data.get("zone", "MISSING")))
	print("[MAIN] saved pos: %s" % str(player_data.get("position", "MISSING")))
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
	_setup_ability_menu(hotbar_loadout)
	_setup_equip_panel()
	_restore_equipped(player_data.get("equipped", {}))
	_setup_ability_menu(hotbar_loadout)
	_setup_dungeon_hud()
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
			print("[MAIN] Saved pos %s is outside village bounds — using center spawn" % str(saved_pos))
			saved_pos = Vector2(40.0, 40.0)
	print("[MAIN] Resolved scene_path: %s" % scene_path)
	print("[MAIN] spawn_pos: %s" % str(saved_pos))
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
	print("[MAIN] Loading zone: %s" % scene_path)
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
	)

func transition_to_dungeon(dungeon_id: String, zone_name: String, spawn: Vector2) -> void:
	# Same as transition_to_zone but uses dungeon scene path from DungeonData
	var def = DungeonData.get_dungeon(dungeon_id)
	if def.is_empty():
		push_error("[MAIN] transition_to_dungeon: unknown dungeon id: " + dungeon_id)
		return
	var scene_path = def["scene"]
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
	var tween = get_tree().create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 0), 0.4)
	tween.tween_callback(func():
		if fade and is_instance_valid(fade) and fade.get_parent():
			fade.get_parent().queue_free()
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
	print("[MAIN] load_zone() called with: %s spawn=%s" % [scene_path, str(spawn)])
	var gs = get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.clear_world()
	if _world_node != null:
		_world_node.queue_free()
		_world_node = null
	print("[MAIN] load_zone: calling ResourceLoader.load...")
	var world_scene = load(scene_path)
	print("[MAIN] load_zone: world_scene = %s" % str(world_scene))
	if world_scene == null:
		push_error("[MAIN] FAILED to load zone scene: %s" % scene_path)
		return
	_world_node = world_scene.instantiate()
	print("[MAIN] load_zone: instantiated world node: %s" % str(_world_node))
	add_child(_world_node)
	print("[MAIN] load_zone: world node added to scene tree")
	var player = $Player
	player.global_position = spawn
	player.grid_pos        = spawn
	player.target_pos      = spawn
	player.is_stepping     = false
	player.velocity        = Vector2.ZERO
	player._play_idle()
	print("[MAIN] load_zone: player position set to %s" % str(spawn))
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		var zone_name = scene_path.get_file().get_basename()
		print("[MAIN] load_zone: sending zone_and_position zone=%s pos=%s" % [zone_name, spawn])
		net.send_zone_and_position.rpc_id(1, zone_name, spawn)
	else:
		print("[MAIN] load_zone: WARNING — not connected to network, skipping zone change RPC")
	if gs:
		gs.world_node   = _world_node
		gs.current_zone = _world_node.get_meta("zone_name", "village") if _world_node.has_meta("zone_name") else _world_node.name.to_lower()
		print("[MAIN] load_zone: gs.current_zone = %s" % gs.current_zone)
	var fade = _get_fade()
	print("[MAIN] load_zone: starting fade-in from black")
	var tween = get_tree().create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 0), 0.4)
	tween.tween_callback(func():
		print("[MAIN] load_zone: fade complete, world is visible")
		if fade and is_instance_valid(fade) and fade.get_parent():
			fade.get_parent().queue_free()
	)

func _get_fade() -> ColorRect:
	print("[MAIN] _get_fade() called")
	var layer = get_node_or_null("FadeLayer")
	if layer:
		print("[MAIN] _get_fade: reusing existing FadeLayer")
		return layer.get_node("FadeRect")
	# Create a CanvasLayer so the overlay is always screen-space
	var cl           = CanvasLayer.new()
	cl.name          = "FadeLayer"
	cl.layer         = 128
	add_child(cl)
	print("[MAIN] _get_fade: created new FadeLayer CanvasLayer")
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
				var qdef = $Player.QuestDB.get_quest(qid)
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
		net.wave_start_received.connect(func(w, t, o): hud.on_wave_start(w, t, o))
		net.dungeon_complete_received.connect(func(): hud.on_dungeon_complete())
		net.dungeon_failed_received.connect(func(): hud.on_dungeon_failed())
		net.boss_phase_received.connect(func(n, ph, m): hud.on_boss_phase(n, ph, m))
		net.boss_hp_received.connect(func(hp, mhp): hud.update_boss_hp(hp, mhp))

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
