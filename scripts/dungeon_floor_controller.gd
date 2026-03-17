extends Node

# ============================================================
# DUNGEON FLOOR CONTROLLER (server-side)
# Manages room-by-room progression through a generated floor
# Replaces dungeon_wave_controller.gd
# ============================================================

const Generator = preload("res://scripts/dungeon_generator.gd")
const BoonDB    = preload("res://scripts/dungeon_boon_db.gd")
const RoomDB    = preload("res://scripts/dungeon_room_db.gd")

signal floor_complete(instance_id: int, floor_index: int)
signal dungeon_complete(instance_id: int)

var instance_id:   int     = -1
var zone_name:     String  = ""
var party_peers:   Array   = []
var difficulty:    String  = "easy"
var dungeon_level: int     = 1
var _pending_reward: Dictionary = {}  # peer_id -> reward_type for next room entry
var _door_votes:      Dictionary = {}  # peer_id -> {room_id, reward_type} — waiting for all party
var theme_data             = null   # e.g. WolfDenData
var total_floors:  int     = 3

var _current_floor:   int        = 0
var _floor_layout:    Dictionary = {}
var _current_room_id: int        = -1
var _room_enemies:    Array      = []   # enemy_ids alive in current room
var _started:         bool       = false
var _complete:        bool       = false
var _floor_transitioning: bool   = false  # prevents double floor-advance on multiplayer door press
var _awaiting_boon:   bool       = false
var _held_boons:      Dictionary = {}   # peer_id -> Array[boon_id]

# Revive position — updated each room clear
var revive_pos: Vector2 = Vector2(0, 200)

func start() -> void:
	if _started:
		return
	_started = true
	_start_floor(_current_floor)
	_enter_first_room()   # floor 1: enter immediately, no door to press

# ── Floor management ──────────────────────────────────────────

func _start_floor(floor_idx: int) -> void:
	_current_floor   = floor_idx
	_floor_layout    = Generator.generate_floor(difficulty, floor_idx, theme_data, dungeon_level)
	_current_room_id = _floor_layout["start_id"]

	# ── DEBUG: dump full layout so we can see what was generated ──────────
	print("[DUNGEON] ===== FLOOR %d LAYOUT (instance %d) =====" % [floor_idx + 1, instance_id])
	print("[DUNGEON]   start_id=%d  boss_id=%d  treasure_id=%d  total_rooms=%d" % [
		_floor_layout["start_id"], _floor_layout["boss_id"],
		_floor_layout.get("treasure_id", -1), _floor_layout["rooms"].size()])
	for rid in _floor_layout["rooms"]:
		var r = _floor_layout["rooms"][rid]
		print("[DUNGEON]   room %d  type=%d(%s)  safe=%s  connections=%s  cleared=%s" % [
			rid, r["type"], r["label"], str(r.get("safe", false)),
			str(r["connections"]), str(r["cleared"])])
	print("[DUNGEON] ================================================")

	# Broadcast floor start to all players
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		var room_count = _floor_layout["rooms"].size()
		for pid in party_peers:
			net.dungeon_floor_start.rpc_id(pid, floor_idx + 1, total_floors, room_count, difficulty)

	# Mark START room cleared silently — entry handled by _enter_first_room()
	var start_id   = _floor_layout["start_id"]
	var start_room = _floor_layout["rooms"].get(start_id, {})
	start_room["cleared"] = true
	# NOTE: does NOT call _enter_room. _enter_first_room() does that.

func _enter_first_room() -> void:
	_floor_transitioning = false
	var start_id   = _floor_layout["start_id"]
	var start_room = _floor_layout["rooms"].get(start_id, {})
	var forward    = start_room.get("connections", [])
	var first_id   = forward[0] if not forward.is_empty() else start_id
	_enter_room(first_id)

