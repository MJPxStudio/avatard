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
var current_chakra: int       = 500  # DEBUG: start full
var max_chakra:     int       = 500  # DEBUG: large pool for testing
var stat_dex:      int        = 5
var stat_int:      int        = 5
var stat_points:   int        = 0
var quest_state:   Dictionary = {}   # {quest_id: {status, progress}}
var has_done_intro: bool        = false  # set after escort completes
# Mission board state
var active_mission:   String     = ""    # id of currently active mission
var mission_progress: int        = 0     # progress toward required
var mission_data:     Dictionary = {}    # full mission dict (includes assigned deliver target)
# Board state per rank — which missions have been completed this cycle
var board_completed:  Dictionary = {}    # rank -> Array[mission_id] completed this cycle
var facing_dir:       String     = "down"
var locked_target_id: String     = ""   # kept in sync via send_target_update RPC

# --- Server-side validation ---
# Ability cooldowns — keyed by ability_name, value is seconds remaining
var ability_cooldowns: Dictionary = {}

# Attack validation
const ATTACK_COOLDOWN:   float = 0.35   # slightly under client 0.4s to allow for latency
var _attack_timer:       float = 0.0    # time since last accepted attack
var palms_primed:       bool  = false   # 15s window waiting for lunge hit
var parasite_primed:    bool  = false   # Aburame parasite prime window
var parasite_prime_timer: float = 0.0
const PARASITE_PRIME_DUR: float = 15.0
var palms_prime_timer:  float = 0.0
var palms_byakugan:     bool  = false   # byakugan state captured at prime time
var knockback_timer:    float = 0.0     # skip position broadcast while > 0

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

# ── Dungeon boon properties ───────────────────────────────────
var boon_chakra_cost_mult:       float = 1.0
var boon_clay_dmg_mult:          float = 1.0
var boon_c1_damage_flat:         int   = 0
var boon_c1_speed_mult:          float = 1.0
var boon_c1_range_mult:          float = 1.0
var boon_c1_cooldown_flat:       float = 0.0
var boon_c1_spider_count:        int   = 1
var boon_c2_cooldown_flat:       float = 0.0
var boon_c2_orbit_duration_flat: float = 0.0
var boon_c2_drop_interval_mult:  float = 1.0
var boon_c2_explosion_mult:      float = 1.0
var boon_c2_owl_count:           int   = 1
var boon_c3_cooldown_flat:       float = 0.0
var boon_c3_radius_mult:         float = 1.0
var boon_c4_count_flat:          int   = 0
var boon_c4_dmg_mult:            float = 1.0
var boon_c4_radius_mult:         float = 1.0
var dungeon_passives:            Array = []
var dungeon_dash_bonus:          int   = 0
var dungeon_room_id:             int   = -1  # current dungeon room — checked for ability bleed

# Equipment
var equipped:    Dictionary = {}   # slot_key -> item dict from client
var gold:        int        = 0
var inventory:   Dictionary = {}   # item_id -> quantity
var is_poisoned:        bool   = false
var is_rooted:          bool   = false
var is_ghost:           bool   = false  # dungeon ghost — immune to damage, no abilities
var is_spinning:        bool   = false
var is_immune:          bool   = false  # Palm Rotation — blocks all incoming damage
var bug_cloak_active:   bool   = false  # Aburame Bug Cloak toggle
var _cloak_aura_timer:  float  = 0.0    # tracks 1s passive drain tick
var byakugan_active:    bool   = false
var _byakugan_drain_timer: float  = 0.0
var root_timer:         float  = 0.0
var dot_damage:         int    = 0
var dot_ticks_left:     int    = 0
var dot_caster_peer_id: int    = -1
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
# Heal-over-time (Medical Jutsu)
var hot_ticks:     int   = 0
var hot_damage:    int   = 0   # heal amount per tick
var hot_interval:  float = 1.0
var hot_timer:     float = 0.0
# Substitution
var is_substitution_primed: bool  = false
var _sub_timer:             float = 0.0
const SUB_PRIME_DUR:        float = 15.0
# Charging (chakra charge ability)
var is_charging:      bool  = false
var _charge_accum:    float = 0.0
const CHARGE_RATE:    float = 12.0   # chakra/sec while charging (matches client)

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

