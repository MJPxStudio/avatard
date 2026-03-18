extends Node

const DungeonData       = preload("res://scripts/dungeon_data.gd")
const FloorController   = preload("res://scripts/dungeon_floor_controller.gd")
const WolfDenData       = preload("res://scripts/wolf_den_data.gd")

# ============================================================
# DUNGEON MANAGER (server-side)
#
# Instance lifecycle:
#   pending  → ready check in progress outside portal
#   active   → locked, run in progress
#   complete → all waves cleared (exit allowed)
#
# Ready check:
#   Any party member near portal initiates.
#   Requires min 1 player ready to launch (solo-friendly).
#   All ready → 3s countdown → teleport all in → lock.
#
# Death:
#   Player marked is_ghost on server.
#   Ghosts stay in dungeon zone (receive syncs, can spectate).
#   Checkpoint (wave clear) revives all ghosts at wave spawn pos.
#   Full wipe (0 living players) → all kicked to village.
# ============================================================

# instance_id -> {
#   dungeon_id, zone_name, party_id,
#   players: Array[peer_id],       # everyone currently in zone
#   living: Array[peer_id],        # not is_ghost
#   ghosts: Array[peer_id],        # is_ghost
#   state: "pending"|"active"|"complete"
#   ready: Array[peer_id],         # ready-checked during pending
#   pending_peers: Array[peer_id], # who initiated/joined ready check (outside portal)
# }
var _instances:    Dictionary = {}
var _next_id:      int        = 1

# peer_id -> instance_id (set once they enter the zone)
var _peer_instance: Dictionary = {}

# peer_id -> instance_id (set during ready check, before zone enter)
var _peer_pending:  Dictionary = {}

# instance_id -> FloorController node
var _floor_controllers: Dictionary = {}

# Shared with server_main
var server_players: Dictionary = {}

# ── READY CHECK ────────────────────────────────────────────────────────────

func initiate_ready_check(peer_id: int, dungeon_id: String, difficulty: String = "easy") -> Dictionary:
	# Returns { ok, error, instance_id }
	var def = DungeonData.get_dungeon(dungeon_id)
	if def.is_empty():
		return { "ok": false, "error": "Unknown dungeon." }

	var sp = server_players.get(peer_id, null)
	if not sp:
		return { "ok": false, "error": "Player not found." }

	if sp.level < def.get("min_level", 1):
		return { "ok": false, "error": "Requires level %d." % def["min_level"] }

	# Already in a pending or active instance?
	if _peer_pending.has(peer_id) or _peer_instance.has(peer_id):
		return { "ok": false, "error": "Already in a dungeon or ready check." }

	if difficulty not in ["easy", "medium", "hard"]:
		difficulty = "easy"

	# Find an existing pending instance for this party
	var party_id = _get_party_id(peer_id)
	var inst_id  = _find_pending_instance(dungeon_id, party_id)

	if inst_id == -1:
		# Create new pending instance
		inst_id = _next_id
		_next_id += 1
		var base_zone = def.get("zone_name", dungeon_id)
		var inst_zone = base_zone + "_" + str(inst_id)
		_instances[inst_id] = {
			"dungeon_id":     dungeon_id,
			"zone_name":      inst_zone,
			"party_id":       party_id,
			"difficulty":     difficulty,
			"players":        [],
			"living":         [],
			"ghosts":         [],
			"state":          "pending",
			"ready":          [],
			"pending_peers":  [],
		}
		print("[DUNGEON] Created pending instance %d for '%s' difficulty=%s" % [inst_id, dungeon_id, difficulty])
	else:
		_instances[inst_id]["difficulty"] = difficulty

	var inst = _instances[inst_id]

	# Cap check
	if inst["pending_peers"].size() >= def.get("max_players", 4):
		return { "ok": false, "error": "Instance full." }

	if peer_id not in inst["pending_peers"]:
		inst["pending_peers"].append(peer_id)
	_peer_pending[peer_id] = inst_id

	# Auto-add all online party members to the ready check
	if party_id != -1:
		var sm = get_parent()
		for other_id in server_players.keys():
			if other_id == peer_id:
				continue
			var other_party = sm._party_in_party.get(other_id, -1) if sm else -1
			if other_party == party_id and other_id not in inst["pending_peers"]:
				var party_def = DungeonData.get_dungeon(dungeon_id)
				if inst["pending_peers"].size() < party_def.get("max_players", 4):
					inst["pending_peers"].append(other_id)
					_peer_pending[other_id] = inst_id
					var other_sp = server_players.get(other_id, null)
					print("[DUNGEON] Auto-added party member %s to ready check" % (other_sp.username if other_sp else str(other_id)))

	print("[DUNGEON] %s joined ready check for instance %d" % [sp.username, inst_id])
	_broadcast_ready_update(inst_id)
	return { "ok": true, "instance_id": inst_id }

