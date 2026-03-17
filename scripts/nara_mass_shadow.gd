extends AbilityBase

# ============================================================
# MASS SHADOW POSSESSION
# Spawns one shadow per target in radius. Each chases and
# roots its target exactly like solo Shadow Possession.
# Drain: 5/sec per active shadow. +10/sec per caught target
# when Shadow Neck Bind is also running.
# ============================================================

const RADIUS:        float = 240.0  # 15 tiles
const CHAKRA_COST:   int   = 40
const DRAIN_PER_SHADOW: float = 5.0
const DRAIN_STRANGLE:   float = 10.0

var _active:           bool  = false
var _drain_timer:      float = 0.0
var _active_count:     int   = 0   # shadows still alive (chasing or caught)
var caught_target_ids: Array = []   # target_id_str of caught targets (updated by gs.gd)
var strangle_active:   bool  = false

func _init() -> void:
	ability_name    = "Mass Shadow Possession"
	description     = "Bind all nearby enemies with your shadow."
	cooldown        = 20.0
	chakra_cost     = CHAKRA_COST
	activation      = "instant"
	icon_color      = Color("3a2080")
	apply_knockback = false

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if _active:
		_cancel(player)
		return true
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	# Server handles chakra cost via spend_chakra in mass_shadow_start handler
	current_cooldown = cooldown
	_active           = true
	_drain_timer      = 0.0
	_active_count     = 0
	caught_target_ids = []
	strangle_active   = false

	# Caster flash
	var spr = player.get_node_or_null("AnimatedSprite2D")
	if spr:
		var tw = player.get_tree().create_tween()
		tw.tween_property(spr, "modulate", Color(0.4, 0.1, 0.7, 1.0), 0.1)
		tw.tween_property(spr, "modulate", Color(1, 1, 1, 1), 0.3)

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "mass_shadow_start", {
			"caster_pos": player.global_position,
			"radius":     RADIUS,
		})
	return true

func drain_tick(_player: Node, _delta: float) -> void:
	pass  # Server-side: each server_shadow instance drains chakra and calls sync_chakra

func _cancel(player: Node) -> void:
	if not _active:
		return
	_active           = false
	_active_count     = 0
	caught_target_ids = []
	strangle_active   = false
	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "mass_shadow_cancel", {})

func is_active() -> bool:
	return _active

func force_cancel() -> void:
	_active           = false
	_active_count     = 0
	caught_target_ids = []
	strangle_active   = false
	current_cooldown  = cooldown
