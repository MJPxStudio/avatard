extends Node

const ParticleBurst = preload("res://scripts/particle_burst.gd")

# ============================================================
# GAME STATE — Client-side only
# Tracks local player data, remote players, and remote enemies.
# ============================================================

signal login_accepted(player_data)
signal login_denied(reason)
signal players_synced(states)
signal damage_received(amount, knockback_dir)

var my_username:    String     = ""
var my_player_data: Dictionary = {}
var remote_players: Dictionary = {}
var world_node:     Node       = null

var remote_player_nodes: Dictionary = {}
var remote_enemy_nodes:  Dictionary = {}
var _shadow_visuals:     Dictionary = {}   # shadow_id -> ShadowVisual node
var _enemy_static_cache: Dictionary = {}  # static enemy data cached per zone
var _debug_enabled: bool = false  # F1 toggles debug visuals
var current_zone:   String = "village"  # tracked on every zone load
var my_party:       Array  = []          # usernames of current party members (includes self)
var my_party_leader: String = ""          # username of current party leader
var _last_logged_zone: String = ""

func _ready() -> void:
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	Network.login_accepted_client.connect(_on_login_accepted)
	Network.login_denied_client.connect(_on_login_denied)
	Network.players_synced_client.connect(_on_players_synced)
	Network.party_update_received.connect(_on_party_update)
	Network.party_invite_received.connect(_on_party_invite)
	Network.party_msg_received.connect(_on_party_msg)
	Network.damage_received_client.connect(_on_damage_received)
	Network.enemies_synced_client.connect(_on_enemies_synced)
	Network.player_disconnected.connect(_on_player_disconnected)
	Network.enemy_killed_client.connect(_on_enemy_killed)
	Network.enemy_roster_client.connect(_on_enemy_roster)
	Network.enemy_telegraph_received.connect(_on_enemy_telegraph)
	Network.kunai_spawned.connect(_on_kunai_spawned)
	Network.shadow_spawned.connect(_on_shadow_spawned)
	Network.shadow_moved.connect(_on_shadow_moved)
	Network.shadow_despawned.connect(_on_shadow_despawned)
	Network.ability_visual_received.connect(_on_ability_visual)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_debug_enabled = not _debug_enabled
			for re in remote_enemy_nodes.values():
				if is_instance_valid(re) and re.has_method("set_hitbox_visible"):
					re.set_hitbox_visible(_debug_enabled)
			# Also toggle local player attack arc vis
			var lp = get_tree().get_first_node_in_group("local_player")
			if lp and lp.has_method("set_attack_debug"):
				lp.set_attack_debug(_debug_enabled)
	# Right-click on remote player → context menu
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if remote_player_nodes.is_empty():
			return
		var closest_node: Node = null
		var closest_dist: float = 20.0
		for pid in remote_player_nodes:
			var rp = remote_player_nodes[pid]
			if not is_instance_valid(rp):
				continue
			var mouse_world = rp.get_global_mouse_position()
			var dist = rp.global_position.distance_to(mouse_world)
			if dist < closest_dist:
				closest_dist = dist
				closest_node = rp
		if closest_node == null:
			return
		var uname = closest_node.username if "username" in closest_node else ""
		if uname == "" or uname == my_username:
			return
		_ctx_target_username = uname
		get_viewport().set_input_as_handled()
		var screen_pos = DisplayServer.mouse_get_position()
		if _ctx_menu == null:
			_ctx_menu = PopupMenu.new()
			_ctx_menu.id_pressed.connect(_on_ctx_menu_pressed)
			get_tree().root.add_child(_ctx_menu)
		_ctx_menu.clear()
		_ctx_menu.add_item("Invite %s to Party" % uname, 0)
		_ctx_menu.position = screen_pos
		_ctx_menu.popup()

func clear_enemy_cache(zone: String = "") -> void:
	if zone == "":
		_enemy_static_cache.clear()
	else:
		_enemy_static_cache.erase(zone)

func clear_world() -> void:
	for peer_id in remote_player_nodes.keys():
		if is_instance_valid(remote_player_nodes[peer_id]):
			remote_player_nodes[peer_id].queue_free()
	remote_player_nodes.clear()
	for enemy_id in remote_enemy_nodes.keys():
		if is_instance_valid(remote_enemy_nodes[enemy_id]):
			remote_enemy_nodes[enemy_id].queue_free()
	remote_enemy_nodes.clear()
	world_node = null