func request_attack(dir: Vector2, _from_pos: Vector2) -> void:
	if is_dead or is_rooted or is_ghost:
		return
	if _attack_timer > 0.0:
		return
	_attack_timer = ATTACK_COOLDOWN
	var d:  Vector2    = dir.normalized()
	# Always use server world_pos as authoritative origin — never trust client position
	var from_pos: Vector2 = world_pos
	var sm: Node       = get_tree().root.get_node("ServerMain")
	# Track first hit for primed abilities (palms, parasite)
	var palms_hit_node:     Node = null
	var palms_hit_is_enemy: bool = false
	var any_hit_node:       Node = null
	var any_hit_is_enemy:   bool = false
	# Hit players
	for oid: int in sm.server_players:
		if oid == peer_id:
			continue
		var other: ServerPlayer = sm.server_players[oid]
		if other.zone != zone:
			continue
		var to_o: Vector2 = other.world_pos - from_pos
		var fwd:  float   = to_o.dot(d)
		var lat:  float   = abs(to_o.dot(Vector2(-d.y, d.x)))
		if fwd > 0 and fwd < 56.0 and lat < 32.0 and not other.is_dead:
			if sm.are_same_party(peer_id, oid):
				continue
			var pvp_dmg: int = 15 + int(effective_strength() * 0.4)
			other.take_damage(pvp_dmg, d, peer_id)
			Network.confirm_hit.rpc_id(peer_id, other.world_pos, pvp_dmg)
			if any_hit_node == null:
				any_hit_node     = other
				any_hit_is_enemy = false
			if palms_primed and palms_hit_node == null:
				palms_hit_node     = other
				palms_hit_is_enemy = false
	# Hit enemies
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if enemy.zone_name != zone:
			continue
		var to_e: Vector2 = enemy.global_position - from_pos
		var fwd:  float   = to_e.dot(d)
		var lat:  float   = abs(to_e.dot(Vector2(-d.y, d.x)))
		if fwd > 0 and fwd < 56.0 and lat < 32.0:
			var dmg: int = 15 + int(effective_strength() * 0.4)
			if enemy.has_method("take_damage"):
				enemy.take_damage(dmg, d, get_instance_id())
			Network.confirm_hit.rpc_id(peer_id, enemy.global_position, dmg)
			if any_hit_node == null:
				any_hit_node     = enemy
				any_hit_is_enemy = true
			if palms_primed and palms_hit_node == null:
				palms_hit_node     = enemy
				palms_hit_is_enemy = true
	# Trigger 64/128 palms if primed and a hit landed
	if palms_primed and palms_hit_node != null:
		palms_primed      = false
		palms_prime_timer = 0.0
		sm._trigger_palms_burst(peer_id, palms_hit_node, palms_hit_is_enemy)
	# Trigger parasite if primed and a hit landed
	if parasite_primed and any_hit_node != null:
		parasite_primed      = false
		parasite_prime_timer = 0.0
		sm._trigger_parasite(peer_id, any_hit_node, any_hit_is_enemy)

func spend_chakra(amount: int) -> bool:
	if current_chakra < amount:
		# Sync the real value back so client stops thinking it has chakra it doesn't
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			net.sync_chakra.rpc_id(peer_id, peer_id, current_chakra, max_chakra)
		return false
	current_chakra -= amount
	# Keep client chakra in sync with server after every spend
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.sync_chakra.rpc_id(peer_id, peer_id, current_chakra, max_chakra)
	return true

