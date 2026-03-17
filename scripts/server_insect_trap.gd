extends ServerTrapBase

# ============================================================
# SERVER INSECT TRAP
# Placed bug trap. When triggered: roots target + DoT.
# ============================================================

var root_duration:  float = 3.0
var dmg_per_tick:   int   = 8
var tick_interval:  float = 1.0
var tick_count:     int   = 6

func _ready() -> void:
	trap_type      = "insect_trap"
	trigger_radius = 20.0   # ~1.25 tiles
	lifetime       = 45.0
	max_triggers   = 1
	super._ready()

func _on_triggered(target: Node, is_enemy: bool) -> void:
	var sm = get_tree().root.get_node_or_null("ServerMain")
	if is_enemy:
		target.apply_root(root_duration)
		target.apply_dot(dmg_per_tick, tick_interval, tick_count, caster_id)
		if sm:
			sm._emit_visual(target.enemy_id, "bug_hit")
			Network.confirm_ability_hit.rpc_id(caster_id, target.global_position, dmg_per_tick)
	else:
		target.apply_rooted_visual(root_duration)
		target.apply_dot(dmg_per_tick, tick_interval, tick_count, caster_id)
		if sm:
			sm._emit_visual(str(target.peer_id), "bug_hit")
			Network.confirm_ability_hit.rpc_id(caster_id, target.world_pos, dmg_per_tick)