func _on_login_accepted(player_data: Dictionary) -> void:
	my_username    = player_data.get("username", "").strip_edges()
	my_player_data = player_data
	login_accepted.emit(player_data)

func _on_login_denied(reason: String) -> void:
	login_denied.emit(reason)

func _on_players_synced(states: Dictionary) -> void:
	remote_players = states
	players_synced.emit(states)
	_update_remote_players(states)
	# Update party HUD with latest HP data
	var lp = _get_local_player()
	if lp and lp.party_hud and not my_party.is_empty():
		lp.party_hud.update_hp(states)

func _update_remote_players(states: Dictionary) -> void:
	# Don't guard on world_node — remote players attach to Main, not world_node
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var my_id = Network.get_my_id()
	for peer_id in states:
		if peer_id == my_id:
			# Update local player's own K/D from server broadcast
			var lp = get_tree().get_first_node_in_group("local_player")
			if lp:
				var state = states[peer_id]
				lp.kills  = state.get("kills",  lp.kills)
				lp.deaths = state.get("deaths", lp.deaths)
				# Apply gear bonuses from server
				lp.gear_str    = state.get("gear_str",    0)
				lp.gear_hp     = state.get("gear_hp",     0)
				lp.gear_chakra = state.get("gear_chakra", 0)
				lp.gear_dex    = state.get("gear_dex",    0)
				lp.gear_int    = state.get("gear_int",    0)
				# Refresh char info if it's open
				var _ci = lp.char_info if lp.get("char_info") != null else lp.stat_panel
				if _ci and is_instance_valid(_ci) and _ci.visible:
					_ci.update_kd(lp.kills, lp.deaths)
					if _ci.has_method("set_player"):
						_ci.set_player(lp)
			continue
		var state    = states[peer_id]
		var their_zone = state.get("zone", "")
		# Only show players in the same zone as us
		var same_zone = (their_zone == current_zone)
		if not same_zone:
			# Remove node if they've left our zone
			if remote_player_nodes.has(peer_id):
				print("[CLIENT] Removing player %s — their zone=%s, ours=%s" % [state.get("username","?"), their_zone, current_zone])
				remote_player_nodes[peer_id].queue_free()
				remote_player_nodes.erase(peer_id)
			continue
		if not remote_player_nodes.has(peer_id):
			print("[CLIENT] Spawning remote player: %s zone=%s pos=%s" % [state.get("username","?"), their_zone, str(state.get("position", Vector2.ZERO))])
			var rp = Node2D.new()
			rp.set_script(load("res://scripts/remote_player.gd"))
			main.add_child(rp)
			rp.peer_id          = peer_id
			rp.set_username(state.get("username", "?"))
			rp.global_position  = state.get("position", Vector2.ZERO)
			rp.target_position  = rp.global_position
			rp.set_dead(state.get("is_dead", false))
			if rp.has_method("set_level"):
				rp.set_level(state.get("level", 1))
			rp.set_party_member(state.get("username", "") in my_party)
			if rp.has_method("set_rank"):
				rp.set_rank(state.get("rank", "Academy Student"))
			if rp.has_method("apply_appearance"):
				rp.apply_appearance(state.get("appearance", {}))
			if rp.has_method("apply_equipped"):
				rp.apply_equipped(state.get("equipped", {}))
			remote_player_nodes[peer_id] = rp
		else:
			var rp_node  = remote_player_nodes[peer_id]
			var r_hp     = state.get("hp", 1)
			var r_max_hp = state.get("max_hp", 100)
			rp_node.update_position(state.get("position", Vector2.ZERO))
			rp_node.set_dead(state.get("is_dead", false))
			var bcast_facing = state.get("facing_dir", "")
			if bcast_facing != "":
				rp_node.set_facing(bcast_facing)
			if rp_node.has_method("set_level"):
				rp_node.set_level(state.get("level", 1))
			rp_node.set_party_member(state.get("username", "") in my_party)
			if rp_node.has_method("set_rank"):
				rp_node.set_rank(state.get("rank", "Academy Student"))
			if rp_node.has_method("apply_appearance"):
				rp_node.apply_appearance(state.get("appearance", {}))
			if rp_node.has_method("apply_equipped"):
				rp_node.apply_equipped(state.get("equipped", {}))
			# Feed target HUD if this player is locked
			var lp = get_tree().get_first_node_in_group("local_player")
			var pid_key = "player_%d" % peer_id
			if lp and lp.locked_target_id == pid_key and lp.target_hud:
				lp.target_hud.update_target_player(r_hp, r_max_hp, state.get("level", 1))
	for peer_id in remote_player_nodes.keys():
		if not states.has(peer_id):
			remote_player_nodes[peer_id].queue_free()
			remote_player_nodes.erase(peer_id)

