class_name ServerClayBomb
extends RefCounted

# ============================================================
# SERVER CLAY BOMB — 4 growth stages over 10 seconds
# Stage timing: 2.5s each
# Kagura detonation: half damage at current stage
# ============================================================

const STAGE_DURATION: float = 2.5
const TOTAL_STAGES:   int   = 4

# Stage definitions: [radius, damage]
const STAGES: Array = [
	[60.0,  40],
	[100.0, 70],
	[150.0, 100],
	[200.0, 140],
]

var bomb_id:      String  = ""
var peer_id:      int     = 0
var zone:         String  = ""
var pos:          Vector2 = Vector2.ZERO
var cast_room_id: int     = -1  # dungeon room where bomb was placed
var done:      bool    = false
var radius_mult: float = 1.0  # boon_c3_radius_mult
var invisible:   bool  = false  # c3_invisible passive

var current_stage: int   = 0   # 0-indexed, 0 = stage 1
var stage_timer:   float = STAGE_DURATION

# Callbacks
var on_stage_change: Callable = Callable()  # func(stage: int, radius: float)
var on_explode:      Callable = Callable()  # func(pos: Vector2, radius: float, damage: int)

func step(delta: float) -> void:
	if done:
		return

	stage_timer -= delta
	if stage_timer <= 0.0:
		stage_timer = STAGE_DURATION
		if current_stage < TOTAL_STAGES - 1:
			current_stage += 1
			if on_stage_change.is_valid():
				on_stage_change.call(current_stage, STAGES[current_stage][0] * radius_mult)
		else:
			# Max stage reached — detonate
			_detonate(false)

func detonate_early() -> void:
	if done:
		return
	_detonate(true)

func get_current_radius() -> float:
	return STAGES[current_stage][0]

func get_current_damage(kagura: bool = false) -> int:
	var dmg: int = STAGES[current_stage][1]
	return dmg / 2 if kagura else dmg

func _detonate(kagura: bool) -> void:
	if done:
		return
	done = true
	var radius: float = get_current_radius() * radius_mult
	var damage: int   = get_current_damage(kagura)
	if on_explode.is_valid():
		on_explode.call(pos, radius, damage)
