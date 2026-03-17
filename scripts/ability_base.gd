extends Resource
class_name AbilityBase

# ============================================================
# ABILITY BASE — All abilities extend this
# Abilities are slottable just like items
# ============================================================

@export var ability_name:  String = "Unnamed"
var ability_id:    String = ""   # set by AbilityDB.create_instance
@export var description:   String = ""
@export var cooldown:      float  = 3.0
@export var chakra_cost:   int    = 20
@export var activation:    String = "instant"  # "instant" | "hold" | "toggle"
@export var cast_time:     float  = 0.0           # seconds to cast before firing (0 = instant)
@export var cast_stand_still: bool = false          # if true, movement is locked during cast
var tags:              Array  = []  # "instant" or "targeted"

# ── Hold-to-charge fields (activation = "hold") ──────────────────────────
@export var charge_duration: float = 1.5   # seconds to full charge
@export var charge_min:      float = 0.3   # minimum hold before release fires
var _charge_accum: float = 0.0             # 0..1 progress while held
var _is_charging:  bool  = false

@export var icon_color:    Color  = Color("ffffff")

# Hit effect flags — set per ability
@export var apply_knockback: bool = true
@export var apply_stun:      bool = false   # future
@export var apply_snare:     bool = false   # future

# Runtime state
var current_cooldown:   float = 0.0
var effective_cooldown: float = 0.0   # actual cooldown after boon reductions — set on cast
var is_primed:          bool  = false   # for targeted abilities

# Slottable interface (matches item interface)
var quantity:   int     = 1
var stackable:  bool    = false
var is_ability: bool    = true
var icon_path:  String  = ""   # optional sprite path

func is_ready() -> bool:
	return current_cooldown <= 0.0

func tick(delta: float) -> void:
	if current_cooldown > 0.0:
		current_cooldown = max(0.0, current_cooldown - delta)

func get_cooldown_percent() -> float:
	var base = effective_cooldown if effective_cooldown > 0.0 else cooldown
	if base <= 0.0:
		return 0.0
	return current_cooldown / base

# Override in subclasses.
# For "instant"/"toggle": called on key press.
# For "hold": called when minimum hold met — use on_charged for release.
func activate(player: Node) -> bool:
	return false

# ── Hold-to-charge lifecycle ─────────────────────────────────────────────
# Called every frame while the key is held (ratio = 0..1 charge progress)
func on_charging(player: Node, delta: float, ratio: float) -> void:
	pass

# Called when key is released after charge_min is reached.
# ratio = how fully charged (0..1). Return true if the ability fired.
func on_charged(player: Node, ratio: float) -> bool:
	return false

# Called if the charge is interrupted (movement, stun, cancel key, death)
func on_charge_cancelled(player: Node) -> void:
	pass

# Internal: tick charge accumulator. Called by hotbar each frame key is held.
func tick_charge(player: Node, delta: float) -> void:
	if activation != "hold":
		return
	_is_charging = true
	_charge_accum = min(_charge_accum + delta / charge_duration, 1.0)
	on_charging(player, delta, _charge_accum)

# Internal: called on key release. Returns true if ability fired.
func release_charge(player: Node) -> bool:
	if not _is_charging:
		return false
	var ratio = _charge_accum
	_charge_accum = 0.0
	_is_charging  = false
	if ratio < (charge_min / charge_duration):
		on_charge_cancelled(player)
		return false
	return on_charged(player, ratio)

# Internal: cancel charge without firing
func cancel_charge(player: Node) -> void:
	if _is_charging:
		_charge_accum = 0.0
		_is_charging  = false
		on_charge_cancelled(player)

# Override for abilities that need server processing
func server_activate(peer_id: int, data: Dictionary) -> void:
	pass
