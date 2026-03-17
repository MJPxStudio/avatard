extends AbilityBase

# ============================================================
# EIGHT TRIGRAMS: 64 / 128 PALMS
#
# Phase 1 — Prime (client-only):
#   Deducts chakra, opens a 15-second window.  The player must
#   land a basic Lunge during that window to trigger the combo.
#   Byakugan cannot be toggled while primed.
#   If the window expires without a hit: cooldown is applied,
#   chakra is NOT refunded.
#
# Phase 2 — Cinematic (server-driven):
#   Server detects the lunge hit, roots caster + target, and
#   chains 64 (or 128 with Byakugan) hits × 0.5 s with per-hit
#   chakra drain on the target.  All clients see the cinematic.
# ============================================================

const CHAKRA_64:    int   = 100
const CHAKRA_128:   int   = 200
const PRIME_DUR:    float = 15.0
const COOLDOWN_SEC: float = 14.0

var _prime_timer: float = 0.0
var _timer_bar:   Node  = null   # ColorRect bar added to player HUD
var _bar_bg:      Node  = null

func _init() -> void:
	ability_name    = "Eight Trigrams: 64 Palms"
	description     = "Prime a window. Land a Lunge to trigger a 64-hit (128 with Byakugan) palm strike chain."
	cooldown        = COOLDOWN_SEC
	cast_stand_still = true
	cast_time    = 0.7
	chakra_cost     = CHAKRA_64
	activation      = "instant"
	icon_color      = Color("2090ee")
	apply_knockback = false

func tick(delta: float) -> void:
	super.tick(delta)
	if not is_primed:
		return
	_prime_timer -= delta
	_update_bar()
	if _prime_timer <= 0.0:
		# Window expired without landing a hit
		var player = _bar_bg.get_parent().get_parent() if _bar_bg else null
		_expire_prime(player)

func activate(player: Node) -> bool:
	if not is_ready():
		return false
	# Byakugan check
	var byakugan_on: bool = false
	if player.hotbar != null:
		for slot in player.hotbar.slots:
			if slot != null and "ability_id" in slot and slot.ability_id == "byakugan":
				if slot.has_method("is_active") and slot.is_active():
					byakugan_on = true
					break
	var cost: int = CHAKRA_128 if byakugan_on else CHAKRA_64
	if player.current_chakra < cost:
		if player.chat: player.chat.add_system_message("Not enough chakra.")
		return false
	# Deduct chakra + start cooldown — server confirms and deducts authoritatively
	current_cooldown = COOLDOWN_SEC
	ability_name = "Eight Trigrams: 128 Palms" if byakugan_on else "Eight Trigrams: 64 Palms"
	# Open prime window — local HUD only; server tracks palms_primed separately
	is_primed     = true
	_prime_timer  = PRIME_DUR
	_show_timer_bar(player)
	if player.chat:
		player.chat.add_system_message("Eight Trigrams primed — land a Lunge within 15s!")
	# Notify server to set prime flag and deduct chakra
	var net = player.get_node_or_null("/root/Network")
	if net and net.is_network_connected():
		net.send_ability.rpc_id(1, "prime_palms", {"byakugan": byakugan_on})
	return true

# Called by gs.gd when the cinematic starts (lunge connected successfully)
func clear_prime() -> void:
	is_primed    = false
	_prime_timer = 0.0
	_destroy_bar()

# Called internally when the 15s window expires without a hit
func _expire_prime(player: Node) -> void:
	is_primed    = false
	_prime_timer = 0.0
	_destroy_bar()
	if player and player.chat:
		player.chat.add_system_message("Eight Trigrams window expired.")

# ── HUD timer bar ─────────────────────────────────────────────────────────

func _show_timer_bar(player: Node) -> void:
	_destroy_bar()
	if player.hud == null:
		return
	# Background track
	var bg := ColorRect.new()
	bg.color         = Color(0.1, 0.1, 0.15, 0.8)
	bg.size          = Vector2(180, 10)
	bg.position      = Vector2(8, -16)   # just above the HUD frame
	bg.z_index       = 30
	player.hud.add_child(bg)
	_bar_bg = bg
	# Fill bar
	var bar := ColorRect.new()
	bar.color    = Color(0.2, 0.65, 1.0, 0.9)
	bar.size     = Vector2(180, 10)
	bar.position = Vector2.ZERO
	bar.z_index  = 31
	bg.add_child(bar)
	_timer_bar = bar
	# Label
	var lbl := Label.new()
	lbl.text                                  = "Eight Trigrams — Land a Lunge"
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.93, 1.0, 1.0))
	lbl.position = Vector2(0, -12)
	lbl.z_index  = 32
	bg.add_child(lbl)

func _update_bar() -> void:
	if _timer_bar == null or not is_instance_valid(_timer_bar):
		return
	var pct: float = clampf(_prime_timer / PRIME_DUR, 0.0, 1.0)
	_timer_bar.size.x = 180.0 * pct
	# Pulse red in the last 5 seconds
	if _prime_timer < 5.0:
		var pulse: float = abs(sin(_prime_timer * TAU * 2.0))
		_timer_bar.color = Color(0.9, 0.2 + pulse * 0.2, 0.1 + pulse * 0.1, 0.9)
	else:
		_timer_bar.color = Color(0.2, 0.65, 1.0, 0.9)

func _destroy_bar() -> void:
	if _bar_bg != null and is_instance_valid(_bar_bg):
		_bar_bg.queue_free()
	_bar_bg   = null
	_timer_bar = null