func _enter_room(room_id: int) -> void:
	var room = _floor_layout["rooms"].get(room_id, {})
	if room.is_empty():
		return
	if room_id == _current_room_id and _current_room_id != -1:
		push_warning("[DUNGEON] _enter_room called for already-current room %d — ignored" % room_id)
		return

	_current_room_id = room_id
	_room_enemies.clear()

	# Update room ID on each party server player so ability bleed checks work
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm:
		for pid in party_peers:
			var sp = sm.server_players.get(pid, null)
			if sp:
				sp.dungeon_room_id = room_id

	print("[DUNGEON] Instance %d entering room %d (%s)" % [
		instance_id, room_id, room.get("label", "?")])

	# Compute 1-based position in the player-visible path (excludes START room).
	# room_order = [start, r1, r2, ..., boss, treasure]
	# Player sees rooms starting from index 1 (first after start).
	var room_order    = _floor_layout.get("room_order", [])
	var path_index    = room_order.find(room_id)   # 0-based index in full order
	var display_num   = max(1, path_index)          # start=0 → clamp to 1, others natural
	var display_total = max(1, room_order.size() - 1) # exclude START from total

	# Broadcast room info to players
	var net = get_tree().root.get_node_or_null("Network")
	var connections = room.get("connections", [])
	var room_type   = room.get("type", RoomDB.RoomType.COMBAT)

	if net:
		for pid in party_peers:
			net.dungeon_room_enter.rpc_id(pid, room_id, room.get("label", "Room"),
				room_type, connections, _current_floor + 1,
				room.get("tiles_w", 28), room.get("tiles_h", 19),
				Vector2.ZERO)  # always spawn at room centre
		# Always send wave start so HUD Room X/Y updates for every room type
		for pid in party_peers:
			net.notify_wave_start.rpc_id(pid, display_num, display_total,
				room.get("label", "Room"))

	# Safe rooms — auto clear immediately
	if room.get("safe", false) or room_type == RoomDB.RoomType.START:
		_clear_room(room_id)
		return

	# Boss room
	if room_type == RoomDB.RoomType.BOSS:
		_spawn_boss(room_id)
		return

	# Combat rooms — spawn enemies from point budget
	_spawn_room_enemies(room_id)

func _spawn_room_enemies(room_id: int) -> void:
	var room    = _floor_layout["rooms"].get(room_id, {})
	var spawns  = room.get("spawns", [])
	var sm      = get_tree().root.get_node_or_null("ServerMain")
	if not sm:
		return

	# Calculate scaling multipliers for this difficulty and floor
	var scaling    = theme_data.ENEMY_SCALING.get(difficulty, theme_data.ENEMY_SCALING["easy"])
	var floor_hp   = pow(theme_data.FLOOR_HP_SCALE,  _current_floor)
	var floor_dmg  = pow(theme_data.FLOOR_DMG_SCALE, _current_floor)
	var hp_mult    = scaling["hp"]    * floor_hp
	var dmg_mult   = scaling["dmg"]   * floor_dmg
	var speed_mult = scaling["speed"]
	var aggro_mult = scaling["aggro"]

	var spawn_positions = _get_spawn_positions(spawns.size())

	for i in range(spawns.size()):
		var entry    = spawns[i]
		var enemy_id = "%s_%d_r%d_e%d" % [zone_name, instance_id, room_id, i]
		var pos      = spawn_positions[i] if i < spawn_positions.size() else Vector2(0, 0)
		sm.spawn_dungeon_enemy(enemy_id, entry.get("script", ""), pos, zone_name, hp_mult, dmg_mult, speed_mult, aggro_mult)
		_room_enemies.append(enemy_id)

	# Send roster to clients
	for pid in party_peers:
		sm._send_enemy_roster(pid, zone_name)

	revive_pos = spawn_positions[0] if spawn_positions.size() > 0 else Vector2(0, 200)

	# If nothing spawned (empty budget), clear immediately
	if _room_enemies.is_empty():
		_clear_room(room_id)
		return

