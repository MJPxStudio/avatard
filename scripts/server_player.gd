extends CharacterBody2D
class_name ServerPlayer

const QuestDB = preload("res://scripts/quest_db.gd")

# ============================================================
# SERVER PLAYER
# Position is set by client via set_position_from_client.
# No server-side movement math.
# ============================================================

const TILE_SIZE = 16

func _ready() -> void:
	add_to_group("player")
	var shape   = CollisionShape2D.new()
	var rect    = RectangleShape2D.new()
	rect.size   = Vector2(10, 14)
	shape.shape = rect
	add_child(shape)
	collision_layer = 2
	collision_mask  = 3

var peer_id:       int        = -1
var username:      String     = ""
var kills:         int        = 0
var deaths:        int        = 0
var level:         int        = 1
var exp:           int        = 0
var max_exp:       int        = 100
var rank:          String     = "Academy Student"
var appearance:    Dictionary = {}  # hair_folder, hair_color
var stat_hp:       int        = 5
var stat_chakra:   int        = 5
var current_chakra: int       = -1   # -1 = full on first load
var max_chakra:     int       = 100  # recomputed in apply_stats
var stat_dex:      int        = 5
var stat_int:      int        = 5
var stat_points:   int        = 0
var quest_state:   Dictionary = {}   # {quest_id: {status, progress}}
var facing_dir:    String     = "down"

# --- Server-side validation ---
# Attack validation
const ATTACK_COOLDOWN:   float = 0.35   # slightly under client 0.4s to allow for latency
var _attack_timer:       float = 0.0    # time since last accepted attack

# Position rate limiting
const MIN_POS_INTERVAL:  float = 0.016  # ~60 updates/sec max
const MAX_POS_DELTA:     float = 320.0  # max px movement per update (10 tiles — covers lunge)
var _last_pos_time:      float = 0.0
var world_pos:     Vector2    = Vector2.ZERO
var prev_world_pos: Vector2   = Vector2.ZERO
var zone:          String     = "village"
var hp:            int        = 100
var max_hp:        int        = 100
var stat_strength: int        = 5
var _loaded_data:  Dictionary = {}

# Equipment
var equipped:    Dictionary = {}   # slot_key -> item dict from client
var is_poisoned:        bool   = false
var is_rooted:          bool   = false
var root_timer:         float  = 0.0
var dot_damage:         int    = 0
var dot_ticks_left:     int    = 0
var dot_interval:       float  = 1.0
var dot_timer:          float  = 0.0
var clan:               String = ""
var element:            String = ""
var element2:           String = ""
var unlocked_abilities: Array  = []
var hotbar_loadout:     Array  = []
# Gear bonuses (recalculated on equip change)
var _gear_str:    int = 0
var _gear_hp:     int = 0
var _gear_chakra: int = 0
var _gear_dex:    int = 0
var _gear_int:    int = 0

var invuln_ticks: float = 0.0
var is_dead:      bool  = false
var bleed_ticks:  int   = 0
var bleed_damage: int   = 2
var bleed_timer:  float = 1.0

# XP per level: base 100, grows by 1.5x each level
static func xp_for_level(lv: int) -> int:
	var v = 100
	for i in range(lv - 1):
		v = int(v * 1.5)
	return v

func grant_xp(amount: int) -> void:
	exp += amount
	while exp >= max_exp:
		exp    -= max_exp
		var old_rank: String = rank
		level  += 1
		max_exp = xp_for_level(level)
		stat_points += 3
		# Every level: +10 max_hp passively — stats are spent manually by the player
		max_hp += 10
		hp      = max_hp  # full heal on level up
		rank    = RankDB.get_rank_name(level)
		print("[SERVER] %s leveled up to %d! (rank: %s)" % [username, level, rank])
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			net.notify_level_up.rpc_id(peer_id, level, exp, max_exp, stat_points, max_hp,
				stat_strength, stat_hp, stat_chakra, stat_dex, stat_int)
			# Notify rank-up if rank changed
			if rank != old_rank:
				print("[SERVER] %s ranked up to %s!" % [username, rank])
				net.notify_rank_up.rpc_id(peer_id, rank)
				# Broadcast to all players via server_main
				var sm = get_tree().root.get_node_or_null("ServerMain")
				if sm and sm.has_method("broadcast_rank_up"):
					sm.broadcast_rank_up(username, rank)
	# Always sync current exp progress
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.notify_xp_gained.rpc_id(peer_id, exp, max_exp, amount)

func set_position_from_client(pos: Vector2, server_call: bool = false) -> void:
	# --- Rate limiting & distance validation (client calls only) ---
	if not server_call:
		var now = Time.get_ticks_msec() / 1000.0
		if now - _last_pos_time < MIN_POS_INTERVAL:
			return  # too fast — drop silently
		if pos.distance_to(world_pos) > MAX_POS_DELTA and world_pos != Vector2.ZERO:
			print("[SERVER] Position jump rejected for %s — %.1fpx" % [username, pos.distance_to(world_pos)])
			return
		_last_pos_time = now
	prev_world_pos = world_pos
	world_pos      = pos
	global_position                    = pos
	Network.players[peer_id]["position"]       = pos
	Network.players[peer_id]["position_ready"] = true

