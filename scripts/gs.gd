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
var _air_palm_orbs:   Dictionary = {}  # caster_peer_id -> orb Node2D
var _clay_spiders:    Dictionary = {}  # spider_id -> Node2D
var _clay_owls:       Dictionary = {}  # owl_id -> Node2D
var _clay_bombs:      Dictionary = {}  # bomb_id -> { node, danger_handle }
var _explosion_frames: SpriteFrames = null  # preloaded once, reused for every explosion
var _c4_swarms:       Dictionary = {}  # swarm_id -> Array of dot Node2Ds
var world_node:     Node       = null

var remote_player_nodes: Dictionary = {}
var remote_enemy_nodes:  Dictionary = {}
var _shadow_visuals:     Dictionary = {}   # shadow_id -> ShadowVisual node
var _trap_visuals:       Dictionary = {}   # trap_id   -> TrapVisual node
var _shadow_circles:     Dictionary = {}   # shadow_id -> Array[Node2D] ground circles
var _shadow_meta:        Dictionary = {}   # shadow_id -> {caster_peer_id, target_id_str}
var _enemy_static_cache: Dictionary = {}  # static enemy data cached per zone
var _debug_enabled: bool = false  # F1 toggles debug visuals
var current_zone:   String = "village"  # tracked on every zone load
var my_party:       Array  = []          # usernames of current party members (includes self)
var my_party_leader: String = ""          # username of current party leader
var _last_logged_zone: String = ""

func _ready() -> void:
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	if Network.is_server:
		return  # gs.gd is an autoload — runs on server too. All signals here are client-only.
	Network.login_accepted_client.connect(_on_login_accepted)
	Network.login_denied_client.connect(_on_login_denied)
	Network.players_synced_client.connect(_on_players_synced)
	Network.party_update_received.connect(_on_party_update)
	Network.party_invite_received.connect(_on_party_invite)
	Network.party_msg_received.connect(_on_party_msg)
	Network.damage_received_client.connect(_on_damage_received)
	Network.enemies_synced_client.connect(_on_enemies_synced)
	Network.enemy_hit_flash_received.connect(_on_enemy_hit_flash)
	Network.player_disconnected.connect(_on_player_disconnected)
	Network.enemy_killed_client.connect(_on_enemy_killed)
	Network.enemy_roster_client.connect(_on_enemy_roster)
	Network.enemy_telegraph_received.connect(_on_enemy_telegraph)
	Network.kunai_spawned.connect(_on_kunai_spawned)
	Network.shadow_spawned.connect(_on_shadow_spawned)
	Network.shadow_moved.connect(_on_shadow_moved)
	Network.shadow_despawned.connect(_on_shadow_despawned)
	Network.trap_spawned.connect(_on_trap_spawned)
	Network.trap_despawned.connect(_on_trap_despawned)
	Network.ability_visual_received.connect(_on_ability_visual)
	Network.enemy_pulled_received.connect(_on_enemy_pulled)
	Network.mass_shadow_visual_received.connect(_on_mass_shadow_visual)
	Network.air_palm_visual_received.connect(_on_air_palm_visual)
	Network.air_palm_stop_received.connect(_on_air_palm_stop)
	Network.clay_spider_visual_received.connect(_on_clay_spider_visual)
	Network.clay_spider_stop_received.connect(_on_clay_spider_stop)
	Network.clay_owl_spawn_received.connect(_on_clay_owl_spawn)
	Network.clay_owl_move_received.connect(_on_clay_owl_move)
	Network.clay_owl_explode_received.connect(_on_clay_owl_explode)
	Network.clay_bomb_spawn_received.connect(_on_clay_bomb_spawn)
	Network.clay_bomb_stage_received.connect(_on_clay_bomb_stage)
	Network.clay_bomb_explode_received.connect(_on_clay_bomb_explode)
	Network.c4_spawn_received.connect(_on_c4_spawn)
	Network.c4_chain_explode_received.connect(_on_c4_chain_explode)
	Network.byakugan_state_received.connect(_on_byakugan_state)
	Network.gold_synced.connect(_on_gold_synced)
	Network.item_granted.connect(_on_item_granted)
	Network.chakra_drain_visual_received.connect(_on_chakra_drain_visual)
	Network.palms_cinematic_received.connect(_on_palms_cinematic)
	Network.palms_prime_expired_received.connect(_on_palms_prime_expired)
	Network.palms_cinematic_end_received.connect(_on_palms_cinematic_end)

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
				# Server-authoritative status flags — drives movement lock on local player
				var srv_spinning: bool = state.get("is_spinning", false)
				var srv_rooted:   bool = state.get("is_rooted",   false)
				if srv_spinning != lp.is_spinning:
					lp.is_spinning = srv_spinning
					lp.flash_visual("rotation_start" if srv_spinning else "rotation_end")
				if srv_rooted != lp.is_rooted:
					lp.is_rooted = srv_rooted
					if srv_rooted:
						lp.flash_visual("rooted_start")
					else:
						lp.flash_visual("rooted_end")
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
			# Restore status visuals for players already in an active state
			if state.get("is_spinning", false):
				rp.flash_visual("rotation_start")
			if state.get("is_rooted", false):
				rp.flash_visual("rooted_start")
			# If local player already has Byakugan active, show the chakra bar
			# on this newly-entered player immediately rather than waiting for a toggle.
			var lp_spawn = get_tree().get_first_node_in_group("local_player")
			if lp_spawn and lp_spawn.get("byakugan_active") == true:
				if rp.has_method("set_byakugan_visible"):
					rp.set_byakugan_visible(true)
				if rp.has_method("update_chakra_bar"):
					rp.update_chakra_bar(state.get("chakra", 0), state.get("max_chakra", 100))
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
			# Always keep chakra data fresh — bar visibility is controlled separately by
			# set_byakugan_visible so values are correct the moment Byakugan activates.
			var lp = get_tree().get_first_node_in_group("local_player")
			if rp_node.has_method("update_chakra_bar"):
				rp_node.update_chakra_bar(state.get("chakra", 0), state.get("max_chakra", 100))
			# Feed target HUD if this player is locked
			var pid_key = "player_%d" % peer_id
			if lp and lp.locked_target_id == pid_key and lp.target_hud:
				lp.target_hud.update_target_player(r_hp, r_max_hp, state.get("level", 1))
			# Sync status visuals: detect transitions so we only call flash_visual on change
			var now_spinning: bool = state.get("is_spinning", false)
			if now_spinning and not rp_node.is_spinning:
				rp_node.flash_visual("rotation_start")
			elif not now_spinning and rp_node.is_spinning:
				rp_node.flash_visual("rotation_end")
			var now_rooted: bool = state.get("is_rooted", false)
			if now_rooted and not rp_node.is_rooted:
				rp_node.flash_visual("rooted_start")
			elif not now_rooted and rp_node.is_rooted:
				rp_node.flash_visual("rooted_end")
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