func _on_enemy_roster(zone: String, roster: Dictionary) -> void:
	# Cache static fields — merged into dynamic sync on first spawn
	if not _enemy_static_cache.has(zone):
		_enemy_static_cache[zone] = {}
	for enemy_id in roster:
		_enemy_static_cache[zone][enemy_id] = roster[enemy_id]

func _on_enemies_synced(all_zones: Dictionary) -> void:
	if world_node == null:
		return
	# Skip enemy sync while local player is dead — prevents enemy wipe during respawn transition
	var lp = get_tree().get_first_node_in_group("local_player")
	if lp and lp.is_dead:
		print("[CLIENT] Skipping enemy sync — player is dead, zone=%s" % current_zone)
		return
	# Only process if the packet contains our current zone — ignore mismatched zone data
	if not all_zones.has(current_zone):
		print("[CLIENT] Zone mismatch — got %s, we are in %s" % [str(all_zones.keys()), current_zone])
		return
	var states = all_zones.get(current_zone, {})
	# Log periodically when enemy count changes
	var incoming = states.size()
	var existing = remote_enemy_nodes.size()
	if incoming != existing:
		print("[CLIENT] Enemy count: local=%d incoming=%d zone=%s" % [existing, incoming, current_zone])
	for enemy_id in states:
		var state = states[enemy_id]
		# Merge dynamic state with cached static data
		var static_data = _enemy_static_cache.get(current_zone, {}).get(enemy_id, {})
		if not remote_enemy_nodes.has(enemy_id):
			# Skip spawn until we have static data — avoids "unknown" type and missing max_hp
			if static_data.is_empty():
				continue
			var re = Node2D.new()
			re.set_script(load("res://scripts/remote_enemy.gd"))
			var main = get_tree().root.get_node_or_null("Main")
			if main:
				main.add_child(re)
			else:
				world_node.add_child(re)
			re.global_position = state.get("position", Vector2.ZERO)
			re.target_position = re.global_position
			re.enemy_id        = enemy_id
			re.setup(static_data.get("type", "unknown"))
			var s_max_hp = static_data.get("max_hp", 0)
			var s_level  = static_data.get("level",  1)
			re.update_state(state.get("hp", 0), state.get("state", "idle"), s_max_hp, s_level)
			if static_data.has("hitbox_size"):
				re.update_hitbox_size(static_data["hitbox_size"])
			if static_data.has("attack_range"):
				re.set_attack_range(static_data["attack_range"])
			remote_enemy_nodes[enemy_id] = re
			if re.has_method("set_hitbox_visible"):
				re.set_hitbox_visible(_debug_enabled)
		else:
			var re = remote_enemy_nodes[enemy_id]
			re.update_position(state.get("position", Vector2.ZERO))
			# Use static max_hp if we have it — otherwise preserve what the node already has
			var known_max_hp = static_data.get("max_hp", 0)
			if known_max_hp <= 0:
				known_max_hp = re._hud_max_hp
			re.update_state(state.get("hp", 0), state.get("state", "idle"),
				known_max_hp, static_data.get("level", -1))
			# Feed target HUD if this is the locked enemy
			var player = get_tree().get_first_node_in_group("local_player")
			if player and player.locked_target_id == enemy_id and player.target_hud:
				player.target_hud.update_target(state.get("hp", 0), known_max_hp, static_data.get("level", -1))
	for enemy_id in remote_enemy_nodes.keys():
		if not states.has(enemy_id):
			# Auto-release targeting lock if this enemy is gone
			var player = get_tree().get_first_node_in_group("local_player")
			if player and "locked_target_id" in player and player.locked_target_id == enemy_id:
				player._set_target(null)
			var re_node = remote_enemy_nodes[enemy_id]
			if is_instance_valid(re_node):
				ParticleBurst.spawn(get_tree(), re_node.global_position, "death_enemy")
			re_node.queue_free()
			remote_enemy_nodes.erase(enemy_id)