func _spawn_boss(room_id: int) -> void:
	var sm   = get_tree().root.get_node_or_null("ServerMain")
	if not sm:
		return
	var boss_def = theme_data.BOSSES.get(difficulty, {})
	if boss_def.is_empty():
		return

	var enemy_id = "%s_%d_boss" % [zone_name, instance_id]
	sm.spawn_dungeon_enemy(enemy_id, boss_def.get("script", ""), Vector2(0, -100), zone_name)
	_room_enemies.append(enemy_id)
	revive_pos = Vector2(0, 0)

	# Apply boss scaling — use boss_def multipliers × difficulty scaling × floor scaling
	var enemy_node = sm._enemy_nodes.get(enemy_id, null)
	if enemy_node and enemy_node.has_method("apply_dungeon_scaling"):
		var scaling   = theme_data.ENEMY_SCALING.get(difficulty, theme_data.ENEMY_SCALING["easy"])
		var floor_hp  = pow(theme_data.FLOOR_HP_SCALE, _current_floor)
		var floor_dmg = pow(theme_data.FLOOR_DMG_SCALE, _current_floor)
		enemy_node.apply_dungeon_scaling(
			boss_def.get("hp_mult", 1.0) * scaling["hp"]  * floor_hp,
			boss_def.get("dmg_mult", 1.0) * scaling["dmg"] * floor_dmg,
			scaling["speed"] * 0.85,   # bosses slightly slower but hit harder
			scaling["aggro"] * 1.2     # bosses are extra aggressive
		)

	var net = get_tree().root.get_node_or_null("Network")
	for pid in party_peers:
		sm._send_enemy_roster(pid, zone_name)
		if net:
			net.notify_boss_phase.rpc_id(pid, boss_def.get("label", "Boss"), 1, "")

func _get_spawn_positions(count: int) -> Array:
	# Spread enemies in the top half of the room — away from the bottom entrance
	var positions = []
	for i in range(count):
		var angle = (TAU / count) * i + randf() * 0.3
		var dist  = randf_range(80, 180)
		var pos   = Vector2(cos(angle) * dist, sin(angle) * dist)
		# Push into the upper portion (negative Y = up)
		pos.y = -abs(pos.y) - 40.0
		positions.append(pos)
	return positions

# ── Enemy killed ─────────────────────────────────────────────

func on_enemy_killed(enemy_id: String) -> void:
	if not _started or _complete:
		return
	_room_enemies.erase(enemy_id)
	if _room_enemies.is_empty():
		_clear_room(_current_room_id)

func _clear_room(room_id: int) -> void:
	var room = _floor_layout["rooms"].get(room_id, null)
	if room == null or room.get("cleared", false):
		return
	room["cleared"] = true

	print("[DUNGEON] Instance %d room %d cleared" % [instance_id, room_id])

	# Revive ghosts on room clear
	var dm = _get_dungeon_manager()
	if dm:
		dm.checkpoint_revive(instance_id, revive_pos)

	# Check if this was the boss room — door goes to treasure room, not floor exit
	if room_id == _floor_layout.get("boss_id", -1):
		var treasure_id = _floor_layout.get("treasure_id", -1)
		var boss_conn   = [treasure_id] if treasure_id >= 0 else []
		print("[DUNGEON] Boss cleared! room_id=%d → treasure_id=%d floor=%d/%d" % [
			room_id, treasure_id, _current_floor + 1, total_floors])
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			for pid in party_peers:
				net.dungeon_room_cleared.rpc_id(pid, room_id, boss_conn)
		_deliver_pending_rewards()
		return

	# Check if this was the treasure room — now trigger floor exit
	if room_id == _floor_layout.get("treasure_id", -1):
		var is_last_floor: bool = (_current_floor + 1 >= total_floors)
		# Last floor: no door — 30s auto-exit via dungeon_manager handles transport
		# Mid floor: show Next Floor door
		var exit_conn: Array = [] if is_last_floor else [-2]
		print("[DUNGEON] Treasure cleared! floor=%d/%d is_last=%s sending=%s" % [
			_current_floor + 1, total_floors, str(is_last_floor), str(exit_conn)])
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			for pid in party_peers:
				net.dungeon_room_cleared.rpc_id(pid, room_id, exit_conn)
		_on_floor_complete()
		return

	# Broadcast room cleared — tell clients what doors and rewards are available
	var connections  = room.get("connections", [])
	var door_rewards = room.get("door_rewards", {})
	var next_room    = room.get("next_room_id", connections[0] if not connections.is_empty() else -1)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		for pid in party_peers:
			net.dungeon_room_cleared.rpc_id(pid, room_id, connections, door_rewards)

	# Deliver pending reward for each player who chose a door to get here
	_deliver_pending_rewards()