func _on_enemy_hit_flash(enemy_id: String) -> void:
	var node = remote_enemy_nodes.get(enemy_id, null)
	if node and is_instance_valid(node) and node.has_method("hit_flash"):
		node.hit_flash()

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
			var hp_now = state.get("hp", 0)
			re.update_state(hp_now, state.get("state", "idle"),
				known_max_hp, static_data.get("level", -1))
			# Update byakugan bar if local player has byakugan active
			var lp_byk = get_tree().get_first_node_in_group("local_player")
			if lp_byk and lp_byk.get("byakugan_active") == true:
				if re.has_method("set_byakugan_visible"):
					re.set_byakugan_visible(true, hp_now, known_max_hp)
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

func _on_gold_synced(amount: int) -> void:
	my_player_data["gold"] = amount
	# Update any gold display UI if present
	var lp = get_tree().get_first_node_in_group("local_player")
	if lp and lp.hud and lp.hud.has_method("update_gold"):
		lp.hud.update_gold(amount)

func _on_item_granted(item_id: String, quantity: int) -> void:
	var lp = get_tree().get_first_node_in_group("local_player")
	if lp and lp.inventory and lp.inventory.has_method("add_item"):
		var item_data = ItemDB.get_item(item_id)
		if not item_data.is_empty():
			item_data["quantity"] = quantity
			lp.inventory.add_item(item_data)

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

func _on_mass_shadow_visual(origin: Vector2, radius: float) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return
	# Expanding dark ring using a shader-driven ColorRect
	var holder = Node2D.new()
	holder.global_position = origin
	holder.z_index = 3
	scene_root.add_child(holder)

	var rect   = ColorRect.new()
	var mat    = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float radius : hint_range(0.0, 512.0) = 10.0;
uniform float thickness : hint_range(1.0, 20.0) = 4.0;
uniform vec2  center = vec2(0.0, 0.0);
void fragment() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float d = distance(world, center);
	float edge = 1.0 - smoothstep(radius - thickness, radius, d);
	edge *= smoothstep(radius - thickness * 2.0, radius - thickness, d);
	COLOR = vec4(0.25, 0.02, 0.45, 0.8 * edge);
}
"""
	mat.shader = shader
	mat.set_shader_parameter("center", origin)
	mat.set_shader_parameter("radius", 10.0)
	mat.set_shader_parameter("thickness", 5.0)
	rect.material = mat
	rect.size     = Vector2(radius * 2.0 + 20.0, radius * 2.0 + 20.0)
	rect.position = Vector2(-radius - 10.0, -radius - 10.0)
	holder.add_child(rect)

	var tween = get_tree().create_tween()
	tween.tween_method(func(r: float):
		if is_instance_valid(mat):
			mat.set_shader_parameter("radius", r)
	, 10.0, radius, 0.35)
	tween.tween_property(holder, "modulate:a", 0.0, 0.3)
	tween.tween_callback(holder.queue_free)

func _on_air_palm_visual(caster_peer_id: int, from_pos: Vector2, to_pos: Vector2) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return
	# Spawn a fast-travelling blue orb from caster to target
	var orb = Node2D.new()
	orb.global_position = from_pos
	orb.z_index = 4
	scene_root.add_child(orb)
	# Draw a glowing circle
	var rect   = ColorRect.new()
	var mat    = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float core = 1.0 - smoothstep(0.0, 0.45, d);
	float glow = 1.0 - smoothstep(0.4, 1.0, d);
	COLOR = vec4(0.55, 0.92, 1.0, core * 0.95 + glow * 0.4);
}
"""
	mat.shader = shader
	rect.material = mat
	rect.size     = Vector2(20, 20)
	rect.position = Vector2(-10, -10)
	orb.add_child(rect)
	# Store orb so _on_air_palm_stop can redirect it
	_air_palm_orbs[caster_peer_id] = orb
	orb.tree_exited.connect(func(): _air_palm_orbs.erase(caster_peer_id))
	# Travel tween — server will send air_palm_stop if it hits early
	var dist     = from_pos.distance_to(to_pos)
	var duration = clamp(dist / 500.0, 0.08, 0.65)
	var tween    = get_tree().create_tween()
	tween.tween_property(orb, "global_position", to_pos, duration)
	tween.tween_property(orb, "modulate:a", 0.0, 0.12)
	tween.tween_callback(orb.queue_free)
	orb.set_meta("tween", tween)

func _on_air_palm_stop(caster_peer_id: int, hit_pos: Vector2) -> void:
	var orb = _air_palm_orbs.get(caster_peer_id, null)
	if orb == null or not is_instance_valid(orb):
		return
	# Kill the existing tween and snap orb to hit position, then fade out
	var old_tween = orb.get_meta("tween", null)
	if old_tween and old_tween.is_valid():
		old_tween.kill()
	orb.global_position = hit_pos
	var tw = get_tree().create_tween()
	tw.tween_property(orb, "modulate:a", 0.0, 0.12)
	tw.tween_callback(orb.queue_free)

# ── Clay Spider Visuals ───────────────────────────────────────────────────────