func request_attack(dir: Vector2, from_pos: Vector2) -> void:
	if is_dead:
		return
	# --- Validation ---
	# Cooldown: reject if attack fired too soon
	if _attack_timer > 0.0:
		return
	_attack_timer = ATTACK_COOLDOWN
	# from_pos = client's actual visual position at time of swing
	# More accurate than world_pos which is the step destination
	var d  = dir.normalized()
	var sm = get_tree().root.get_node("ServerMain")
	# Hit players
	for oid in sm.server_players:
		if oid == peer_id:
			continue
		var other = sm.server_players[oid]
		if other.zone != zone:
			continue
		var to_o = other.world_pos - from_pos
		var fwd  = to_o.dot(d)
		var lat  = abs(to_o.dot(Vector2(-d.y, d.x)))
		if fwd > 0 and fwd < 48.0 and lat < 28.0 and not other.is_dead:
			# Friendly fire: skip damage if both are in the same party
			if sm.are_same_party(peer_id, oid):
				continue
			var pvp_dmg = 15 + int(effective_strength() * 0.4)
			other.take_damage(pvp_dmg, d, peer_id)
			# Send confirm_hit back to attacker so damage numbers appear
			Network.confirm_hit.rpc_id(peer_id, other.world_pos, pvp_dmg)
	# Hit enemies
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.zone_name != zone:
			continue
		var to_e = enemy.global_position - from_pos
		var fwd  = to_e.dot(d)
		var lat  = abs(to_e.dot(Vector2(-d.y, d.x)))
		if fwd > 0 and fwd < 48.0 and lat < 28.0:
			var dmg = 15 + int(effective_strength() * 0.4)
			if enemy.has_method("take_damage"):
				enemy.take_damage(dmg, d, get_instance_id())
			Network.confirm_hit.rpc_id(peer_id, enemy.global_position, dmg)

func take_damage(amount: int, knockback_dir: Vector2, attacker = null) -> void:
	if invuln_ticks > 0 or is_dead:
		return
	hp           = max(0, hp - amount)
	invuln_ticks = 0.5
	Network.sync_damage.rpc_id(peer_id, peer_id, amount, knockback_dir)
	if hp <= 0:
		hp      = max_hp
		is_dead = true
		deaths += 1
		print("[SERVER] Player %s died — starting 5s respawn timer" % username)
		# Broadcast kill feed — attacker is a peer_id (PvP) or instance_id (enemy)
		var sm = get_tree().root.get_node_or_null("ServerMain")
		if sm and attacker != null and attacker is int:
			var killer_name = "Unknown"
			# Try peer_id lookup first (PvP)
			var killer_sp = sm.server_players.get(attacker, null)
			if killer_sp:
				killer_name = killer_sp.username
			else:
				# Attacker is an enemy instance_id — find by instance
				for eid in sm._enemy_nodes:
					var en = sm._enemy_nodes[eid]
					if is_instance_valid(en) and en.get_instance_id() == attacker:
						killer_name = en.enemy_name
						break
			sm.broadcast_kill(killer_name, username)
		# Notify dungeon manager if inside a dungeon
		if sm._dungeon_manager and sm._dungeon_manager.peer_is_in_dungeon(peer_id):
			sm._dungeon_manager.player_died(peer_id)
		# Keep zone unchanged during death — changing it now clears client enemy list
		# Use a timer node so we don't await inside take_damage
		var t = get_tree().create_timer(5.0)
		t.timeout.connect(_on_respawn_timer, CONNECT_ONE_SHOT)

func _on_respawn_timer() -> void:
	print("[SERVER] Respawn timer fired for %s — was zone=%s" % [username, zone])
	is_dead         = false
	# Now change zone and position for respawn
	var village_spawn     = Vector2(40.0, 40.0)  # center of village
	world_pos       = village_spawn
	global_position = village_spawn
	Network.players[peer_id]["position"] = village_spawn
	Network.players[peer_id]["zone"]     = "village"
	zone            = "village"
	var save_data         = get_save_data().duplicate()
	save_data["zone"]     = "village"
	save_data["position"] = [village_spawn.x, village_spawn.y]
	Database.save_player(username, save_data)
	print("[SERVER] Player %s respawning — sending signal to client" % username)
	# Signal client to respawn (amount=0 = respawn signal)
	Network.sync_damage.rpc_id(peer_id, peer_id, 0, Vector2.ZERO)

