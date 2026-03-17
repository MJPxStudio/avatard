extends AbilityBase

# ============================================================
# PARASITE INSECT JUTSU
# Phase 1 — Prime: deducts chakra, opens a 15s window.
#   Player must land a basic Lunge to implant the bugs.
# Phase 2 — Server-driven: on lunge hit, server triggers
#   a chakra drain DoT on the target (players) or HP DoT
#   (enemies, which have no chakra). Deals base melee damage.
# ============================================================

const CHAKRA_COST:   int   = 25
const PRIME_DUR:     float = 15.0
const COOLDOWN_SEC:  float = 8.0

var _prime_timer: float = 0.0
var _bar_bg:      Node  = null
var _timer_bar:   Node  = null
var _player_ref:  Node  = null   # stored on bar creation, avoids node-hierarchy guessing

func _init() -> void:
	ability_name    = "Parasite Insect Jutsu"
	description     = "Prime a window. Land a Lunge to implant kikaichu that drain the target's chakra."
	cooldown        = COOLDOWN_SEC
	cast_time    = 0.3
	chakra_cost     = CHAKRA_COST
	activation      = "instant"
	icon_color      = Color("3d5a1e")
	apply_knockback = false
	tags            = ["dot", "debuff"]

func tick(delta: float) -> void:
	super.tick(delta)
	if not is_primed:
		return
	_prime_timer -= delta
	_update_bar()
	if _prime_timer <= 0.0:
		_expire_prime(_player_ref)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	if player.current_chakra < chakra_cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false

	current_cooldown = COOLDOWN_SEC
	is_primed        = true
	_prime_timer     = PRIME_DUR
	_show_timer_bar(player)

	if player.chat:
		player.chat.add_system_message("Parasite primed — land a Lunge within 15s!")

	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "parasite_prime", {})
	return true

func clear_prime() -> void:
	is_primed    = false
	_prime_timer = 0.0
	_destroy_bar()

func _expire_prime(player: Node) -> void:
	is_primed    = false
	_prime_timer = 0.0
	_destroy_bar()
	if player and player.chat:
		player.chat.add_system_message("Parasite window expired.")

# ── HUD timer bar ──────────────────────────────────────────────────────────

func _show_timer_bar(player: Node) -> void:
	_destroy_bar()
	_player_ref = player
	if player.hud == null:
		return
	var bg := ColorRect.new()
	bg.color    = Color(0.05, 0.1, 0.05, 0.8)
	bg.size     = Vector2(180, 10)
	bg.position = Vector2(8, -16)
	bg.z_index  = 30
	player.hud.add_child(bg)
	_bar_bg = bg
	var bar := ColorRect.new()
	bar.color    = Color(0.35, 0.65, 0.1, 0.9)
	bar.size     = Vector2(180, 10)
	bar.position = Vector2.ZERO
	bar.z_index  = 31
	bg.add_child(bar)
	_timer_bar = bar
	var lbl := Label.new()
	lbl.text = "Parasite — Land a Lunge"
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.9, 0.3, 1.0))
	lbl.position = Vector2(0, -12)
	lbl.z_index  = 32
	bg.add_child(lbl)

func _update_bar() -> void:
	if _timer_bar == null or not is_instance_valid(_timer_bar):
		return
	var pct: float = clampf(_prime_timer / PRIME_DUR, 0.0, 1.0)
	_timer_bar.size.x = 180.0 * pct
	if _prime_timer < 5.0:
		var pulse: float = abs(sin(_prime_timer * TAU * 2.0))
		_timer_bar.color = Color(0.7, 0.4 + pulse * 0.2, 0.0, 0.9)
	else:
		_timer_bar.color = Color(0.35, 0.65, 0.1, 0.9)

func _destroy_bar() -> void:
	if _bar_bg != null and is_instance_valid(_bar_bg):
		_bar_bg.queue_free()
	_bar_bg     = null
	_timer_bar  = null
	_player_ref = null