func _on_clay_spider_visual(caster_peer_id: int, spider_id: String, from_pos: Vector2, to_pos: Vector2, dir_str: String, proj_speed: float = 160.0) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return

	# Build AnimatedSprite2D from individual frame PNGs
	var sframes   = SpriteFrames.new()
	var anim_name = "walk"
	sframes.add_animation(anim_name)
	sframes.set_animation_loop(anim_name, true)
	sframes.set_animation_speed(anim_name, 8.0 * (proj_speed / 160.0))

	var base_path = "res://sprites/Clay/Spider/spider_%s_" % dir_str
	for i in range(4):
		var tex = load(base_path + str(i) + ".png")
		if tex:
			sframes.add_frame(anim_name, tex)

	var spr = AnimatedSprite2D.new()
	spr.sprite_frames = sframes
	spr.play(anim_name)
	spr.z_index = 3
	spr.global_position = from_pos
	scene_root.add_child(spr)

	_clay_spiders[spider_id] = spr
	# Clean up dict entry when node is freed by either path
	spr.tree_exited.connect(func(): _clay_spiders.erase(spider_id))

	# Travel at server speed (boon-modified) so visual matches hit timing
	var dist     = from_pos.distance_to(to_pos)
	var duration = dist / max(proj_speed, 1.0)
	var tween    = get_tree().create_tween()
	tween.tween_property(spr, "global_position", to_pos, duration)
	# If server never sends stop (5 s timeout expired), explode at arrival point
	tween.tween_callback(func():
		if is_instance_valid(spr):
			var end_pos = spr.global_position
			spr.queue_free()
			_spawn_explosion(end_pos)
	)
	spr.set_meta("tween", tween)

func _on_clay_spider_stop(spider_id: String, hit_pos: Vector2) -> void:
	# Kill the travelling spider and spawn explosion at server-confirmed hit position
	var spr = _clay_spiders.get(spider_id, null)
	if spr != null and is_instance_valid(spr):
		var old_tween = spr.get_meta("tween", null)
		if old_tween and old_tween.is_valid():
			old_tween.kill()
		spr.queue_free()
	# Don't erase dict here — tree_exited signal handles it
	_spawn_explosion(hit_pos)

# ── Clay Owl Visuals ──────────────────────────────────────────────────────────

func _on_clay_owl_spawn(owl_id: String, caster_peer_id: int, from_pos: Vector2, _target_id: String) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return

	var tex = load("res://sprites/Clay/Owl/owl_right_0.png")
	var spr = Sprite2D.new()
	if tex:
		spr.texture = tex
	spr.z_index = 4
	spr.global_position = from_pos
	scene_root.add_child(spr)

	_clay_owls[owl_id] = spr
	spr.tree_exited.connect(func(): _clay_owls.erase(owl_id))

func _on_clay_owl_move(owl_id: String, pos: Vector2, dir_str: String) -> void:
	var spr = _clay_owls.get(owl_id, null)
	if spr == null or not is_instance_valid(spr):
		return
	spr.global_position = pos
	var tex = load("res://sprites/Clay/Owl/owl_%s_0.png" % dir_str)
	if tex:
		spr.texture = tex

func _on_clay_owl_explode(owl_id: String, pos: Vector2) -> void:
	var spr = _clay_owls.get(owl_id, null)
	if spr != null and is_instance_valid(spr):
		spr.queue_free()
	_spawn_explosion(pos, 3.0)

# ── Clay Bomb Visuals ─────────────────────────────────────────────────────────

const BOMB_BASE_SCALE: float = 0.6   # stage 0 scale — grows to 2.0 at stage 3

func _on_clay_bomb_spawn(bomb_id: String, pos: Vector2, stage: int, radius: float) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return

	var tex = load("res://sprites/Clay/C3/clay.png")
	var spr = Sprite2D.new()
	if tex:
		spr.texture = tex
	spr.z_index = 3
	spr.global_position = pos
	var s = lerp(BOMB_BASE_SCALE, 2.0, float(stage) / 3.0)
	spr.scale = Vector2(s, s)
	scene_root.add_child(spr)

	# Spawn danger tile grid — full 10 second duration
	var handle = DangerTiles.spawn(pos, radius, 10.0)

	_clay_bombs[bomb_id] = { "node": spr, "danger_handle": handle }
	spr.tree_exited.connect(func(): _clay_bombs.erase(bomb_id))

func _on_clay_bomb_stage(bomb_id: String, stage: int, radius: float) -> void:
	var entry = _clay_bombs.get(bomb_id, null)
	if entry == null:
		return
	# Scale bomb sprite up with stage
	var spr = entry["node"]
	if is_instance_valid(spr):
		var s = lerp(BOMB_BASE_SCALE, 2.0, float(stage) / 3.0)
		var tw = get_tree().create_tween()
		tw.tween_property(spr, "scale", Vector2(s, s), 0.3)
	# Grow danger tiles
	DangerTiles.grow(entry["danger_handle"], radius)

func _on_clay_bomb_explode(bomb_id: String, pos: Vector2, radius: float) -> void:
	var entry = _clay_bombs.get(bomb_id, null)
	if entry != null:
		DangerTiles.despawn(entry["danger_handle"])
		var spr = entry["node"]
		if is_instance_valid(spr):
			spr.queue_free()
	# Scale explosion sprite so it fills the full blast radius
	# Frames are 64x64, diameter = radius * 2, so scale = radius / 32
	var scale_factor = radius / 32.0
	_spawn_explosion(pos, scale_factor)

func _spawn_explosion(pos: Vector2, scale_factor: float = 1.0) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return
	# Preload frames once — avoids 13 blocking disk reads per explosion
	if _explosion_frames == null:
		_explosion_frames = SpriteFrames.new()
		_explosion_frames.add_animation("boom")
		_explosion_frames.set_animation_loop("boom", false)
		_explosion_frames.set_animation_speed("boom", 20.0)
		for i in range(13):
			var tex = load("res://sprites/explosion_frames/explosion_%d.png" % i)
			if tex:
				_explosion_frames.add_frame("boom", tex)
	# Cap visual scale — large radii use multiple smaller explosions instead of one giant sprite
	var clamped_scale = min(scale_factor, 8.0)
	if scale_factor > 8.0:
		# Scatter a ring of smaller explosions for large blasts
		var ring_count = mini(int(scale_factor / 4.0), 8)
		for i in range(ring_count):
			var angle  = (TAU / ring_count) * i
			var offset = Vector2(cos(angle), sin(angle)) * (scale_factor * 16.0)
			_spawn_explosion(pos + offset, clamped_scale)
	var spr             = AnimatedSprite2D.new()
	spr.sprite_frames   = _explosion_frames
	spr.scale           = Vector2(clamped_scale, clamped_scale)
	spr.z_index         = 5
	spr.global_position = pos
	scene_root.add_child(spr)
	spr.play("boom")
	spr.animation_finished.connect(spr.queue_free)