func take_damage(amount: int, knockback_dir: Vector2, attacker = null) -> void:
	if invuln_ticks > 0 or is_dead or is_immune or is_ghost:
		return
	# Substitution — negate hit, trigger teleport (client already moved, server confirms)
	if is_substitution_primed:
		is_substitution_primed = false
		_sub_timer = 0.0
		_broadcast_visual("sub_triggered")
		return
	# Bug Cloak: 10% damage reduction + drain 5 chakra from attacker
	if bug_cloak_active:
		amount = max(1, int(amount * 0.9))
		if attacker != null and attacker is int:
			var sm = get_tree().root.get_node_or_null("ServerMain")
			if sm:
				var attacker_sp = sm.server_players.get(attacker, null)
				if attacker_sp:
					attacker_sp.apply_chakra_drain(5)
	hp           = max(0, hp - amount)
	invuln_ticks = 0.5
	Network.sync_damage.rpc_id(peer_id, peer_id, amount, knockback_dir)
	# Knockback breaks shadow possession
	if knockback_dir != Vector2.ZERO:
		var sm = get_tree().root.get_node_or_null("ServerMain")
		if sm and sm.has_method("cancel_shadows_for_peer"):
			sm.cancel_shadows_for_peer(peer_id)
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
	# Reset chakra to full on respawn
	current_chakra  = max_chakra
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.sync_chakra.rpc_id(peer_id, peer_id, current_chakra, max_chakra)
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
	# Tick ability cooldowns
	for key in ability_cooldowns.keys():
		ability_cooldowns[key] -= delta
		if ability_cooldowns[key] <= 0.0:
			ability_cooldowns.erase(key)
	if knockback_timer > 0.0:
		knockback_timer -= delta
	# Tick 64-palms prime window
	if palms_primed:
		palms_prime_timer -= delta
		if palms_prime_timer <= 0.0:
			palms_primed = false
			var _net = get_tree().root.get_node_or_null("Network")
			if _net:
				_net.palms_prime_expired.rpc_id(peer_id)
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
	# Parasite prime timer
	if parasite_primed:
		parasite_prime_timer -= delta
		if parasite_prime_timer <= 0.0:
			parasite_primed = false
	# Substitution prime timer
	if is_substitution_primed:
		_sub_timer -= delta
		if _sub_timer <= 0.0:
			is_substitution_primed = false
	# HoT (Medical Jutsu)
	if hot_ticks > 0:
		hot_timer -= delta
		if hot_timer <= 0.0:
			hot_timer = hot_interval
			hp = min(max_hp, hp + hot_damage)
			Network.sync_damage.rpc_id(peer_id, peer_id, -hot_damage, Vector2.ZERO)
			hot_ticks -= 1
	# DoT (shadow strangle, poison, etc.)
	if dot_ticks_left > 0:
		dot_timer -= delta
		if dot_timer <= 0.0:
			dot_timer = dot_interval
			take_damage(dot_damage, Vector2.ZERO)
			dot_ticks_left -= 1
	# Bug Cloak passive aura — drain 2 chakra/sec from enemies within 80px
	if bug_cloak_active:
		_cloak_aura_timer += delta
		if _cloak_aura_timer >= 1.0:
			_cloak_aura_timer = 0.0
			var sm = get_tree().root.get_node_or_null("ServerMain")
			if sm:
				for enemy in sm.get_tree().get_nodes_in_group("enemy"):
					if enemy.zone_name != zone or enemy.is_dead:
						continue
					if enemy.global_position.distance_to(world_pos) <= 80.0:
						if enemy.has_method("apply_chakra_drain"):
							enemy.apply_chakra_drain(2)
	# Byakugan — drain 5 chakra/sec while active, auto-deactivate on empty
	if byakugan_active:
		_byakugan_drain_timer += delta
		if _byakugan_drain_timer >= 1.0:
			_byakugan_drain_timer = 0.0
			if not spend_chakra(5):
				byakugan_active = false
				var net = get_tree().root.get_node_or_null("Network")
				if net:
					net.byakugan_state.rpc(peer_id, false)
	# Chakra charging — regenerate while is_charging (matches client 12/sec)
	if is_charging and current_chakra < max_chakra:
		_charge_accum += CHARGE_RATE * delta
		if _charge_accum >= 1.0:
			var gained = int(_charge_accum)
			_charge_accum -= gained
			current_chakra = mini(max_chakra, current_chakra + gained)
			var net = get_tree().root.get_node_or_null("Network")
			if net:
				net.sync_chakra.rpc_id(peer_id, peer_id, current_chakra, max_chakra)
	elif not is_charging:
		_charge_accum = 0.0

func apply_root(duration: float) -> void:
	is_rooted  = true
	root_timer = duration
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.notify_status.rpc_id(peer_id, peer_id, "root", duration)

func apply_dot(damage: int, interval: float, ticks: int, caster_peer: int = -1) -> void:
	dot_damage          = damage
	dot_interval        = interval
	dot_ticks_left      = ticks
	dot_timer           = interval
	dot_caster_peer_id  = caster_peer
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.notify_status.rpc_id(peer_id, peer_id, "dot", interval * ticks)

