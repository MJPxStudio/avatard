extends AbilityBase

# ============================================================
# SHADOW POSSESSION JUTSU — toggle ability.
#
# First press:  spend initial chakra, send shadow_possession_start to server.
#               Server spawns ServerShadow, broadcasts shadow_spawn to all clients.
#               Client drains chakra each second while active.
#
# Second press: send shadow_possession_cancel. Server despawns shadow.
#
# Auto-cancel:  when client chakra hits 0, sends cancel automatically.
# Server also despawns if chakra runs out server-side (safety net).
# ============================================================

const RANGE:         float = 320.0
const CHAKRA_DRAIN:  float = 5.0    # per second — matches server_shadow.gd
var _active:         bool  = false
var strangle_active: bool  = false
var caught_target_id: String = ""  # set when shadow catches its target  # set by shadow_strangle when DoT is running
var _drain_timer:    float = 0.0

func _init() -> void:
	ability_name    = "Shadow Possession"
	description     = "Send your shadow to chase and bind an enemy. Hold drains chakra."
	cooldown        = 20.0
	chakra_cost     = 15    # initial cost to cast
	activation      = "instant"
	icon_color      = Color("4a3060")
	apply_knockback = false

# Called by hotbar each frame while this ability is in a slot
func tick(delta: float) -> void:
	super.tick(delta)  # ticks cooldown only

func activate(player: Node) -> bool:
	# Toggle off
	if _active:
		_cancel(player)
		return true

	# Toggle on
	if not is_ready():
			return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false
	var target = player.locked_target
	if target == null or not is_instance_valid(target):
		if player.chat: player.chat.add_system_message("No target selected.")
		return false
	if player.global_position.distance_to(target.global_position) > RANGE:
		if player.chat: player.chat.add_system_message("Target out of range.")
		return false

	# Server handles chakra cost and ongoing drain via server_shadow.gd
	_active       = true
	_drain_timer  = 0.0
	current_cooldown = 0.0

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		caught_target_id = player.locked_target_id
		net.send_ability.rpc_id(1, "shadow_possession_start", {
			"caster_pos": player.global_position,
			"target_id":  player.locked_target_id,
			"range":      RANGE,
		})
	return true

func _cancel(player: Node) -> void:
	if not _active:
		return
	_active = false
	strangle_active = false
	caught_target_id = ""
	current_cooldown = cooldown
	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "shadow_possession_cancel", {})

# Called by player.gd each frame while this ability is active
func drain_tick(_player: Node, _delta: float) -> void:
	pass  # Server-side: server_shadow.gd drains chakra and calls sync_chakra each second

func is_active() -> bool:
	return _active

# Called by gs.gd when server reports shadow resolved — no need to send cancel RPC
func force_cancel() -> void:
	if not _active:
		return
	_active = false
	strangle_active = false
	caught_target_id = ""
	current_cooldown = cooldown