func _on_chakra_drain_visual(pos: Vector2, amount: int) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return
	var lbl = Label.new()
	lbl.text = "-%d ✦" % amount
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.2, 0.85, 0.85, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.z_index = 10
	scene_root.add_child(lbl)
	lbl.global_position = pos + Vector2(-10, -36)
	var tw = get_tree().create_tween()
	tw.tween_property(lbl, "position", lbl.position + Vector2(0, -22), 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9)
	tw.tween_callback(lbl.queue_free)

# State for the active palms cinematic — one at a time per client
var _palms_caster_ghost:   Node   = null
var _palms_caster_peer_id: int    = -1
var _palms_target_id_str:  String = ""

func _on_palms_prime_expired() -> void:
	# Server says the prime window ran out — clear the ability's timer bar
	var player: Node = get_tree().get_first_node_in_group("local_player")
	if player == null or player.hotbar == null:
		return
	for slot in player.hotbar.slots:
		if slot != null and "ability_id" in slot and slot.ability_id == "64_palms":
			if slot.has_method("clear_prime"):
				slot.clear_prime()

func _on_palms_cinematic(caster_peer_id: int, target_id_str: String, hit_count: int, interval: float, icon_path: String) -> void:
	# ── Resolve nodes ─────────────────────────────────────────────────────
	var target_node: Node = null
	if remote_enemy_nodes.has(target_id_str):
		target_node = remote_enemy_nodes[target_id_str]
	else:
		var tpid: int = target_id_str.to_int()
		if remote_player_nodes.has(tpid):
			target_node = remote_player_nodes[tpid]
		elif tpid == multiplayer.get_unique_id():
			target_node = get_tree().get_first_node_in_group("local_player")
	if target_node == null or not is_instance_valid(target_node):
		return

	var caster_node: Node = null
	if caster_peer_id == multiplayer.get_unique_id():
		caster_node = get_tree().get_first_node_in_group("local_player")
	else:
		caster_node = remote_player_nodes.get(caster_peer_id, null)

	# Clear prime bar if this client is the caster
	if caster_peer_id == multiplayer.get_unique_id():
		var player: Node = caster_node
		if player and player.hotbar:
			for slot in player.hotbar.slots:
				if slot != null and "ability_id" in slot and slot.ability_id == "64_palms":
					if slot.has_method("clear_prime"):
						slot.clear_prime()

	var scene: Node      = get_tree().current_scene
	var target_world_pos: Vector2 = target_node.global_position
	var total_dur: float  = float(hit_count) * interval

	# ── Store for cinematic_end ───────────────────────────────────────────
	_palms_caster_peer_id = caster_peer_id
	_palms_target_id_str  = target_id_str

	# ── Camera lock to target ─────────────────────────────────────────────
	if caster_peer_id == multiplayer.get_unique_id() or true:
		var local_player: Node = get_tree().get_first_node_in_group("local_player")
		if local_player != null:
			var cam = local_player.get_node_or_null("Camera2D")
			if cam and cam.has_method("lock_to"):
				cam.lock_to(target_node, total_dur + 0.8)

	# ── Get caster sprite texture for ghosts ──────────────────────────────
	var player_tex: Texture2D = null
	if caster_node != null:
		# Try named child first (local player), then .sprite property (remote player)
		var anim_spr: AnimatedSprite2D = null
		if caster_node.has_node("AnimatedSprite2D"):
			anim_spr = caster_node.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if anim_spr == null and "sprite" in caster_node:
			anim_spr = caster_node.get("sprite") as AnimatedSprite2D
		if anim_spr != null and is_instance_valid(anim_spr):
			var sf: SpriteFrames = anim_spr.sprite_frames
			if sf != null and sf.has_animation(anim_spr.animation):
				player_tex = sf.get_frame_texture(anim_spr.animation, anim_spr.frame)

	# ── Trigram icon backdrop ─────────────────────────────────────────────
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon_spr := Sprite2D.new()
		icon_spr.texture          = load(icon_path)
		icon_spr.global_position  = target_world_pos
		icon_spr.scale            = Vector2(0.625, 0.625)
		icon_spr.modulate         = Color(0.3, 0.65, 1.0, 0.0)
		icon_spr.z_index          = 4
		scene.add_child(icon_spr)
		var tw_icon := get_tree().create_tween()
		tw_icon.tween_property(icon_spr, "modulate:a", 0.35, 0.12)
		tw_icon.tween_property(icon_spr, "rotation", TAU * 0.5, total_dur).set_trans(Tween.TRANS_LINEAR)
		get_tree().create_timer(total_dur + 0.25).timeout.connect(func() -> void:
			if is_instance_valid(icon_spr):
				var tw_out := get_tree().create_tween()
				tw_out.tween_property(icon_spr, "modulate:a", 0.0, 0.2)
				tw_out.tween_callback(icon_spr.queue_free)
		)

	# ── Caster teleport blur ──────────────────────────────────────────────
	var caster_old_pos: Vector2 = caster_node.global_position if caster_node != null else target_world_pos
	var orbit_radius: float     = 60.0
	var orbit_angle: float      = randf() * TAU
	var caster_new_pos: Vector2 = target_world_pos + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius

	# Blur trail — 4 ghost copies fading from old to new position
	for b in range(4):
		var t_lerp: float    = float(b) / 3.0
		var blur_pos: Vector2 = caster_old_pos.lerp(caster_new_pos, t_lerp)
		var blur_ghost: Node2D
		if player_tex != null:
			blur_ghost = Sprite2D.new()
			(blur_ghost as Sprite2D).texture = player_tex
		else:
			blur_ghost = Polygon2D.new()
			(blur_ghost as Polygon2D).polygon = PackedVector2Array([Vector2(0,-8),Vector2(5,0),Vector2(0,8),Vector2(-5,0)])
			(blur_ghost as Polygon2D).color   = Color(0.4, 0.85, 1.0, 0.6)
		blur_ghost.global_position = blur_pos
		blur_ghost.modulate        = Color(0.5, 0.88, 1.0, 0.65 - t_lerp * 0.35)
		blur_ghost.z_index         = 8
		scene.add_child(blur_ghost)
		var tw_blur := get_tree().create_tween()
		tw_blur.tween_property(blur_ghost, "modulate:a", 0.0, 0.18)
		tw_blur.tween_callback(blur_ghost.queue_free)

	# Main caster ghost at orbit position (persistent for combo duration)
	var caster_ghost: Node2D
	if player_tex != null:
		caster_ghost = Sprite2D.new()
		(caster_ghost as Sprite2D).texture = player_tex
	else:
		caster_ghost = Polygon2D.new()
		(caster_ghost as Polygon2D).polygon = PackedVector2Array([Vector2(0,-8),Vector2(5,0),Vector2(0,8),Vector2(-5,0)])
		(caster_ghost as Polygon2D).color   = Color(0.4, 0.85, 1.0, 0.8)
	caster_ghost.global_position = caster_new_pos
	caster_ghost.modulate        = Color(0.55, 0.9, 1.0, 0.85)
	caster_ghost.z_index         = 9
	scene.add_child(caster_ghost)
	_palms_caster_ghost = caster_ghost

	# Hide the entire caster node (body + hair + equip layers all at once)
	if caster_node != null:
		caster_node.modulate.a = 0.0

	# ── Per-hit afterimages at RANDOM ring positions ──────────────────────
	for i in range(hit_count):
		var delay_t: float = float(i) * interval
		get_tree().create_timer(delay_t).timeout.connect(func() -> void:
			if not is_instance_valid(target_node):
				return
			var ring_angle: float  = randf() * TAU
			var ring_radius: float = randf_range(22.0, 42.0)
			var hit_world: Vector2 = target_node.global_position + Vector2(cos(ring_angle), sin(ring_angle)) * ring_radius

			# Afterimage ghost
			var ghost: Node2D
			if player_tex != null:
				ghost = Sprite2D.new()
				(ghost as Sprite2D).texture = player_tex
			else:
				ghost = Polygon2D.new()
				(ghost as Polygon2D).polygon = PackedVector2Array([Vector2(0,-8),Vector2(5,0),Vector2(0,8),Vector2(-5,0)])
				(ghost as Polygon2D).color   = Color(0.3, 0.75, 1.0, 0.8)
			ghost.global_position = hit_world
			ghost.modulate        = Color(0.35, 0.78, 1.0, 0.85)
			ghost.z_index         = 9
			scene.add_child(ghost)
			var tw_g := get_tree().create_tween()
			tw_g.tween_property(ghost, "modulate:a", 0.0, 0.28)
			tw_g.tween_callback(ghost.queue_free)

			# Impact flash on target
			if target_node.has_method("flash_visual"):
				target_node.flash_visual("gentle_fist")

			# Impact burst ring
			var burst := ColorRect.new()
			burst.size             = Vector2(6, 6)
			burst.color            = Color(0.5, 0.9, 1.0, 0.9)
			burst.z_index          = 10
			burst.global_position  = hit_world - Vector2(3, 3)
			scene.add_child(burst)
			var tw_burst := get_tree().create_tween()
			tw_burst.tween_property(burst, "scale", Vector2(3.0, 3.0), 0.18)
			tw_burst.parallel().tween_property(burst, "modulate:a", 0.0, 0.18)
			tw_burst.tween_callback(burst.queue_free)
		)

