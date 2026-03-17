extends Node

# ============================================================
# DUNGEON WAVE CONTROLLER (server-side)
# Spawns waves, advances on clear, fires checkpoint revives.
# ============================================================

signal dungeon_complete(instance_id: int)

var instance_id:    int     = -1
var zone_name:      String  = ""
var party_peers:    Array   = []
var wave_spawn_pos: Vector2 = Vector2(0, 200)  # revive pos for ghosts at checkpoint

var _current_wave:   int   = 0
var _total_waves:    int   = 3
var _wave_enemies:   Array = []
var _started:        bool  = false
var _complete:       bool  = false
var _wave_advancing: bool  = false

const WAVE_DEFS = [
	# Wave 1
	[
		{script="res://scripts/enemy_wolf.gd",        pos=Vector2(-120, 0),   id="w1_wolf_a"},
		{script="res://scripts/enemy_wolf.gd",        pos=Vector2( 120, 0),   id="w1_wolf_b"},
		{script="res://scripts/enemy_rogue_ninja.gd", pos=Vector2(  0, -80),  id="w1_ninja_a"},
	],
	# Wave 2
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
			# Wave clear — revive ghosts as checkpoint, then next wave after delay
			_checkpoint_revive()
			await get_tree().create_timer(3.0).timeout
			if not _complete:
				_wave_advancing = false
				_advance_wave()

func _advance_wave() -> void:
	_wave_advancing = false
	_current_wave  += 1
	if _current_wave > _total_waves:
		return

	var sm = get_tree().root.get_node_or_null("ServerMain")
	if not sm:
		return

	# Use first enemy spawn pos as the wave spawn / revive anchor
	var wave_def   = WAVE_DEFS[_current_wave - 1]
	wave_spawn_pos = wave_def[0].pos if wave_def.size() > 0 else Vector2(0, 200)
	_wave_enemies  = []

	for entry in wave_def:
		var enemy_id = "%s_%d_%s" % [zone_name, instance_id, entry.id]
		sm.spawn_dungeon_enemy(enemy_id, entry.script, entry.pos, zone_name)
		_wave_enemies.append(enemy_id)

	# Send roster AFTER spawning — clients need static data before sync arrives
	for pid in party_peers:
		sm._send_enemy_roster(pid, zone_name)

	_broadcast_wave_start()
	print("[DUNGEON] Instance %d wave %d started — %d enemies" % [
		instance_id, _current_wave, _wave_enemies.size()])

func _checkpoint_revive() -> void:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm and sm._dungeon_manager:
		sm._dungeon_manager.checkpoint_revive(instance_id, wave_spawn_pos)

func _broadcast_wave_start() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if not net:
		return
	var desc = "Boss!" if _current_wave == _total_waves else "Defeat all enemies"
	for pid in party_peers:
		net.notify_wave_start.rpc_id(pid, _current_wave, _total_waves, desc)

func _on_dungeon_complete() -> void:
	_complete = true
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm and sm._dungeon_manager:
		sm._dungeon_manager.on_dungeon_complete(instance_id)
	print("[DUNGEON] Instance %d complete!" % instance_id)
	dungeon_complete.emit(instance_id)