func _on_enemy_killed(_xp: int, gold: int, _item_drop: String) -> void:
	# XP and level-up are handled server-authoritatively via notify_xp_gained / notify_level_up.
	# player.gd._on_enemy_killed handles gold float and item drop display.
	# Only keep gold tracking in game state here.
	my_player_data["gold"] = my_player_data.get("gold", 0) + gold

func _on_damage_received(amount: int, knockback_dir: Vector2) -> void:
	damage_received.emit(amount, knockback_dir)

func _get_local_player():
	var lp = get_tree().root.get_node_or_null("Main/Player")
	if lp: return lp
	for child in get_tree().root.get_children():
		var p = child.get_node_or_null("Player")
		if p: return p
	return null

func _on_party_update(party_data: Dictionary) -> void:
	my_party = party_data.get("members", [])
	my_party_leader = party_data.get("leader", "")
	var lp = _get_local_player()
	if lp and lp.party_hud:
		lp.party_hud.set_party(my_party, my_party_leader, my_username)
	# Refresh target HUD border color — party membership may have changed
	if lp and lp.target_hud and lp.locked_target != null and is_instance_valid(lp.locked_target):
		if "username" in lp.locked_target:
			lp.target_hud.set_target(lp.locked_target)

func _on_party_invite(inviter_name: String) -> void:
	var lp = _get_local_player()
	if lp and lp.party_invite_popup:
		lp.party_invite_popup.show_invite(inviter_name)
	elif lp and lp.chat:
		lp.chat.add_system_message("[PARTY] %s invited you. /accept %s or /decline %s" % [inviter_name, inviter_name, inviter_name])

func _on_party_msg(channel: String, text: String) -> void:
	var lp = _get_local_player()
	if lp and lp.chat:
		lp.chat.add_system_message("[PARTY] " + text)

func _on_player_disconnected(peer_id: int) -> void:
	remote_players.erase(peer_id)
	if remote_player_nodes.has(peer_id):
		remote_player_nodes[peer_id].queue_free()
		remote_player_nodes.erase(peer_id)

func _on_enemy_telegraph(enemy_id: String) -> void:
	if remote_enemy_nodes.has(enemy_id):
		remote_enemy_nodes[enemy_id].telegraph()

func on_enemy_telegraph_color(enemy_id: String, color: Color) -> void:
	if remote_enemy_nodes.has(enemy_id):
		remote_enemy_nodes[enemy_id].telegraph(color, 0.6)

func on_enemy_indicator(enemy_id: String, text: String, color: Color) -> void:
	if remote_enemy_nodes.has(enemy_id):
		remote_enemy_nodes[enemy_id].show_indicator(text, color)

func _on_kunai_spawned(start_pos: Vector2, direction: Vector2) -> void:
	var k            = Node2D.new()
	k.global_position = start_pos
	k.z_index        = 3
	var vis      = ColorRect.new()
	vis.size     = Vector2(6, 6)
	vis.position = Vector2(-3, -3)
	vis.color    = Color("f39c12")
	vis.z_index  = 3
	k.add_child(vis)
	var main = get_tree().root.get_node_or_null("Main")
	if main:
		main.add_child(k)
	var tween = k.create_tween()
	tween.tween_property(k, "global_position", start_pos + direction * 300.0, 1.5)
	tween.tween_callback(k.queue_free)

# ================================================================
# TARGETING HELPER
# ================================================================

func on_boss_telegraph(enemy_id: String, attack_type: String, origin: Vector2, size: Vector2, dir: Vector2, windup_time: float) -> void:
	var re = remote_enemy_nodes.get(enemy_id, null)
	if re and is_instance_valid(re):
		re.show_windup()
	var warning_script = load("res://scripts/boss_attack_warning.gd")
	if warning_script == null:
		return
	var warning = Node2D.new()
	warning.set_script(warning_script)
	var main = get_tree().root.get_node_or_null("Main")
	if main:
		main.add_child(warning)
	warning.setup(attack_type, origin, size, dir, windup_time)

