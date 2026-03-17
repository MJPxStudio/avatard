extends Node2D

# ============================================================
# SERVER COCOON — straight-line non-homing projectile.
# Travels at 120px/s (slower than player's 200px/s).
# Hitbox: 24px radius (3 tiles = 48px diameter).
# Hits ALL valid targets it overlaps, then despawns.
# ============================================================

const SPEED:        float = 120.0
const HIT_RADIUS:   float = 24.0    # 1.5 tiles — half of 3-tile width
const MAX_RANGE:    float = 240.0   # 15 tiles max travel distance
const BROADCAST_INTERVAL: float = 0.05

var cocoon_id:    String = ""
var caster_id:    int    = 0
var zone:         String = ""
var direction:    Vector2 = Vector2.ZERO
var root_dur:     float  = 4.0
var dmg_per_tick: int    = 8
var tick_int:     float  = 1.0
var tick_count:   int    = 6

var _start_pos:       Vector2 = Vector2.ZERO
var _broadcast_acc:   float   = 0.0
var _hit_ids:         Array   = []   # target ids already hit — no double-hit

func _ready() -> void:
	_start_pos = global_position
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	global_position += direction * SPEED * delta

	# Despawn if exceeded max range
	if global_position.distance_to(_start_pos) >= MAX_RANGE:
		_despawn(false)
		return

	# Broadcast position
	_broadcast_acc += delta
	if _broadcast_acc >= BROADCAST_INTERVAL:
		_broadcast_acc = 0.0
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			net.shadow_move.rpc(cocoon_id, global_position)

	# Overlap check
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return
	var hit_any = false
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.zone_name != zone or enemy.is_dead:
			continue
		if _hit_ids.has(enemy.enemy_id):
			continue
		if enemy.global_position.distance_to(global_position) <= HIT_RADIUS:
			_hit_ids.append(enemy.enemy_id)
			enemy.apply_root(root_dur)
			enemy.apply_dot(dmg_per_tick, tick_int, tick_count, caster_id)
			sm._emit_visual(enemy.enemy_id, "bug_hit")
			Network.confirm_ability_hit.rpc_id(caster_id, enemy.global_position, dmg_per_tick)
			hit_any = true
	for oid in sm.server_players:
		if oid == caster_id:
			continue
		var other = sm.server_players[oid]
		if other.zone != zone or other.is_dead:
			continue
		if sm.are_same_party(caster_id, oid):
			continue
		var pid_str = "player_%d" % oid
		if _hit_ids.has(pid_str):
			continue
		if other.world_pos.distance_to(global_position) <= HIT_RADIUS:
			_hit_ids.append(pid_str)
			other.apply_rooted_visual(root_dur)
			other.apply_dot(dmg_per_tick, tick_int, tick_count, caster_id)
			sm._emit_visual(str(other.peer_id), "bug_hit")
			Network.confirm_ability_hit.rpc_id(caster_id, other.world_pos, dmg_per_tick)
			hit_any = true

	if hit_any:
		_despawn(true)

func _despawn(hit: bool) -> void:
	set_physics_process(false)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.shadow_despawn.rpc(cocoon_id, hit)
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm:
		sm._cocoon_nodes.erase(cocoon_id)
	queue_free()
