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
@export var activation:    String = "instant"  # "instant" or "targeted"
@export var icon_color:    Color  = Color("ffffff")

# Hit effect flags — set per ability
@export var apply_knockback: bool = true
@export var apply_stun:      bool = false   # future
@export var apply_snare:     bool = false   # future

# Runtime state
var current_cooldown: float = 0.0
var is_primed:        bool  = false   # for targeted abilities

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
	if cooldown <= 0.0:
		return 0.0
	return current_cooldown / cooldown

# Override in subclasses
func activate(player: Node) -> bool:
	return false

# Override for abilities that need server processing
func server_activate(peer_id: int, data: Dictionary) -> void:
	pass