func _on_palms_cinematic_end(caster_peer_id: int, target_pos: Vector2, knockback_dir: Vector2) -> void:
	# ── Restore caster sprite ─────────────────────────────────────────────
	var caster_node: Node = null
	if caster_peer_id == multiplayer.get_unique_id():
		caster_node = get_tree().get_first_node_in_group("local_player")
	else:
		caster_node = remote_player_nodes.get(caster_peer_id, null)
	if caster_node != null:
		var tw_restore := get_tree().create_tween()
		tw_restore.tween_property(caster_node, "modulate:a", 1.0, 0.15)

	# Fade caster ghost
	if _palms_caster_ghost != null and is_instance_valid(_palms_caster_ghost):
		var tw_g := get_tree().create_tween()
		tw_g.tween_property(_palms_caster_ghost, "modulate:a", 0.0, 0.2)
		tw_g.tween_callback(_palms_caster_ghost.queue_free)
	_palms_caster_ghost = null

	# ── Knockback the target visually ─────────────────────────────────────
	var target_node: Node = null
	if remote_enemy_nodes.has(_palms_target_id_str):
		target_node = remote_enemy_nodes[_palms_target_id_str]
	else:
		var tpid: int = _palms_target_id_str.to_int()
		if remote_player_nodes.has(tpid):
			target_node = remote_player_nodes[tpid]
		elif tpid == multiplayer.get_unique_id():
			target_node = get_tree().get_first_node_in_group("local_player")
	if target_node != null and is_instance_valid(target_node):
		var kb_dest: Vector2 = target_node.global_position + knockback_dir * 150.0
		# freeze_for_knockback snaps position + target_position and blocks
		# update_position() for the freeze window so sync ticks can't drag it back
		if target_node.has_method("freeze_for_knockback"):
			target_node.freeze_for_knockback(kb_dest, 0.7)
		else:
			# local player — just tween, physics handles it
			var tw_kb := get_tree().create_tween()
			tw_kb.tween_property(target_node, "global_position", kb_dest, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		# Final flash on target
		if target_node.has_method("flash_visual"):
			target_node.flash_visual("gentle_fist")

	# ── Release camera (smooth return handled by camera.gd lerp) ──────────
	var local_player: Node = get_tree().get_first_node_in_group("local_player")
	if local_player != null:
		var cam = local_player.get_node_or_null("Camera2D")
		if cam and cam.has_method("release_lock"):
			cam.release_lock()

	# Reset cinematic state
	_palms_caster_peer_id = -1
	_palms_target_id_str  = ""
func _on_byakugan_state(caster_peer_id: int, active: bool) -> void:
	var my_id = multiplayer.get_unique_id()
	if caster_peer_id == my_id:
		# Local player toggled — show/hide byakugan bars on all remote enemies
		for eid in remote_enemy_nodes:
			var en = remote_enemy_nodes[eid]
			if is_instance_valid(en) and en.has_method("set_byakugan_visible"):
				en.set_byakugan_visible(active, en._hud_current_hp, en._hud_max_hp)
		# Also show/hide chakra bars on all remote players
		for pid in remote_player_nodes:
			var rp = remote_player_nodes[pid]
			if is_instance_valid(rp) and rp.has_method("set_byakugan_visible"):
				rp.set_byakugan_visible(active)
		# If server force-deactivated (chakra empty) — cancel slot + remove tint
		if not active:
			var lp = get_tree().get_first_node_in_group("local_player")
			if lp and lp.hotbar != null:
				for slot in lp.hotbar.slots:
					if slot != null and slot.has_method("is_active") and slot.is_active():
						if slot.get("ability_id") == "byakugan" or slot.get("ability_name") == "Byakugan":
							slot.force_cancel()
							break
		return
	var node = remote_player_nodes.get(caster_peer_id, null)
	if node == null or not is_instance_valid(node):
		return
	var spr = node.get_node_or_null("AnimatedSprite2D")
	if spr == null:
		return
	if active:
		var tw = get_tree().create_tween()
		tw.tween_property(spr, "modulate", Color(0.85, 0.97, 1.0, 1.0), 0.3)
	else:
		var tw = get_tree().create_tween()
		tw.tween_property(spr, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.3)

func _on_enemy_pulled(enemy_id: String, new_pos: Vector2, caster_pos: Vector2) -> void:
	var eid = enemy_id.trim_prefix("enemy_")
	var re = remote_enemy_nodes.get(eid, remote_enemy_nodes.get(enemy_id, null))
	if re and is_instance_valid(re):
		# Drag: tween target_position through steps toward caster
		var start  = re.global_position
		var steps  = 6
		var tween  = get_tree().create_tween()
		for i in range(1, steps + 1):
			var waypoint = start.lerp(new_pos, float(i) / float(steps))
			tween.tween_callback(func(): 
				if is_instance_valid(re): re.update_position(waypoint)
			).set_delay(0.04 * i)
		# Snap to final after animation
		tween.tween_callback(func():
			if is_instance_valid(re): re.update_position(new_pos)
		)
	_spawn_pull_visual(caster_pos, new_pos)
	# Retract the shadow trail to follow the pulled enemy
	for sid in _shadow_visuals:
		var vis = _shadow_visuals[sid]
		if is_instance_valid(vis) and vis.has_method("retract_to"):
			vis.retract_to(new_pos, 0.24)
			break

func _spawn_pull_visual(from: Vector2, to: Vector2) -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return
	var line = Line2D.new()
	line.width         = 4.0
	line.default_color = Color(0.45, 0.1, 0.7, 0.95)
	line.add_point(from)
	line.add_point(to)
	line.z_index = 5
	scene_root.add_child(line)
	var tween = get_tree().create_tween()
	tween.tween_method(func(t: float):
		if is_instance_valid(line):
			line.set_point_position(1, to.lerp(from, t))
	, 0.0, 1.0, 0.25)
	tween.tween_property(line, "modulate:a", 0.0, 0.1)
	tween.tween_callback(line.queue_free)


func _get_mass_shadow_slot() -> Resource:
	var lp = _get_local_player()
	if lp == null or lp.hotbar == null:
		return null
	for slot in lp.hotbar.slots:
		if slot != null and "caught_target_ids" in slot:
			return slot
	return null
func _on_shadow_spawned(shadow_id: String, caster_peer_id: int, start_pos: Vector2, _target_id_str: String) -> void:
	# Despawn any existing visual with same id (re-cast)
	if _shadow_visuals.has(shadow_id):
		if is_instance_valid(_shadow_visuals[shadow_id]):
			_shadow_visuals[shadow_id].queue_free()
		_shadow_visuals.erase(shadow_id)

	_shadow_meta[shadow_id] = {caster_peer_id = caster_peer_id, target_id_str = _target_id_str}
	var my_id_sp = multiplayer.get_unique_id()
	if shadow_id.begins_with("massshadow_%d_" % my_id_sp):
		var ms_slot = _get_mass_shadow_slot()
		if ms_slot != null:
			ms_slot._active_count += 1
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

func _on_trap_spawned(trap_id: String, caster_peer_id: int, pos: Vector2, trap_type: String) -> void:
	if _trap_visuals.has(trap_id):
		if is_instance_valid(_trap_visuals[trap_id]):
			_trap_visuals[trap_id].queue_free()
		_trap_visuals.erase(trap_id)
	var script = load("res://scripts/trap_visual_base.gd")
	if script == null:
		return
	var visual = Node2D.new()
	visual.set_script(script)
	visual.trap_id        = trap_id
	visual.caster_peer_id = caster_peer_id
	visual.trap_type      = trap_type
	visual.global_position = pos
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(visual)
		_trap_visuals[trap_id] = visual

func _on_trap_despawned(trap_id: String, triggered: bool) -> void:
	var visual = _trap_visuals.get(trap_id, null)
	if visual and is_instance_valid(visual):
		if triggered:
			visual.play_trigger_effect()
		else:
			visual.play_expire_effect()
	_trap_visuals.erase(trap_id)

func _on_ability_visual(target_id_str: String, visual_id: String, extra: Vector2 = Vector2.ZERO) -> void:
	var node: Node = null
	# Try remote enemy dict first (keyed by enemy_id string e.g. "wolf_0")
	if remote_enemy_nodes.has(target_id_str):
		node = remote_enemy_nodes[target_id_str]
	# Try remote player by peer_id
	if node == null:
		var tpid = target_id_str.to_int()
		if remote_player_nodes.has(tpid):
			node = remote_player_nodes[tpid]
	# Try local player
	if node == null:
		var lp = get_tree().get_first_node_in_group("local_player")
		if lp and str(Network.get_my_id()) == target_id_str:
			node = lp
	if node == null or not is_instance_valid(node):
		return
	match visual_id:
		"strangle":
			if node.has_method("flash_visual"):
				node.flash_visual("strangle")
		"gentle_fist", "palms_burst":
			if node.has_method("flash_visual"):
				node.flash_visual("gentle_fist")
		"air_palm":
			if node.has_method("flash_visual"):
				node.flash_visual("air_palm")
		"fire_burst":
			if node.has_method("flash_visual"):
				node.flash_visual("fire_burst")
			ParticleBurst.spawn(get_tree(), node.global_position, "fire_burst")
		"bug_hit":
			if node.has_method("flash_visual"):
				node.flash_visual("bug_hit")
			ParticleBurst.spawn(get_tree(), node.global_position, "bug_hit")
		"bug_swarm_cast":
			var aim_vec = extra if extra != Vector2.ZERO else Vector2.DOWN
			if aim_vec == Vector2.ZERO and node and node.has_method("_facing_vec"):
				aim_vec = node._facing_vec()
			var swarm_script = load("res://scripts/bug_swarm_visual.gd")
			if swarm_script:
				var vis = Node2D.new()
				vis.set_script(swarm_script)
				vis.direction    = aim_vec
				vis.caster_node  = node
				if "locked_target" in node and is_instance_valid(node.locked_target):
					vis.target_node = node.locked_target
				vis.global_position = node.global_position
				get_tree().current_scene.add_child(vis)
			else:
				ParticleBurst.spawn(get_tree(), node.global_position, "bug_swarm", aim_vec)
		"hive_burst_cast":
			if node.has_method("flash_visual"):
				node.flash_visual("hive_burst_cast")
			ParticleBurst.spawn(get_tree(), node.global_position, "hive_burst")
		"bug_cloak_start":
			if node.has_method("flash_visual"):
				node.flash_visual("bug_cloak_start")
			ParticleBurst.spawn(get_tree(), node.global_position, "bug_cloak_on")
		"bug_cloak_end":
			if node.has_method("flash_visual"):
				node.flash_visual("bug_cloak_end")
		"rooted_start":
			if node.has_method("flash_visual"):
				node.flash_visual("rooted_start")
		"rooted_end":
			if node.has_method("flash_visual"):
				node.flash_visual("rooted_end")
		"rotation_start":
			if node.has_method("flash_visual"):
				node.flash_visual("rotation_start")
		"rotation_end":
			if node.has_method("flash_visual"):
				node.flash_visual("rotation_end")
		"gentle_fist_cast", "air_palm_cast", "fire_burst_cast", \
		"medical_start", "medical_tick", "sub_primed", "sub_triggered", \
		"charging_start", "charging_stop", "bug_swarm_cast", "hive_burst_cast", \
		"bug_cloak_start", "bug_cloak_end", "bug_hit":
			if node.has_method("flash_visual"):
				node.flash_visual(visual_id)
		"byakugan_off":
			# Server drained byakugan to 0 — force deactivate on the caster's client.
			# node is already resolved to local player or remote player.
			var lp = get_tree().get_first_node_in_group("local_player")
			if lp and str(Network.get_my_id()) == target_id_str:
				# This is us — force-cancel byakugan on our hotbar
				if lp.hotbar != null:
					for slot in lp.hotbar.slots:
						if slot != null and slot.has_method("is_active") and slot.is_active():
							if slot.get("ability_id") == "byakugan" or slot.get("ability_name") == "Byakugan":
								slot.force_cancel()
								break
			else:
				# Remote player: just remove the visual tint (byakugan_state handles this already
				# but this is a fallback for the force-off path)
				var gs_byakugan_state: Signal = Network.byakugan_state_received
				if gs_byakugan_state.is_connected(_on_byakugan_state):
					_on_byakugan_state(target_id_str.to_int(), false)

func _on_shadow_despawned(shadow_id: String, hit: bool) -> void:
	var is_clear  = shadow_id.ends_with("_clear")
	var lookup_id = shadow_id.trim_suffix("_clear")
	var visual    = _shadow_visuals.get(lookup_id, null)

	if is_clear:
		# Shadow ended after catch (cancel/chakra empty) — fade frozen line, end ability
		if visual and is_instance_valid(visual):
			visual.play_despawn_effect()
		_shadow_visuals.erase(lookup_id)
		_remove_shadow_circles(lookup_id)
		_shadow_force_cancel(lookup_id)
		var my_id_cl = multiplayer.get_unique_id()
		if lookup_id.begins_with("massshadow_%d_" % my_id_cl):
			var ms_slot_cl = _get_mass_shadow_slot()
			if ms_slot_cl != null:
				ms_slot_cl._active_count = max(0, ms_slot_cl._active_count - 1)
				var meta_cl = _shadow_meta.get(lookup_id, {})
				var tid_cl: String = meta_cl.get("target_id_str", "")
				ms_slot_cl.caught_target_ids.erase(tid_cl)
		return

	if hit:
		# Caught — freeze line, keep draining (force_cancel fires on _clear)
		if visual and is_instance_valid(visual):
			visual.play_hit_effect()
		_spawn_shadow_circles(lookup_id)
		var my_id_hit = multiplayer.get_unique_id()
		if lookup_id.begins_with("massshadow_%d_" % my_id_hit):
			var ms_slot_hit = _get_mass_shadow_slot()
			if ms_slot_hit != null:
				var meta_hit = _shadow_meta.get(lookup_id, {})
				var tid_hit: String = meta_hit.get("target_id_str", "")
				if tid_hit != "" and not ms_slot_hit.caught_target_ids.has(tid_hit):
					ms_slot_hit.caught_target_ids.append(tid_hit)
	else:
		# Missed or cancelled before catch — fade line, end ability now
		if visual and is_instance_valid(visual):
			visual.play_despawn_effect()
		_shadow_visuals.erase(lookup_id)
		_remove_shadow_circles(lookup_id)
		_shadow_force_cancel(lookup_id)
		var my_id_ms = multiplayer.get_unique_id()
		if lookup_id.begins_with("massshadow_%d_" % my_id_ms):
			var ms_slot_ms = _get_mass_shadow_slot()
			if ms_slot_ms != null:
				ms_slot_ms._active_count = max(0, ms_slot_ms._active_count - 1)

func _spawn_shadow_circles(shadow_id: String) -> void:
	var circles: Array = []
	var meta = _shadow_meta.get(shadow_id, {})
	var caster_peer: int  = meta.get("caster_peer_id", -1)
	var target_str: String = meta.get("target_id_str", "")
	var my_id = multiplayer.get_unique_id()

	# Caster node — local player if we are the caster, else remote player node
	var caster_node = null
	if caster_peer == my_id:
		caster_node = _get_local_player()
	else:
		caster_node = remote_player_nodes.get(caster_peer, null)
	if caster_node and is_instance_valid(caster_node):
		var c = _make_shadow_circle(caster_node)
		if c: circles.append(c)

	# Target node — local player, remote player, or enemy
	var target_node = null
	if target_str.begins_with("player_"):
		var tpid = int(target_str.trim_prefix("player_"))
		if tpid == my_id:
			target_node = _get_local_player()
		else:
			target_node = remote_player_nodes.get(tpid, null)
	else:
		# Enemy IDs are stored directly e.g. "wolf_0" — try with and without "enemy_" prefix
		var eid_str = target_str.trim_prefix("enemy_")
		if remote_enemy_nodes.has(target_str):
			target_node = remote_enemy_nodes[target_str]
		elif remote_enemy_nodes.has(eid_str):
			target_node = remote_enemy_nodes[eid_str]
	if target_node and is_instance_valid(target_node):
		var c2 = _make_shadow_circle(target_node)
		if c2: circles.append(c2)

	_shadow_circles[shadow_id] = circles

func _make_shadow_circle(parent: Node) -> Node2D:
	if not is_instance_valid(parent):
		return null
	# Use a pre-baked ellipse via a scaled ColorRect with circular shader
	var c = Node2D.new()
	c.z_index = -1
	var rect  = ColorRect.new()
	rect.color          = Color(0.0, 0.0, 0.0, 0.0)  # transparent base
	rect.size           = Vector2(36, 14)
	rect.position       = Vector2(-18, -7)
	var mat    = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = dot(uv, uv);
	COLOR = vec4(0.0, 0.0, 0.0, 0.55 * step(d, 1.0));
}
"""
	mat.shader  = shader
	rect.material = mat
	c.add_child(rect)
	parent.add_child(c)
	return c

func _remove_shadow_circles(shadow_id: String) -> void:
	if not _shadow_circles.has(shadow_id):
		return
	for c in _shadow_circles[shadow_id]:
		if is_instance_valid(c):
			c.queue_free()
	_shadow_circles.erase(shadow_id)
	_shadow_meta.erase(shadow_id)

func _shadow_force_cancel(lookup_id: String) -> void:
	var lp = _get_local_player()
	if lp == null:
		return
	var my_id = multiplayer.get_unique_id()
	if lookup_id == "shadow_%d" % my_id and lp.hotbar != null:
		for slot in lp.hotbar.slots:
			if slot != null and slot.has_method("force_cancel"):
				slot.force_cancel()
				break
	# Mass shadow: if ALL massshadow visuals for me are gone, force_cancel the mass shadow slot
	if lookup_id.begins_with("massshadow_%d_" % my_id):
		var prefix = "massshadow_%d_" % my_id
		var any_left = false
		for sid in _shadow_visuals:
			if sid.begins_with(prefix):
				any_left = true
				break
		if not any_left and lp.hotbar != null:
			for slot in lp.hotbar.slots:
				if slot != null and slot.ability_id == "mass_shadow" and slot.has_method("force_cancel"):
					slot.force_cancel()
					break

# ── C4 Karura Visuals ─────────────────────────────────────────────────────────

const C4_DOT_RADIUS:  float = 1.0
const C4_DRIFT_SPEED: float = 40.0
const C4_DRIFT_TIME:  float = 8.0
const C4_WOBBLE:      float = 0.8   # radians/sec max wobble

func _c4_generate_positions(origin: Vector2, seed_val: int, count: int) -> Array:
	const DRIFT_SPEED  = 40.0
	const DRIFT_TIME   = 8.0
	const MAX_DISTANCE = DRIFT_SPEED * DRIFT_TIME * 1.5
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	var positions: Array = []
	for i in range(count):
		var base_angle = (TAU / count) * i
		var jitter     = rng.randf_range(-0.18, 0.18)
		var angle      = base_angle + jitter
		var dir        = Vector2(cos(angle), sin(angle))
		var drift_dist = rng.randf_range(MAX_DISTANCE * 0.1, MAX_DISTANCE)
		positions.append(origin + dir * drift_dist)
	return positions

func _on_c4_spawn(swarm_id: String, origin: Vector2, seed_val: int, count: int, zone: String = "") -> void:
	var scene_root = get_tree().current_scene
	if scene_root == null:
		return
	if zone != "" and zone != current_zone:
		# Store entry with no dots so chain_explode can still erase it cleanly
		_c4_swarms[swarm_id] = {"origin": origin, "dots": [], "zone": zone}
		return

	var positions: Array = _c4_generate_positions(origin, seed_val, count)
	var dots: Array = []

	for i in range(count):
		var final_pos: Vector2 = positions[i]
		var dir        = (final_pos - origin).normalized()

		var dot             = Node2D.new()
		dot.z_index         = 3
		dot.global_position = origin
		scene_root.add_child(dot)

		var circle      = ColorRect.new()
		circle.size     = Vector2(C4_DOT_RADIUS * 2, C4_DOT_RADIUS * 2)
		circle.position = Vector2(-C4_DOT_RADIUS, -C4_DOT_RADIUS)
		circle.color    = Color(1.0, 0.4, 0.0, 0.9)
		dot.add_child(circle)

		var perp       = Vector2(-dir.y, dir.x)
		var wobble_amt = randf_range(-30.0, 30.0)
		var mid_pos    = origin + (final_pos - origin) * 0.5 + perp * wobble_amt
		var tween      = get_tree().create_tween()
		tween.tween_property(dot, "global_position", mid_pos, C4_DRIFT_TIME * 0.5).set_trans(Tween.TRANS_SINE)
		tween.tween_property(dot, "global_position", final_pos, C4_DRIFT_TIME * 0.5).set_trans(Tween.TRANS_SINE)

		dots.append(dot)

	_c4_swarms[swarm_id] = { "dots": dots, "origin": origin, "seed_val": seed_val, "count": count }

func _on_c4_chain_explode(swarm_id: String, seed_val: int, count: int, dot_delay: float = 0.01, zone: String = "") -> void:
	var entry = _c4_swarms.get(swarm_id, null)
	var dots: Array = entry["dots"] if entry != null else []
	var origin: Vector2  = entry["origin"] if entry != null else Vector2.ZERO
	_c4_swarms.erase(swarm_id)
	# Skip explosion visuals if this swarm belongs to a different zone
	if zone != "" and zone != current_zone:
		for dot in dots:
			if is_instance_valid(dot): dot.queue_free()
		return

	var positions: Array = _c4_generate_positions(origin, seed_val, count)
	var indices = range(positions.size())
	indices.shuffle()
	for i in range(indices.size()):
		var idx: int     = indices[i]
		var pos: Vector2 = positions[idx]
		var dot          = dots[idx] if idx < dots.size() else null
		get_tree().create_timer(i * dot_delay).timeout.connect(func() -> void:
			if dot != null and is_instance_valid(dot):
				dot.queue_free()
			_spawn_explosion(pos, 1.0)
		, CONNECT_ONE_SHOT)