func set_ready(peer_id: int, ready: bool) -> void:
	var inst_id = _peer_pending.get(peer_id, -1)
	if inst_id == -1:
		return
	var inst = _instances.get(inst_id, null)
	if not inst or inst["state"] != "pending":
		return

	if ready:
		if peer_id not in inst["ready"]:
			inst["ready"].append(peer_id)
	else:
		inst["ready"].erase(peer_id)

	_broadcast_ready_update(inst_id)

	# Launch if at least 1 player is ready (min 1 of max 4)
	# All pending peers must be ready (not just one)
	var all_ready = inst["pending_peers"].size() > 0
	for pid in inst["pending_peers"]:
		if pid not in inst["ready"]:
			all_ready = false
			break
	if all_ready:
		_begin_countdown(inst_id)

func cancel_ready_check(peer_id: int) -> void:
	var inst_id = _peer_pending.get(peer_id, -1)
	if inst_id == -1:
		return
	var inst = _instances.get(inst_id, null)
	if not inst or inst["state"] != "pending":
		return

	inst["pending_peers"].erase(peer_id)
	inst["ready"].erase(peer_id)
	_peer_pending.erase(peer_id)

	_broadcast_ready_update(inst_id)

	# Destroy instance if no one left in ready check
	if inst["pending_peers"].is_empty():
		_broadcast_ready_cancelled(inst_id, "Ready check cancelled.")
		_instances.erase(inst_id)
		print("[DUNGEON] Instance %d pending destroyed — empty" % inst_id)

# ── COUNTDOWN + LAUNCH ─────────────────────────────────────────────────────