func apply_chakra_drain(amount: int) -> void:
	current_chakra = max(0, current_chakra - amount)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.sync_chakra.rpc_id(peer_id, peer_id, current_chakra, max_chakra)

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
	max_chakra = maxi(max_chakra, 500)  # DEBUG: ensure large pool for testing
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
	# Validate the player actually owns this item
	if not has_item(item_id):
		return {success=false, message="You don't have that item."}
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
			consume_item(item_id)
			return {success=true, message="Restored %d HP." % amount, new_hp=hp, new_max_hp=max_hp}
		"cure_poison":
			if not is_poisoned:
				return {success=false, message="You are not poisoned."}
			is_poisoned = false
			consume_item(item_id)
			return {success=true, message="Cured poison.", new_hp=hp, new_max_hp=max_hp}
		_:
			return {success=false, message="Unknown effect."}

func grant_gold(amount: int) -> void:
	gold += amount
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.sync_gold.rpc_id(peer_id, gold)

func grant_item(item_id: String, quantity: int = 1) -> void:
	inventory[item_id] = inventory.get(item_id, 0) + quantity
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.grant_item.rpc_id(peer_id, item_id, quantity)

func has_item(item_id: String, quantity: int = 1) -> bool:
	return inventory.get(item_id, 0) >= quantity

func consume_item(item_id: String, quantity: int = 1) -> bool:
	if not has_item(item_id, quantity):
		return false
	inventory[item_id] -= quantity
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	return true

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
	data["has_done_intro"] = has_done_intro
	data["active_mission"]   = active_mission
	data["mission_progress"] = mission_progress
	data["mission_data"]     = mission_data.duplicate()
	data["board_completed"]  = board_completed.duplicate()
	data["equipped"]    = equipped
	data["gold"]        = gold
	data["inventory"]   = inventory.duplicate()
	data["appearance"]  = appearance.duplicate()
	return data

func _broadcast_visual(visual_id: String) -> void:
	# Broadcast a visual tied to this player to all connected clients.
	# Uses .rpc() to reach all clients + emits locally for the host process.
	var net = Engine.get_singleton("Network") if Engine.has_singleton("Network") else null
	if net == null:
		net = Engine.get_main_loop().root.get_node_or_null("/root/Network")
	if net == null:
		return
	var id_str = str(peer_id)
	net.ability_visual.rpc(id_str, visual_id)
	net.ability_visual_received.emit(id_str, visual_id, Vector2.ZERO)

func apply_rooted_visual(duration: float) -> void:
	# Same as apply_root but also broadcasts the rooted visual to ALL clients
	# so other players can see the target get rooted.
	is_rooted  = true
	root_timer = duration
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.notify_status.rpc_id(peer_id, peer_id, "root", duration)
		net.ability_visual.rpc(str(peer_id), "rooted_start")
		net.ability_visual_received.emit(str(peer_id), "rooted_start", Vector2.ZERO)

func apply_spin(duration: float) -> void:
	# Grant spin immunity + broadcast rotation visual to all clients.
	is_spinning = true
	is_immune   = true
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.ability_visual.rpc(str(peer_id), "rotation_start")
		net.ability_visual_received.emit(str(peer_id), "rotation_start", Vector2.ZERO)
	# Schedule spin end
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		is_spinning = false
		is_immune   = false
		var net2 = get_tree().root.get_node_or_null("Network")
		if net2:
			net2.ability_visual.rpc(str(peer_id), "rotation_end")
			net2.ability_visual_received.emit(str(peer_id), "rotation_end", Vector2.ZERO)
	, CONNECT_ONE_SHOT)

func start_charging() -> void:
	is_charging = true
	_broadcast_visual("charging_start")

func stop_charging() -> void:
	is_charging = false
	_broadcast_visual("charging_stop")

func start_hot(heal_per_tick: int, interval: float, ticks: int) -> void:
	hot_damage   = heal_per_tick
	hot_interval = interval
	hot_ticks    = ticks
	hot_timer    = 0.0
	_broadcast_visual("medical_start")

func prime_substitution() -> void:
	is_substitution_primed = true
	_sub_timer             = SUB_PRIME_DUR
	_broadcast_visual("sub_primed")

func trigger_substitution(new_pos: Vector2) -> void:
	is_substitution_primed = false
	_sub_timer             = 0.0
	# Teleport server position
	world_pos = new_pos
	_broadcast_visual("sub_triggered")

func is_ability_on_cooldown(ability_name: String) -> bool:
	return ability_cooldowns.has(ability_name) and ability_cooldowns[ability_name] > 0.0

func set_ability_cooldown(ability_name: String, duration: float) -> void:
	if duration > 0.0:
		ability_cooldowns[ability_name] = duration
