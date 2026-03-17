class_name ServerClayOwl
extends RefCounted

# ============================================================
# SERVER CLAY OWL
# Phase 1 — TRAVEL: flies toward target at TRAVEL_SPEED.
# Phase 2 — ORBIT:  circles caster's LIVE target at ORBIT_RADIUS,
#           dropping a spider toward that target every DROP_INTERVAL.
# Phase 3 — DASH:   when timer expires, dashes in the direction of
#           the current target (not homing) then explodes.
# On early destruction: explodes immediately.
# ============================================================

const TRAVEL_SPEED:    float = 240.0
const ORBIT_RADIUS:    float = 220.0  # doubled again from 110
const ORBIT_SPEED:     float = 2.2    # radians per second
const ORBIT_DURATION:  float = 5.0
const DROP_INTERVAL:   float = 1.0
const DASH_SPEED:      float = 320.0
const DASH_HIT_RADIUS: float = 24.0   # explode when this close to target
const DASH_TIMEOUT:    float = 3.0    # safety — explode after this many seconds regardless
const OWL_HP:          int   = 3
const EXPLOSION_DMG:   int   = 64
const EXPLOSION_RADIUS:float = 96.0

enum Phase { TRAVEL, ORBIT, DASH, DEAD }

var owl_id:      String  = ""
var peer_id:     int     = 0
var zone:        String  = ""
var cast_room_id: int    = -1  # dungeon room where owl was cast
var pos:         Vector2 = Vector2.ZERO
var target_id:   String  = ""   # initial target — updated each step from sp.locked_target_id
var phase:       Phase   = Phase.TRAVEL
var hp:          int     = OWL_HP
var done:        bool    = false

# Orbit state
var orbit_angle:  float  = 0.0
var orbit_timer:  float  = ORBIT_DURATION
var drop_timer:   float  = 0.0

# Dash state
var dash_dir:     Vector2 = Vector2.ZERO
var dash_timer:   float   = DASH_TIMEOUT  # safety timeout
var homing_on_dash: bool  = false  # c2_homing_dash passive

# Callbacks set by server_main
var on_drop_spider: Callable = Callable()   # func(pos: Vector2, aim_dir: Vector2)
var on_explode:     Callable = Callable()   # func(pos: Vector2)
var on_sync:        Callable = Callable()   # func(pos: Vector2, dir_str: String)

func step(delta: float, target_pos: Vector2, caster_target_id: String) -> void:
	if done:
		return
	# Keep target_id in sync with caster's live target
	if caster_target_id != "":
		target_id = caster_target_id

	match phase:
		Phase.TRAVEL:
			_step_travel(delta, target_pos)
		Phase.ORBIT:
			_step_orbit(delta, target_pos)
		Phase.DASH:
			_step_dash(delta, target_pos)

func _step_travel(delta: float, target_pos: Vector2) -> void:
	var dir  = target_pos - pos
	var dist = dir.length()
	if dist <= ORBIT_RADIUS or dist <= TRAVEL_SPEED * delta:
		phase        = Phase.ORBIT
		orbit_angle  = (pos - target_pos).angle()
		drop_timer   = DROP_INTERVAL  # first drop after one interval
		return
	dir = dir.normalized()
	pos += dir * TRAVEL_SPEED * delta
	_sync_visual(dir)

func _step_orbit(delta: float, target_pos: Vector2) -> void:
	orbit_angle += ORBIT_SPEED * delta
	pos = target_pos + Vector2(cos(orbit_angle), sin(orbit_angle)) * ORBIT_RADIUS

	var tangent = Vector2(-sin(orbit_angle), cos(orbit_angle))
	_sync_visual(tangent)

	# Drop spider aimed at target
	drop_timer -= delta
	if drop_timer <= 0.0:
		drop_timer = DROP_INTERVAL
		var aim = (target_pos - pos).normalized()
		if aim == Vector2.ZERO:
			aim = Vector2.RIGHT
		if on_drop_spider.is_valid():
			on_drop_spider.call(pos, aim)

	# When orbit expires, dash toward current target
	orbit_timer -= delta
	if orbit_timer <= 0.0:
		dash_dir   = (target_pos - pos).normalized()
		if dash_dir == Vector2.ZERO:
			dash_dir = Vector2.RIGHT
		phase      = Phase.DASH
		dash_timer = DASH_TIMEOUT

func _step_dash(delta: float, target_pos: Vector2) -> void:
	# Homing boon — continuously steer toward target during dash
	if homing_on_dash:
		var to_target = target_pos - pos
		if to_target.length() > 4.0:
			dash_dir = to_target.normalized()
	pos        += dash_dir * DASH_SPEED * delta
	dash_timer -= delta
	_sync_visual(dash_dir)
	if pos.distance_to(target_pos) <= DASH_HIT_RADIUS or dash_timer <= 0.0:
		_trigger_explosion()

func take_hit() -> void:
	if done:
		return
	hp -= 1
	if hp <= 0:
		_trigger_explosion()

func _trigger_explosion() -> void:
	if done:
		return
	done  = true
	phase = Phase.DEAD
	if on_explode.is_valid():
		on_explode.call(pos)

func _sync_visual(dir: Vector2) -> void:
	if not on_sync.is_valid():
		return
	var dir_str: String
	if abs(dir.x) >= abs(dir.y):
		dir_str = "right" if dir.x >= 0.0 else "left"
	else:
		dir_str = "down" if dir.y >= 0.0 else "up"
	on_sync.call(pos, dir_str)
