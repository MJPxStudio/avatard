extends Node

# ============================================================
# DUNGEON WAVE CONTROLLER (server-side)
# One instance per dungeon run. Spawns waves of enemies,
# advances on full clear, triggers boss on wave 3.
# Lives as a child of ServerMain.
# ============================================================

signal dungeon_complete(instance_id: int)
signal dungeon_failed(instance_id: int)

var instance_id:   int     = -1
var zone_name:     String  = ""        # unique zone e.g. "cave_of_trials_1"
var party_peers:   Array   = []        # peer_ids in this instance

var _current_wave:   int   = 0         # 0 = not started
var _total_waves:    int   = 3
var _wave_enemies:   Array = []        # enemy_ids alive this wave
var _started:        bool  = false
var _complete:       bool  = false
var _wave_advancing: bool  = false     # prevents duplicate advance calls

# Wave definitions: array of arrays of {script, pos, id_suffix}
const WAVE_DEFS = [
	# Wave 1 — light patrol
	[
		{script="res://scripts/enemy_wolf.gd",        pos=Vector2(-120, 0),   id="w1_wolf_a"},
		{script="res://scripts/enemy_wolf.gd",        pos=Vector2( 120, 0),   id="w1_wolf_b"},
		{script="res://scripts/enemy_rogue_ninja.gd", pos=Vector2(  0, -80),  id="w1_ninja_a"},
	],
	# Wave 2 — heavier
	[
		{script="res://scripts/enemy_wolf.gd",        pos=Vector2(-160,  40), id="w2_wolf_a"},
		{script="res://scripts/enemy_wolf.gd",        pos=Vector2( 160,  40), id="w2_wolf_b"},
		{script="res://scripts/enemy_wolf.gd",        pos=Vector2(   0, -60), id="w2_wolf_c"},
		{script="res://scripts/enemy_rogue_ninja.gd", pos=Vector2(-80,  100), id="w2_ninja_a"},
		{script="res://scripts/enemy_rogue_ninja.gd", pos=Vector2( 80,  100), id="w2_ninja_b"},
	],
	# Wave 3 — boss
	[
		{script="res://scripts/enemy_cave_boss.gd",   pos=Vector2(0, -100),   id="w3_boss"},
	],
]

func start() -> void:
	if _started:
		return
	_started = true
	_advance_wave()

func on_enemy_killed(enemy_id: String) -> void:
	if not _started or _complete:
		return
	_wave_enemies.erase(enemy_id)
	if _wave_enemies.is_empty() and not _wave_advancing:
		_wave_advancing = true
		if _current_wave >= _total_waves:
			_on_dungeon_complete()
		else:
			# Brief delay then next wave
			await get_tree().create_timer(3.0).timeout
			if not _complete:
				_wave_advancing = false
				_advance_wave()

func _advance_wave() -> void:
	_wave_advancing = false
	_current_wave += 1
	if _current_wave > _total_waves:
		return

	var sm = get_tree().root.get_node_or_null("ServerMain")
	if not sm:
		return

	var wave_def  = WAVE_DEFS[_current_wave - 1]
	_wave_enemies = []

	for entry in wave_def:
		var enemy_id = "%s_%d_%s" % [zone_name, instance_id, entry.id]
		sm.spawn_dungeon_enemy(enemy_id, entry.script, entry.pos, zone_name)
		_wave_enemies.append(enemy_id)

	# Send fresh enemy roster to all players so static_cache is populated before sync arrives
	for pid in party_peers:
		sm._send_enemy_roster(pid, zone_name)

	# Notify all players in this instance
	_broadcast_wave_start()
	print("[DUNGEON] Instance %d wave %d started — %d enemies" % [instance_id, _current_wave, _wave_enemies.size()])

func _broadcast_wave_start() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if not net:
		return
	var desc = "Boss!" if _current_wave == _total_waves else "Defeat all enemies"
	for pid in party_peers:
		net.notify_wave_start.rpc_id(pid, _current_wave, _total_waves, desc)

func _on_dungeon_complete() -> void:
	_complete = true
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		for pid in party_peers:
			net.notify_dungeon_complete.rpc_id(pid)
	print("[DUNGEON] Instance %d complete!" % instance_id)
	dungeon_complete.emit(instance_id)
