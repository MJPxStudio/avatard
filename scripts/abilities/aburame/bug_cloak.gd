extends AbilityBase

# ============================================================
# BUG CLOAK
# Toggle. Cover yourself in a defensive layer of kikaichu.
# While active:
#   - 10% damage reduction (server-side in take_damage)
#   - Attackers lose 5 chakra per hit (server-side in take_damage)
#   - Passive aura: drains 2 chakra/sec from enemies within 80px
#     (server-side in server_player._process)
# Server drain: 8 chakra/sec via sync_chakra.
# ============================================================

const DRAIN_PER_SEC: float = 8.0

var _active:      bool  = false
var _drain_timer: float = 0.0

func _init() -> void:
	ability_name    = "Bug Cloak"
	description     = "Coat yourself in kikaichu. Reduces damage taken by 10%, drains attacker chakra, and passively saps nearby enemies."
	cooldown        = 1.0
	cast_time    = 0.2
	chakra_cost     = 35
	activation      = "instant"
	icon_color      = Color("5a7a25")
	apply_knockback = false
	tags            = ["buff", "toggle"]

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if _active:
		_deactivate(player)
		return true
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	current_cooldown = cooldown
	_active      = true
	_drain_timer = 0.0

	_apply_cloak_effects(player, true)

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "bug_cloak_toggle", {"active": true})
	return true

func drain_tick(_player: Node, _delta: float) -> void:
	pass  # Server handles all chakra drain via sync_chakra

func _deactivate(player: Node) -> void:
	if not _active:
		return
	_active = false
	_apply_cloak_effects(player, false)
	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "bug_cloak_toggle", {"active": false})

func _apply_cloak_effects(player: Node, on: bool) -> void:
	player.flash_visual("bug_cloak_start" if on else "bug_cloak_end")
	# Set flag on player for server to read
	if "bug_cloak_active" in player:
		player.bug_cloak_active = on

func is_active() -> bool:
	return _active

func force_cancel() -> void:
	_active = false
	current_cooldown = cooldown