func _begin_countdown(inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		return
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		for pid in inst["pending_peers"]:
			net.dungeon_launching.rpc_id(pid, 3.0)
	print("[DUNGEON] Instance %d launching in 3s" % inst_id)
	get_tree().create_timer(3.0).timeout.connect(
		func(): _launch_instance(inst_id), CONNECT_ONE_SHOT)

func _launch_instance(inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst or inst["state"] != "pending":
		return
	inst["state"] = "active"

	var dungeon_id = inst["dungeon_id"]
	var def        = DungeonData.get_dungeon(dungeon_id)
	var zone_name  = inst["zone_name"]
	var spawn      = def.get("spawn_pos", Vector2(0, 200))
	var net        = get_tree().root.get_node_or_null("Network")
	var sm         = get_parent()

	print("[DUNGEON] Launching instance %d — teleporting %d players" % [inst_id, inst["pending_peers"].size()])

	for pid in inst["pending_peers"].duplicate():
		var sp = server_players.get(pid, null)
		if not sp:
			continue
		sp.zone            = zone_name
		sp.world_pos       = spawn
		sp.global_position = spawn
		Network.players[pid]["zone"]     = zone_name
		Network.players[pid]["position"] = spawn
		inst["players"].append(pid)
		inst["living"].append(pid)
		_peer_instance[pid] = inst_id
		_peer_pending.erase(pid)
		if net:
			net.dungeon_enter_accepted.rpc_id(pid, dungeon_id, zone_name, spawn)

	inst["pending_peers"].clear()
	inst["ready"].clear()

	# Notify portal locked
	if net:
		net.dungeon_portal_locked.rpc(inst["dungeon_id"], true)

	# Start floor controller after clients load
	var fc              = FloorController.new()
	fc.instance_id      = inst_id
	fc.zone_name        = zone_name
	fc.party_peers      = inst["players"].duplicate()
	fc.difficulty       = inst.get("difficulty", "easy")
	fc.dungeon_level    = def.get("min_level", 1)
	var theme_script    = def.get("theme_script", "res://scripts/wolf_den_data.gd")
	fc.theme_data       = load(theme_script).new() if ResourceLoader.exists(theme_script) else WolfDenData.new()
	fc.total_floors     = fc.theme_data.FLOOR_COUNTS.get(fc.difficulty, 3)
	sm.add_child(fc)
	_floor_controllers[inst_id] = fc
	get_tree().create_timer(4.0).timeout.connect(
		func(): fc.start(), CONNECT_ONE_SHOT)

# ── DEATH / GHOST ──────────────────────────────────────────────────────────

func player_died(peer_id: int) -> void:
	var inst_id = _peer_instance.get(peer_id, -1)
	if inst_id == -1:
		return
	var inst = _instances.get(inst_id, null)
	if not inst:
		return

	inst["living"].erase(peer_id)
	if peer_id not in inst["ghosts"]:
		inst["ghosts"].append(peer_id)

	var sp = server_players.get(peer_id, null)
	if sp:
		sp.is_ghost = true

	print("[DUNGEON] %s became a ghost in instance %d. Living: %d" % [
		server_players.get(peer_id, {}).get("username", str(peer_id)),
		inst_id, inst["living"].size()])

	# Broadcast ghost state — everyone in instance sees the visual
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		for pid in inst["players"]:
			net.player_became_ghost.rpc_id(pid, peer_id)

	# Full wipe?
	if inst["living"].is_empty():
		print("[DUNGEON] Wipe! All players dead in instance %d" % inst_id)
		get_tree().create_timer(2.0).timeout.connect(
			func(): _wipe_instance(inst_id), CONNECT_ONE_SHOT)

func checkpoint_revive(inst_id: int, revive_pos: Vector2) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		return
	if inst["ghosts"].is_empty():
		return

	var revived: Array = []
	var net = get_tree().root.get_node_or_null("Network")

	for pid in inst["ghosts"].duplicate():
		var sp = server_players.get(pid, null)
		if not sp:
			continue
		sp.is_ghost    = false
		sp.hp          = max(1, sp.max_hp / 2)
		sp.world_pos   = revive_pos
		sp.global_position = revive_pos
		Network.players[pid]["position"] = revive_pos
		inst["living"].append(pid)
		revived.append(pid)

	inst["ghosts"].clear()

	if net:
		for pid in inst["players"]:
			net.checkpoint_revive.rpc_id(pid, revived, revive_pos)

	print("[DUNGEON] Checkpoint revived %d ghosts in instance %d" % [revived.size(), inst_id])

# ── WIPE ───────────────────────────────────────────────────────────────────

func _wipe_instance(inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		return

	var net = get_tree().root.get_node_or_null("Network")
	var def = DungeonData.get_dungeon(inst["dungeon_id"])
	var exit_scene = def.get("exit_scene", "res://scenes/village.tscn")
	var exit_pos   = def.get("exit_pos",   Vector2(40, 40))
	var exit_zone  = def.get("exit_zone",  "village")

	for pid in inst["players"].duplicate():
		var sp = server_players.get(pid, null)
		if sp:
			sp.is_ghost  = false
			sp.is_dead   = false
			sp.hp        = sp.max_hp
			sp.zone      = exit_zone
			sp.world_pos = exit_pos
			sp.global_position = exit_pos
			Network.players[pid]["zone"]     = exit_zone
			Network.players[pid]["position"] = exit_pos
		if net:
			net.dungeon_wiped.rpc_id(pid, exit_scene, exit_pos)

	# Unlock portal
	if net:
		net.dungeon_portal_locked.rpc(inst["dungeon_id"], false)

	_destroy_instance(inst_id)

# ── EXIT (voluntary, only when complete) ──────────────────────────────────

func player_exit(peer_id: int) -> void:
	if not _peer_instance.has(peer_id):
		return
	var inst_id = _peer_instance[peer_id]
	_remove_player(peer_id, inst_id)

func is_instance_complete(inst_id: int) -> bool:
	var inst = _instances.get(inst_id, null)
	if inst and inst["state"] == "complete":
		return true
	var fc = _floor_controllers.get(inst_id, null)
	return fc != null and is_instance_valid(fc) and fc._complete

func is_floor_boss_cleared(inst_id: int) -> bool:
	var fc = _floor_controllers.get(inst_id, null)
	if fc == null or not is_instance_valid(fc):
		return false
	return fc.is_current_floor_boss_cleared()

func on_dungeon_complete(inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		return
	inst["state"] = "complete"
	# Revive any remaining ghosts so they see the clear screen
	var fc = _floor_controllers.get(inst_id, null)
	var revive_pos = fc.revive_pos if fc else Vector2(0, 200)
	if not inst["ghosts"].is_empty():
		checkpoint_revive(inst_id, revive_pos)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.dungeon_portal_locked.rpc(inst["dungeon_id"], false)
		for pid in inst["players"]:
			net.notify_dungeon_complete.rpc_id(pid)
	# Auto-teleport all players to village entrance 30 seconds after clear
	get_tree().create_timer(30.0).timeout.connect(
		func(): _auto_exit_instance(inst_id), CONNECT_ONE_SHOT)

func _auto_exit_instance(inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		return
	var def        = DungeonData.get_dungeon(inst["dungeon_id"])
	var exit_scene = def.get("exit_scene", "res://scenes/village.tscn")
	var exit_pos   = def.get("exit_pos",   Vector2(40, 40))
	var exit_zone  = def.get("exit_zone",  "village")
	var net        = get_tree().root.get_node_or_null("Network")
	for pid in inst["players"].duplicate():
		var sp = server_players.get(pid, null)
		if sp:
			sp.is_ghost  = false
			sp.zone      = exit_zone
			sp.world_pos = exit_pos
			sp.global_position = exit_pos
			Network.players[pid]["zone"]     = exit_zone
			Network.players[pid]["position"] = exit_pos
		if net:
			net.dungeon_exit_accepted.rpc_id(pid, exit_scene, exit_pos)
	if net:
		net.dungeon_portal_locked.rpc(inst["dungeon_id"], false)
	_destroy_instance(inst_id)
	print("[DUNGEON] Instance %d auto-exited after completion." % inst_id)

# ── QUERY ──────────────────────────────────────────────────────────────────

func on_enemy_killed(enemy_id: String, zone: String) -> void:
	for iid in _instances:
		if _instances[iid]["zone_name"] == zone:
			var fc = _floor_controllers.get(iid, null)
			if fc:
				fc.on_enemy_killed(enemy_id)
			return

func get_instance_id_for_peer(peer_id: int) -> int:
	return _peer_instance.get(peer_id, -1)

func get_instance_id_for_zone(zone: String) -> int:
	for iid in _instances:
		if _instances[iid]["zone_name"] == zone:
			return iid
	return -1

func peer_is_in_dungeon(peer_id: int) -> bool:
	return _peer_instance.has(peer_id)

func peer_is_in_ready_check(peer_id: int) -> bool:
	return _peer_pending.has(peer_id)

func player_disconnected(peer_id: int) -> void:
	cancel_ready_check(peer_id)
	player_exit(peer_id)

# ── INTERNAL ───────────────────────────────────────────────────────────────

func _get_party_id(peer_id: int) -> int:
	var sm = get_parent()
	return sm._party_in_party.get(peer_id, -1) if sm and "_party_in_party" in sm else -1

func _find_pending_instance(dungeon_id: String, party_id: int) -> int:
	if party_id == -1:
		return -1  # Solo always gets own instance
	for iid in _instances:
		var inst = _instances[iid]
		if inst["dungeon_id"] == dungeon_id and inst["party_id"] == party_id and inst["state"] == "pending":
			return iid
	return -1

func _broadcast_ready_update(inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		return
	var members: Array = []
	for pid in inst["pending_peers"]:
		var sp = server_players.get(pid, null)
		members.append({
			"peer_id":  pid,
			"username": sp.username if sp else str(pid),
			"ready":    pid in inst["ready"],
		})
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		for pid in inst["pending_peers"]:
			net.ready_check_update.rpc_id(pid, members, inst["dungeon_id"])

func _broadcast_ready_cancelled(inst_id: int, reason: String) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		return
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		for pid in inst["pending_peers"]:
			net.ready_check_cancelled.rpc_id(pid, reason)

func _remove_player(peer_id: int, inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		_peer_instance.erase(peer_id)
		return
	inst["players"].erase(peer_id)
	inst["living"].erase(peer_id)
	inst["ghosts"].erase(peer_id)
	_peer_instance.erase(peer_id)
	var sp = server_players.get(peer_id, null)
	if sp:
		sp.is_ghost = false
		# Reset all dungeon boon properties
		sp.boon_chakra_cost_mult       = 1.0
		sp.boon_clay_dmg_mult          = 1.0
		sp.boon_c1_damage_flat         = 0
		sp.boon_c1_speed_mult          = 1.0
		sp.boon_c1_range_mult          = 1.0
		sp.boon_c1_cooldown_flat       = 0.0
		sp.boon_c1_spider_count        = 1
		sp.boon_c2_cooldown_flat       = 0.0
		sp.boon_c2_orbit_duration_flat = 0.0
		sp.boon_c2_drop_interval_mult  = 1.0
		sp.boon_c2_explosion_mult      = 1.0
		sp.boon_c2_owl_count           = 1
		sp.boon_c3_cooldown_flat       = 0.0
		sp.boon_c3_radius_mult         = 1.0
		sp.boon_c4_count_flat          = 0
		sp.boon_c4_dmg_mult            = 1.0
		sp.boon_c4_radius_mult         = 1.0
		sp.dungeon_passives            = []
	print("[DUNGEON] Player %d exited instance %d. Remaining: %d" % [
		peer_id, inst_id, inst["players"].size()])
	if inst["players"].is_empty():
		_destroy_instance(inst_id)

func _destroy_instance(inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		return
	for pid in inst["players"].duplicate():
		_peer_instance.erase(pid)
	for pid in inst["pending_peers"].duplicate():
		_peer_pending.erase(pid)
	_instances.erase(inst_id)
	if _floor_controllers.has(inst_id):
		var fc = _floor_controllers[inst_id]
		if is_instance_valid(fc):
			fc.queue_free()
		_floor_controllers.erase(inst_id)
	print("[DUNGEON] Instance %d destroyed." % inst_id)

func player_chose_boon(peer_id: int, boon_id: String) -> void:
	var inst_id = _peer_instance.get(peer_id, -1)
	if inst_id == -1:
		return
	var fc = _floor_controllers.get(inst_id, null)
	if fc:
		fc.player_chose_boon(peer_id, boon_id)

func player_move_to_room(peer_id: int, room_id: int, reward_type: int = -1) -> void:
	var inst_id = _peer_instance.get(peer_id, -1)
	if inst_id == -1:
		return
	var fc = _floor_controllers.get(inst_id, null)
	if fc:
		fc.player_move_to_room(peer_id, room_id, reward_type)