func _on_floor_complete() -> void:
	print("[DUNGEON] Instance %d floor %d complete!" % [instance_id, _current_floor + 1])
	floor_complete.emit(instance_id, _current_floor)

	if _current_floor + 1 >= total_floors:
		_on_dungeon_complete()
		return
	# Boons are now delivered per-room via _deliver_pending_rewards on room clear

func _deliver_pending_rewards() -> void:
	if _pending_reward.is_empty():
		return
	var net = get_tree().root.get_node_or_null("Network")
	var sm  = get_tree().root.get_node_or_null("ServerMain")
	for pid in _pending_reward:
		var reward = _pending_reward[pid]
		match reward:
			RoomDB.RewardType.BOON:
				if net:
					var held  = _held_boons.get(pid, [])
					var offer = BoonDB.get_random_boons(BoonDB.BOONS_OFFERED, held, dungeon_level)
					if not offer.is_empty():
						net.dungeon_boon_offer.rpc_id(pid, offer)
			RoomDB.RewardType.UPGRADE:
				if net:
					var held    = _held_boons.get(pid, [])
					var offer: Array
					if held.is_empty():
						# No boons held — treat as a regular boon offer instead
						offer = BoonDB.get_random_boons(BoonDB.BOONS_OFFERED, [], dungeon_level)
					else:
						offer = BoonDB.get_upgrade_boons(BoonDB.BOONS_OFFERED, held)
					if not offer.is_empty():
						net.dungeon_boon_offer.rpc_id(pid, offer)
			RoomDB.RewardType.REST:
				if sm and sm.server_players.has(pid):
					var sp = sm.server_players[pid]
					sp.hp             = min(sp.hp + int(sp.max_hp * 0.4), sp.max_hp)
					sp.current_chakra = min(sp.current_chakra + int(sp.max_chakra * 0.4), sp.max_chakra)
					if net:
						net.dungeon_rest_healed.rpc_id(pid, sp.hp, sp.max_hp, sp.current_chakra, sp.max_chakra)
			RoomDB.RewardType.GOLD, RoomDB.RewardType.RESOURCES, RoomDB.RewardType.SHOP:
				if net:
					net.dungeon_reward_room.rpc_id(pid, reward)
	_pending_reward.clear()