func get_sorted_enemy_nodes(from_pos: Vector2) -> Array:
	var nodes = []
	for eid in remote_enemy_nodes:
		var re = remote_enemy_nodes[eid]
		if is_instance_valid(re):
			nodes.append(re)
	nodes.sort_custom(func(a, b): return a.global_position.distance_to(from_pos) < b.global_position.distance_to(from_pos))
	return nodes

# ── Right-click context menu ──────────────────────────────────
var _ctx_menu: PopupMenu = null
var _ctx_target_username: String = ""



func _on_ctx_menu_pressed(id: int) -> void:
	if id == 0 and _ctx_target_username != "":
		var net = get_tree().root.get_node_or_null("Network")
		if net and net.is_network_connected():
			net.send_party_invite.rpc_id(1, _ctx_target_username)
		var lp = _get_local_player()
		if lp and lp.chat:
			lp.chat.add_system_message("Sending party invite to %s..." % _ctx_target_username)

# ── Shadow Possession visuals ──────────────────────────────────────────────────

func _on_shadow_spawned(shadow_id: String, caster_peer_id: int, start_pos: Vector2, _target_id_str: String) -> void:
	# Despawn any existing visual with same id (re-cast)
	if _shadow_visuals.has(shadow_id):
		if is_instance_valid(_shadow_visuals[shadow_id]):
			_shadow_visuals[shadow_id].queue_free()
		_shadow_visuals.erase(shadow_id)

	var visual = Node2D.new()
	visual.set_script(load("res://scripts/shadow_visual.gd"))
	visual.shadow_id       = shadow_id
	visual.caster_peer_id  = caster_peer_id
	# Position at origin — the visual manages its own world-space drawing
	visual.global_position = Vector2.ZERO
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(visual)
		visual.init_positions(start_pos, start_pos)
		_shadow_visuals[shadow_id] = visual

func _on_shadow_moved(shadow_id: String, pos: Vector2) -> void:
	var visual = _shadow_visuals.get(shadow_id, null)
	if visual and is_instance_valid(visual):
		visual.move_to(pos)

func _on_ability_visual(target_id_str: String, visual_id: String) -> void:
	var node: Node = null
	# Try remote enemy dict first (keyed by enemy_id string e.g. "wolf_0")
	if remote_enemy_nodes.has(target_id_str):
		node = remote_enemy_nodes[target_id_str]
	# Try remote player by peer_id
	if node == null:
		var players = get_tree().get_nodes_in_group("remote_players")
		for p in players:
			if str(p.peer_id) == target_id_str:
				node = p
				break
	# Try local player
	if node == null:
		var lp = get_tree().get_first_node_in_group("local_player")
		if lp and str(lp.get_multiplayer_authority()) == target_id_str:
			node = lp
	if node == null or not is_instance_valid(node):
		return
	match visual_id:
		"strangle":
			if node.has_method("flash_visual"):
				node.flash_visual("strangle")

func _on_shadow_despawned(shadow_id: String, hit: bool) -> void:
	var is_clear  = shadow_id.ends_with("_clear")
	var lookup_id = shadow_id.trim_suffix("_clear")
	var visual    = _shadow_visuals.get(lookup_id, null)

	if is_clear:
		# Shadow ended after catch (cancel/chakra empty) — fade frozen line, end ability
		if visual and is_instance_valid(visual):
			visual.play_despawn_effect()
		_shadow_visuals.erase(lookup_id)
		_shadow_force_cancel(lookup_id)
		return

	if hit:
		# Caught — freeze line, keep draining (force_cancel fires on _clear)
		if visual and is_instance_valid(visual):
			visual.play_hit_effect()
	else:
		# Missed or cancelled before catch — fade line, end ability now
		if visual and is_instance_valid(visual):
			visual.play_despawn_effect()
		_shadow_visuals.erase(lookup_id)
		_shadow_force_cancel(lookup_id)

func _shadow_force_cancel(lookup_id: String) -> void:
	var lp = _get_local_player()
	if lp == null:
		return
	var my_id = multiplayer.get_unique_id()
	if lookup_id == "shadow_%d" % my_id and lp.hotbar != null:
		for slot in lp.hotbar.slots:
			if slot != null and slot.has_method("force_cancel"):
				slot.force_cancel()
