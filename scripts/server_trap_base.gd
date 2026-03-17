extends Node2D
class_name ServerTrapBase

# ============================================================
# SERVER TRAP BASE — framework for all trap abilities.
# Place at a world position. Sits until an enemy/hostile player
# walks within trigger_radius, then fires _on_triggered() once.
#
# Subclass and override _on_triggered(target, is_enemy) to
# define the trap's effect, OR configure the built-in params
# directly and let the base handle it.
#
# To add a new trap:
#   1. Create a script extending ServerTrapBase
#   2. Set vars in _ready() or from the spawner
#   3. Override _on_triggered() for custom effects
#   4. Add a new trap_type string and matching visual in trap_visual_base.gd
# ============================================================

var trap_id:        String  = ""
var caster_id:      int     = 0        # peer_id of caster
var zone:           String  = ""
var trap_type:      String  = "base"   # used by client to pick visual
var lifetime:       float   = 30.0     # despawn if never triggered
var trigger_radius: float   = 20.0     # px — overlap = trigger
var hits_enemies:   bool    = true
var hits_players:   bool    = true     # hostile players only (no party)
var max_triggers:   int     = 1        # 1 = single use; -1 = infinite

var _lifetime_left: float   = 0.0
var _trigger_count: int     = 0
var _hit_ids:       Array   = []       # avoid retriggering same target

func _ready() -> void:
	_lifetime_left = lifetime
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_lifetime_left -= delta
	if _lifetime_left <= 0.0:
		print("[TRAP] %s expired" % trap_id)
		_despawn(false)
		return

	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm == null:
		return

	if hits_enemies:
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if enemy.zone_name != zone or enemy.is_dead:
				continue
			if _hit_ids.has(enemy.enemy_id):
				continue
			var dist = enemy.global_position.distance_to(global_position)
			if dist <= trigger_radius:
				print("[TRAP] %s triggered by enemy %s dist=%.1f" % [trap_id, enemy.enemy_id, dist])
				_hit_ids.append(enemy.enemy_id)
				_on_triggered(enemy, true)
				_trigger_count += 1
				if max_triggers > 0 and _trigger_count >= max_triggers:
					_despawn(true)
					return

	if hits_players:
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
			var dist = other.world_pos.distance_to(global_position)
			if dist <= trigger_radius:
				print("[TRAP] %s triggered by player %d dist=%.1f" % [trap_id, oid, dist])
				_hit_ids.append(pid_str)
				_on_triggered(other, false)
				_trigger_count += 1
				if max_triggers > 0 and _trigger_count >= max_triggers:
					_despawn(true)
					return

# Override in subclasses to define the trap effect
func _on_triggered(target: Node, is_enemy: bool) -> void:
	pass

func _despawn(triggered: bool) -> void:
	set_physics_process(false)
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.trap_despawn.rpc(trap_id, triggered)
		net.trap_despawned.emit(trap_id, triggered)
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if sm and sm._trap_nodes.has(trap_id):
		sm._trap_nodes.erase(trap_id)
	queue_free()
