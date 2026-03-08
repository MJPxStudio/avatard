extends Node

const DungeonData     = preload("res://scripts/dungeon_data.gd")
const WaveController  = preload("res://scripts/dungeon_wave_controller.gd")

# ============================================================
# DUNGEON MANAGER (server-side)
# Manages instanced dungeon runs. Lives as a child of server_main.
#
# Instance lifecycle:
#   enter  → create instance if none exists for this party/player
#   exit   → remove player, destroy instance when empty
#   all dead → destroy instance (party wiped)
#
# Persist rule: instance survives as long as ≥1 member is alive
#               inside. If ALL alive players leave or die, it resets.
# ============================================================

# instance_id (int) -> {
#   dungeon_id, party_id (-1=solo), players: Array[peer_id],
#   alive: Array[peer_id], created_at
# }
var _instances:   Dictionary = {}
var _next_id:     int        = 1

# peer_id -> instance_id (which instance they're currently in)
var _peer_instance: Dictionary = {}

# instance_id -> WaveController node
var _wave_controllers: Dictionary = {}

# Reference to server_main's server_players dict (set by server_main in _ready)
var server_players: Dictionary = {}

# ── ENTER ──────────────────────────────────────────────────────────────────
func player_enter(peer_id: int, dungeon_id: String, party_id: int) -> Dictionary:
	# Returns { ok: bool, instance_id: int, error: String }
	var def = DungeonData.get_dungeon(dungeon_id)
	if def.is_empty():
		return { "ok": false, "error": "Unknown dungeon: %s" % dungeon_id }

	var sp = server_players.get(peer_id, null)
	if not sp:
		return { "ok": false, "error": "Player not found" }

	# Solo-only check
	if def["solo_only"] and party_id != -1:
		return { "ok": false, "error": "%s is solo only." % def["display_name"] }

	# Level check
	if sp.level < def["min_level"]:
		return { "ok": false, "error": "Requires level %d." % def["min_level"] }

	# Already inside an instance?
	if _peer_instance.has(peer_id):
		return { "ok": false, "error": "Already inside a dungeon." }

	# Find existing instance for this party (or solo)
	var inst_id = _find_instance(dungeon_id, party_id, peer_id)

	if inst_id == -1:
		# Create new instance
		inst_id = _next_id
		_next_id += 1
		var base_zone = DungeonData.get_dungeon(dungeon_id).get("zone_name", dungeon_id)
		var inst_zone  = base_zone + "_" + str(inst_id)
		_instances[inst_id] = {
			"dungeon_id":  dungeon_id,
			"zone_name":   inst_zone,
			"party_id":    party_id,
			"players":     [],
			"alive":       [],
			"created_at":  Time.get_ticks_msec(),
		}
		print("[DUNGEON] Created instance %d for dungeon '%s' party_id=%d" % [inst_id, dungeon_id, party_id])

	var inst = _instances[inst_id]

	# Max player cap
	if inst["players"].size() >= def["max_players"]:
		return { "ok": false, "error": "Instance full (%d players)." % def["max_players"] }

	inst["players"].append(peer_id)
	inst["alive"].append(peer_id)
	_peer_instance[peer_id] = inst_id

	# Start or update wave controller
	if not _wave_controllers.has(inst_id):
		var wc = WaveController.new()
		wc.instance_id = inst_id
		wc.zone_name   = inst["zone_name"]
		wc.party_peers = inst["players"]
		get_parent().add_child(wc)
		_wave_controllers[inst_id] = wc
		# Start wave after brief delay so clients finish loading
		get_tree().create_timer(2.5).timeout.connect(func(): wc.start(), CONNECT_ONE_SHOT)
	else:
		# Late joiner — update peer list and fire roster
		_wave_controllers[inst_id].party_peers = inst["players"]

	print("[DUNGEON] %s entered instance %d (%s)" % [sp.username, inst_id, dungeon_id])
	return { "ok": true, "instance_id": inst_id, "zone_name": inst["zone_name"] }

# ── EXIT ───────────────────────────────────────────────────────────────────
func player_exit(peer_id: int) -> void:
	if not _peer_instance.has(peer_id):
		return
	var inst_id = _peer_instance[peer_id]
	_remove_player(peer_id, inst_id)

# Called by server_main when a player dies inside a dungeon
func player_died(peer_id: int) -> void:
	if not _peer_instance.has(peer_id):
		return
	var inst_id = _peer_instance[peer_id]
	var inst    = _instances.get(inst_id, null)
	if not inst:
		return
	inst["alive"].erase(peer_id)
	print("[DUNGEON] Player %d died in instance %d. Alive remaining: %d" % [peer_id, inst_id, inst["alive"].size()])
	# If no one is alive, wipe the instance
	if inst["alive"].is_empty():
		print("[DUNGEON] All players dead — destroying instance %d" % inst_id)
		_destroy_instance(inst_id)

# Called by server_main when a player disconnects
func player_disconnected(peer_id: int) -> void:
	player_exit(peer_id)

# ── QUERY ──────────────────────────────────────────────────────────────────
func is_instance_complete(inst_id: int) -> bool:
	var wc = _wave_controllers.get(inst_id, null)
	if wc and is_instance_valid(wc):
		return wc._complete
	return false

func on_enemy_killed(enemy_id: String, zone: String) -> void:
	# Find which instance owns this zone
	for iid in _instances:
		if _instances[iid]["zone_name"] == zone:
			var wc = _wave_controllers.get(iid, null)
			if wc:
				wc.on_enemy_killed(enemy_id)
			return

func get_instance_id_for_peer(peer_id: int) -> int:
	return _peer_instance.get(peer_id, -1)

func peer_is_in_dungeon(peer_id: int) -> bool:
	return _peer_instance.has(peer_id)

# ── INTERNAL ───────────────────────────────────────────────────────────────
func _find_instance(dungeon_id: String, party_id: int, peer_id: int) -> int:
	for iid in _instances:
		var inst = _instances[iid]
		if inst["dungeon_id"] != dungeon_id:
			continue
		# Solo: each player gets their own instance
		if party_id == -1:
			continue
		# Party: match party_id and make sure instance still has alive players
		if inst["party_id"] == party_id and not inst["alive"].is_empty():
			return iid
	return -1

func _remove_player(peer_id: int, inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		_peer_instance.erase(peer_id)
		return
	inst["players"].erase(peer_id)
	inst["alive"].erase(peer_id)
	_peer_instance.erase(peer_id)
	print("[DUNGEON] Player %d exited instance %d. Remaining: %d" % [peer_id, inst_id, inst["players"].size()])
	if inst["players"].is_empty():
		_destroy_instance(inst_id)

func _destroy_instance(inst_id: int) -> void:
	var inst = _instances.get(inst_id, null)
	if not inst:
		return
	for pid in inst["players"].duplicate():
		_peer_instance.erase(pid)
	_instances.erase(inst_id)
	# Clean up wave controller
	if _wave_controllers.has(inst_id):
		var wc = _wave_controllers[inst_id]
		if is_instance_valid(wc):
			wc.queue_free()
		_wave_controllers.erase(inst_id)
	print("[DUNGEON] Instance %d destroyed." % inst_id)