func player_chose_boon(peer_id: int, boon_id: String) -> void:
	var boon = BoonDB.get_boon(boon_id)
	if boon.is_empty():
		return
	if not _held_boons.has(peer_id):
		_held_boons[peer_id] = []
	# Enforce max stacks cap (unlimited for max_hp and max_chakra)
	var boon_stat = boon.get("stat", "")
	if boon_stat not in ["max_hp", "max_chakra"]:
		var current_count = _held_boons[peer_id].count(boon_id)
		if current_count >= BoonDB.MAX_BOON_STACKS:
			return
	_held_boons[peer_id].append(boon_id)
	var sm = get_tree().root.get_node_or_null("ServerMain")
	var net = get_tree().root.get_node_or_null("Network")
	if sm and sm.server_players.has(peer_id):
		_apply_boon_to_player(sm.server_players[peer_id], boon)
		var sp = sm.server_players[peer_id]
		if net:
			# Sync max stats
			net.dungeon_stat_sync.rpc_id(peer_id, sp.max_hp, sp.max_chakra)
			# Push all boon_* properties so client ability scripts can read them
			var props: Dictionary = {
				"boon_chakra_cost_mult":       sp.boon_chakra_cost_mult,
				"boon_clay_dmg_mult":          sp.boon_clay_dmg_mult,
				"boon_c1_damage_flat":         sp.boon_c1_damage_flat,
				"boon_c1_speed_mult":          sp.boon_c1_speed_mult,
				"boon_c1_range_mult":          sp.boon_c1_range_mult,
				"boon_c1_cooldown_flat":       sp.boon_c1_cooldown_flat,
				"boon_c1_spider_count":        sp.boon_c1_spider_count,
				"boon_c2_cooldown_flat":       sp.boon_c2_cooldown_flat,
				"boon_c2_orbit_duration_flat": sp.boon_c2_orbit_duration_flat,
				"boon_c2_drop_interval_mult":  sp.boon_c2_drop_interval_mult,
				"boon_c2_explosion_mult":      sp.boon_c2_explosion_mult,
				"boon_c2_owl_count":           sp.boon_c2_owl_count,
				"boon_c3_cooldown_flat":       sp.boon_c3_cooldown_flat,
				"boon_c3_radius_mult":         sp.boon_c3_radius_mult,
				"boon_c4_count_flat":          sp.boon_c4_count_flat,
				"boon_c4_dmg_mult":            sp.boon_c4_dmg_mult,
				"boon_c4_radius_mult":         sp.boon_c4_radius_mult,
				"dungeon_passives":            sp.dungeon_passives.duplicate(),
			}
			net.dungeon_boon_props.rpc_id(peer_id, props)
	if net:
		net.dungeon_boon_chosen.rpc_id(peer_id, boon_id, boon.get("name", ""))

func _apply_boon_to_player(sp, boon: Dictionary) -> void:
	var type = boon.get("type", "")
	match type:
		"stat":
			var stat  = boon.get("stat", "")
			var value = boon.get("value", 0)
			match stat:
				"max_hp":
					sp.max_hp  += value
					sp.hp       = min(sp.hp + value, sp.max_hp)
				"max_chakra":
					sp.max_chakra      += value
					sp.current_chakra   = min(sp.current_chakra + value, sp.max_chakra)
				"chakra_cost_mult":       sp.boon_chakra_cost_mult       += value
				"clay_dmg_mult":          sp.boon_clay_dmg_mult           += value
				"c1_damage_flat":         sp.boon_c1_damage_flat          += value
				"c1_speed_mult":          sp.boon_c1_speed_mult           += value
				"c1_range_mult":          sp.boon_c1_range_mult           += value
				"c1_cooldown_flat":       sp.boon_c1_cooldown_flat        += value
				"c1_spider_count":        sp.boon_c1_spider_count          = int(value)
				"c2_cooldown_flat":       sp.boon_c2_cooldown_flat        += value
				"c2_orbit_duration_flat": sp.boon_c2_orbit_duration_flat  += value
				"c2_drop_interval_mult":  sp.boon_c2_drop_interval_mult   += value
				"c2_explosion_mult":      sp.boon_c2_explosion_mult       += value
				"c2_owl_count":           sp.boon_c2_owl_count             = int(value)
				"c3_cooldown_flat":       sp.boon_c3_cooldown_flat        += value
				"c3_radius_mult":         sp.boon_c3_radius_mult          += value
				"c4_count_flat":          sp.boon_c4_count_flat           += int(value)
				"c4_dmg_mult":            sp.boon_c4_dmg_mult             += value
				"c4_radius_mult":         sp.boon_c4_radius_mult          += value
		"ability":
			if boon.get("ability") == "dash_charges":
				sp.dungeon_dash_bonus = (sp.dungeon_dash_bonus if "dungeon_dash_bonus" in sp else 0) + int(boon.get("value", 0))
		"passive":
			sp.dungeon_passives.append(boon.get("passive", ""))
		"double":
			for pair in boon.get("stats", []):
				_apply_boon_to_player(sp, {"type": "stat", "stat": pair[0], "value": pair[1]})

