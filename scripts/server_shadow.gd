extends Node2D

# ============================================================
# SERVER SHADOW — runs on server only.
# Steers toward a moving target using simple angle-probing
# obstacle avoidance. No navigation mesh required.
# ============================================================

const SPEED:          float = 180.0   # px/sec — just under run speed (200)
const CATCH_RADIUS:   float = 14.0    # root triggers within this distance
const CHAKRA_DRAIN:   float = 5.0     # chakra/sec drained from caster
var shadow_id:    String = ""
var caster_id:    int    = 0       # peer_id of caster (server_player key)
var target_id_str: String = ""     # "player_X" or "enemy_X"
var zone:         String = ""

var _drain_acc:   float  = 0.0
var _broadcast_acc: float = 0.0
const BROADCAST_INTERVAL: float = 0.05   # 20Hz position sync

func _ready() -> void:
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	# Resolve target position
	var t_pos = _get_target_pos()
	if t_pos == Vector2.INF:
		_despawn("no_target")
		return

	# Drain caster chakra
	_drain_acc += delta
	if _drain_acc >= 1.0:
		_drain_acc -= 1.0
		var sm = get_tree().root.get_node_or_null("ServerMain")
		if sm:
			var sp = sm.server_players.get(caster_id, null)
			if sp:
				sp.current_chakra = max(0, sp.current_chakra - int(CHAKRA_DRAIN))
				if sp.current_chakra <= 0:
					_despawn("no_chakra")
					return

	# Steer toward target
	var to_target = t_pos - global_position
	var dist      = to_target.length()

	# Catch check
	if dist <= CATCH_RADIUS:
		_apply_root()
		return

	# Steer directly toward target (wall avoidance is client-visual only)
	var move_dir = to_target.normalized()

	global_position += move_dir * SPEED * delta

	# Broadcast position to all clients in zone
	_broadcast_acc += delta
	if _broadcast_acc >= BROADCAST_INTERVAL:
		_broadcast_acc = 0.0
		var net = get_tree().root.get_node_or_null("Network")
		if net:
			net.shadow_move.rpc(shadow_id, global_position)

func _get_target_pos() -> Vector2:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return Vector2.INF
	if target_id_str.begins_with("player_"):
		var tid = target_id_str.substr(7).to_int()
		var sp  = sm.server_players.get(tid, null)
		if sp and not sp.is_dead and sp.zone == zone:
			return sp.world_pos
	else:
		var enemy = sm._enemy_nodes.get(target_id_str, null)
		if enemy and is_instance_valid(enemy) and enemy.zone_name == zone:
			return enemy.global_position
	return Vector2.INF

var _caught: bool = false  # true once shadow has caught its target

func _apply_root() -> void:
	if _caught:
		return
	_caught = true
	const BIG: float = 99999.0  # effectively infinite — cleared by cancel/chakra
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm:
		var result = sm._resolve_target(target_id_str, zone)
		if not result.is_empty():
			var t = result["node"]
			if result["type"] == "player":
				t.apply_root(BIG)
			elif t.has_method("apply_root"):
				t.apply_root(BIG)
		var caster_sp = sm.server_players.get(caster_id, null)
		if caster_sp:
			caster_sp.apply_root(BIG)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.shadow_despawn.rpc(shadow_id, true)  # freeze visual
	# Shadow stays alive — keeps draining chakra until cancel or chakra empty

func _despawn(reason: String = "") -> void:
	print("[SERVER] Shadow %s despawned: %s" % [shadow_id, reason])
	# Clear root on both caster and target
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm:
		var caster_sp = sm.server_players.get(caster_id, null)
		if caster_sp and caster_sp.is_rooted:
			caster_sp.is_rooted  = false
			caster_sp.root_timer = 0.0
			var net0 = get_tree().root.get_node_or_null("Network")
			if net0:
				net0.notify_status_end.rpc_id(caster_sp.peer_id, caster_sp.peer_id, "root")
		var result = sm._resolve_target(target_id_str, zone)
		if not result.is_empty():
			var t = result["node"]
			if result["type"] == "player" and t.is_rooted:
				t.is_rooted  = false
				t.root_timer = 0.0
				var net0b = get_tree().root.get_node_or_null("Network")
				if net0b:
					net0b.notify_status_end.rpc_id(t.peer_id, t.peer_id, "root")
			elif t.has_method("apply_root"):  # enemy
				t.is_rooted  = false
				t._root_timer = 0.0
		sm._shadow_nodes.erase(shadow_id)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		if _caught:
			net.shadow_despawn.rpc(shadow_id + "_clear", false)  # fade frozen line
		else:
			net.shadow_despawn.rpc(shadow_id, false)  # fade chasing line
	queue_free()
