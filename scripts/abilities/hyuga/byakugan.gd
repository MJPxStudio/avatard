extends AbilityBase

# ============================================================
# BYAKUGAN
# Toggle. Drains 5 chakra/sec while active.
# Effects:
#   - Lock-on range extended to 640px (40 tiles)
#   - Enemy chakra bars visible (broadcast by server on tick)
#   - Cloaked enemies revealed (semi-transparent instead of invisible)
#   - Hyuga palm abilities deal bonus damage
#   - 64 Palms upgrades to 128 Palms
# ============================================================

const DRAIN_PER_SEC:       float = 5.0
const LOCK_RANGE_NORMAL:   float = 480.0
const LOCK_RANGE_BYAKUGAN: float = 640.0

var _active:      bool  = false
var _drain_timer: float = 0.0

func _init() -> void:
	ability_name    = "Byakugan"
	description     = "Activate your Byakugan. Extends vision, reveals enemy chakra, and empowers palm techniques."
	cooldown        = 1.0
	cast_time    = 0.2
	chakra_cost     = 10
	activation      = "instant"
	icon_color      = Color("e8f8ff")
	apply_knockback = false
	tags            = ["toggle", "doujutsu"]

func tick(delta: float) -> void:
	super.tick(delta)

func activate(player: Node) -> bool:
	if _active:
		_deactivate(player)
		return true
	if not is_ready():
		return false
	# Block if Eight Trigrams prime window is active
	if player.hotbar != null:
		for slot in player.hotbar.slots:
			if slot != null and "ability_id" in slot and slot.ability_id == "64_palms":
				if slot.is_primed:
					if player.chat: player.chat.add_system_message("Cannot activate Byakugan during Eight Trigrams window.")
					return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	player.current_chakra -= chakra_cost
	current_cooldown = cooldown
	_active      = true
	_drain_timer = 0.0
	player._update_hud()

	_apply_byakugan_effects(player, true)

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "byakugan_toggle", {"active": true})
	return true

func drain_tick(player: Node, delta: float) -> void:
	if not _active:
		return
	# When connected, server drains chakra authoritatively via sync_chakra.
	# We still check deactivation locally so the UI stays responsive.
	var net = player.get_node_or_null("/root/Network")
	var online: bool = net != null and net.is_network_connected()
	_drain_timer += delta
	if _drain_timer >= 1.0:
		_drain_timer -= 1.0
		if not online:
			# Offline / solo play: drain locally
			player.current_chakra = max(0, player.current_chakra - int(DRAIN_PER_SEC))
			player._update_hud()
		# Both online and offline: auto-deactivate when dry
		if player.current_chakra <= 0:
			_deactivate(player)

func _deactivate(player: Node) -> void:
	if not _active:
		return
	_active = false
	_apply_byakugan_effects(player, false)
	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "byakugan_toggle", {"active": false})

var _tint_layer: CanvasLayer = null
var _tint_rect:  ColorRect   = null

func _get_or_create_tint(player: Node) -> ColorRect:
	if is_instance_valid(_tint_rect):
		return _tint_rect
	# CanvasLayer renders in screen space — immune to camera position/zoom
	_tint_layer           = CanvasLayer.new()
	_tint_layer.layer     = 10   # above world, below HUD (HUD is typically 15+)
	_tint_layer.name      = "ByakuganTint"
	_tint_rect            = ColorRect.new()
	_tint_rect.color      = Color(0.18, 0.52, 1.0, 0.0)   # start fully transparent
	_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Cover the entire viewport regardless of resolution
	_tint_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint_rect.size       = player.get_viewport().get_visible_rect().size
	_tint_layer.add_child(_tint_rect)
	player.add_child(_tint_layer)
	return _tint_rect

func _apply_byakugan_effects(player: Node, on: bool) -> void:
	# Extended lock-on range flag (also used by damage multipliers and cloak reveal)
	if "byakugan_active" in player:
		player.byakugan_active = on

	# Full-screen blue overlay via CanvasLayer — covers the whole camera view
	var rect = _get_or_create_tint(player)
	var tw   = player.get_tree().create_tween()
	tw.tween_property(rect, "color:a", 0.22 if on else 0.0, 0.3)

	# Subtle eye glow on player sprite
	var spr = player.get_node_or_null("AnimatedSprite2D")
	if spr:
		var tw_spr = player.get_tree().create_tween()
		var target_mod = Color(0.7, 0.9, 1.0, 1.0) if on else Color(1.0, 1.0, 1.0, 1.0)
		tw_spr.tween_property(spr, "modulate", target_mod, 0.25)

func is_active() -> bool:
	return _active

func force_cancel() -> void:
	_active = false
	current_cooldown = cooldown