func _next_floor() -> void:
	_current_floor += 1
	_start_floor(_current_floor)
	# Does NOT call _enter_first_room — player presses the Next Floor door to trigger that

func _on_dungeon_complete() -> void:
	_complete = true
	var dm = _get_dungeon_manager()
	if dm:
		dm.on_dungeon_complete(instance_id)
	dungeon_complete.emit(instance_id)
	print("[DUNGEON] Instance %d — ALL FLOORS COMPLETE!" % instance_id)

# ── Player room transition ────────────────────────────────────

func player_move_to_room(peer_id: int, room_id: int, reward_type: int = -1) -> void:
	# -2 = player pressed the "Next Floor" door after boss/treasure clear
	if room_id == -2:
		var boss_id   = _floor_layout.get("boss_id", -1)
		var boss_room = _floor_layout["rooms"].get(boss_id, {})
		if not boss_room.get("cleared", false):
			return
		# Guard: only the first peer to press this triggers the transition
		if _floor_transitioning:
			return
		_floor_transitioning = true
		if _current_floor + 1 < total_floors:
			_next_floor()
			_enter_first_room()
		else:
			# Last floor already complete — dungeon_complete was sent, just ignore
			pass
		return

	# Validate — room must be connected to current and current must be cleared
	var current_room = _floor_layout["rooms"].get(_current_room_id, {})
	if not current_room.get("cleared", false):
		return
	if room_id not in current_room.get("connections", []):
		return

	# ── Lock-step door system ────────────────────────────────────────────────
	# Record this player's vote. The door only opens when ALL living party
	# members have pressed a door (they don't need to pick the same reward).
	_door_votes[peer_id] = {"room_id": room_id, "reward_type": reward_type}

	# Tell other party members this player is ready
	var net = get_tree().root.get_node_or_null("Network")
	var sm  = get_tree().root.get_node_or_null("ServerMain")
	var living = _get_living_peers(sm)
	if net:
		for pid in party_peers:
			var voted = _door_votes.keys()
			net.dungeon_door_vote.rpc_id(pid, peer_id, voted.size(), living.size())

	# Check if all living members have voted
	var all_voted = true
	for pid in living:
		if pid not in _door_votes:
			all_voted = false
			break

	if not all_voted:
		return

	# Everyone is ready — use the first voter's room_id (majority reward handled per-peer)
	var chosen_room = _door_votes.values()[0]["room_id"]
	# Apply each player's chosen reward
	for pid in _door_votes:
		var vote = _door_votes[pid]
		if vote["reward_type"] >= 0:
			_pending_reward[pid] = vote["reward_type"]
	_door_votes.clear()
	_enter_room(chosen_room)

func _get_living_peers(sm) -> Array:
	var living = []
	for pid in party_peers:
		if sm and sm.server_players.has(pid):
			var sp = sm.server_players[pid]
			if not sp.is_dead and not sp.is_ghost:
				living.append(pid)
		else:
			living.append(pid)  # no server player data — assume alive
	return living

func is_current_floor_boss_cleared() -> bool:
	var boss_id = _floor_layout.get("boss_id", -1)
	if boss_id < 0:
		return false
	return _floor_layout["rooms"].get(boss_id, {}).get("cleared", false)

# ── Helpers ───────────────────────────────────────────────────

func _get_dungeon_manager() -> Node:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	return sm._dungeon_manager if sm and sm.get("_dungeon_manager") else null