func _process(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta
	if invuln_ticks > 0:
		invuln_ticks -= delta
	if bleed_ticks > 0:
		bleed_timer -= delta
		if bleed_timer <= 0:
			bleed_timer = 1.0
			take_damage(bleed_damage, Vector2.ZERO)
			bleed_ticks -= 1
	# Root timer
	if is_rooted and root_timer > 0.0:
		root_timer -= delta
		if root_timer <= 0.0:
			is_rooted = false
			var net = get_tree().root.get_node_or_null("Network")
			if net:
				net.notify_status_end.rpc_id(peer_id, peer_id, "root")
	# DoT (shadow strangle, poison, etc.)
	if dot_ticks_left > 0:
		dot_timer -= delta
		if dot_timer <= 0.0:
			dot_timer = dot_interval
			take_damage(dot_damage, Vector2.ZERO)
			dot_ticks_left -= 1

func apply_root(duration: float) -> void:
	is_rooted  = true
	root_timer = duration
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.notify_status.rpc_id(peer_id, peer_id, "root", duration)

func apply_dot(damage: int, interval: float, ticks: int) -> void:
	dot_damage     = damage
	dot_interval   = interval
	dot_ticks_left = ticks
	dot_timer      = interval
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.notify_status.rpc_id(peer_id, "dot", interval * ticks)

func apply_pull(caster_pos: Vector2, pull_dist: float, tile_size: float = 16.0) -> void:
	var dir      = (caster_pos - world_pos).normalized()
	var new_pos  = caster_pos - dir * pull_dist
	new_pos      = Vector2(round(new_pos.x / tile_size) * tile_size,
	                       round(new_pos.y / tile_size) * tile_size)
	world_pos        = new_pos
	global_position  = new_pos
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.notify_pull.rpc_id(peer_id, new_pos)

func check_kill_quest(killed_enemy_name: String) -> void:
	var net = get_tree().root.get_node_or_null("Network")
	for qid in quest_state:
		var qs = quest_state[qid]
		if qs.get("status") != "active":
			continue
		var qdef = QuestDB.get_quest(qid)
		if qdef.is_empty() or qdef.get("type") != "kill":
			continue
		if qdef.get("target") != killed_enemy_name:
			continue
		qs["progress"] = qs.get("progress", 0) + 1
		var progress = qs["progress"]
		var required = qdef.get("required", 1)
		if net:
			net.notify_quest_progress.rpc_id(peer_id, qid, progress, required)
		print("[SERVER] Quest %s progress: %d/%d for %s" % [qid, progress, required, username])

func recalculate_gear_stats() -> void:
	_gear_str = 0; _gear_hp = 0; _gear_chakra = 0; _gear_dex = 0; _gear_int = 0
	for slot in equipped:
		var item = equipped[slot]
		var b = item.get("stat_bonuses", {})
		_gear_str    += b.get("strength", 0)
		_gear_hp     += b.get("hp",       0)
		_gear_chakra += b.get("chakra",   0)
		_gear_dex    += b.get("dex",      0)
		_gear_int    += b.get("int",      0)
	# Recompute effective max_hp from base stat + gear
	var base_max_hp = 100 + stat_hp * 10 + (level - 1) * 10
	max_hp     = base_max_hp + _gear_hp
	max_chakra = 100 + stat_chakra * 10 + _gear_chakra
	hp              = mini(hp, max_hp)
	if current_chakra < 0:
		current_chakra = max_chakra
	current_chakra = mini(current_chakra, max_chakra)

func effective_strength() -> int:
	return stat_strength + _gear_str

func use_consumable(item_id: String) -> Dictionary:
	# Returns {success, message, new_hp}
	var item = ItemDB.get_item(item_id)
	if item.is_empty():
		return {success=false, message="Unknown item."}
	var effect = item.get("use_effect", {})
	if effect.is_empty():
		return {success=false, message="%s cannot be used." % item.get("name","Item")}
	var etype = effect.get("type", "")
	match etype:
		"heal_hp":
			if hp >= max_hp:
				return {success=false, message="HP is already full."}
			var amount = effect.get("amount", 50)
			hp = mini(hp + amount, max_hp)
			return {success=true, message="Restored %d HP." % amount, new_hp=hp, new_max_hp=max_hp}
		"cure_poison":
			if not is_poisoned:
				return {success=false, message="You are not poisoned."}
			is_poisoned = false
			return {success=true, message="Cured poison.", new_hp=hp, new_max_hp=max_hp}
		_:
			return {success=false, message="Unknown effect."}

func get_save_data() -> Dictionary:
	var data         = _loaded_data.duplicate()
	data["username"] = username
	data["position"] = world_pos
	data["zone"]     = zone
	data["stat_str"] = stat_strength
	data["max_hp"]   = max_hp
	data["hp"]       = hp
	data["clan"]     = clan
	data["element"]  = element
	data["element2"] = element2
	data["unlocked_abilities"] = unlocked_abilities.duplicate()
	data["hotbar_loadout"]     = hotbar_loadout.duplicate()
	data["kills"]      = kills
	data["deaths"]     = deaths
	data["level"]      = level
	data["exp"]        = exp
	data["max_exp"]    = max_exp
	data["stat_points"]= stat_points
	data["stat_hp"]    = stat_hp
	data["stat_chakra"]= stat_chakra
	data["stat_dex"]   = stat_dex
	data["stat_int"]   = stat_int
	data["quest_state"]= quest_state
	data["equipped"]    = equipped
	data["appearance"]  = appearance.duplicate()
	return data
