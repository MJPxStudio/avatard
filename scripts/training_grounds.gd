extends Node2D

# ============================================================
# TRAINING GROUNDS
# Manages the q_basic_training objectives:
#   Phase 1 — Touch 3 waypoint orbs (teaches movement)
#   Phase 2 — Land 3 melee attacks (teaches combat)
#   Phase 3 — Dash 3 times (teaches dash)
# Notifies server when all phases complete.
# ============================================================

const WAYPOINT_COUNT = 3
const MELEE_REQUIRED = 3
const DASH_REQUIRED  = 3

var _phase:         int   = 0   # 0=inactive 1=waypoints 2=melee 3=dash 4=done
var _progress:      int   = 0
var _waypoints:     Array = []
var _player:        Node  = null
var _objective_hud: Node  = null

# Waypoint spawn positions (relative to training grounds origin)
const WAYPOINT_POSITIONS = [
	Vector2(-80, -40),
	Vector2(  0, -80),
	Vector2( 80, -40),
]

func _ready() -> void:
	add_to_group("training_grounds")
	set_process(false)

func activate(player: Node, objective_hud: Node) -> void:
	_player        = player
	_objective_hud = objective_hud
	_phase         = 1
	_progress      = 0
	set_process(true)
	_spawn_waypoints()
	_update_hud()

func _spawn_waypoints() -> void:
	_clear_waypoints()
	for wp_pos in WAYPOINT_POSITIONS:
		var orb = Node2D.new()
		orb.set_script(load("res://scripts/waypoint_orb.gd"))
		orb.global_position = global_position + wp_pos
		orb.touched.connect(_on_waypoint_touched.bind(orb))
		get_tree().current_scene.add_child(orb)
		_waypoints.append(orb)

func _clear_waypoints() -> void:
	for w in _waypoints:
		if is_instance_valid(w):
			w.queue_free()
	_waypoints.clear()

func _on_waypoint_touched(orb: Node) -> void:
	if _phase != 1:
		return
	if is_instance_valid(orb):
		orb.queue_free()
	_waypoints.erase(orb)
	_progress += 1
	_update_hud()
	if _progress >= WAYPOINT_COUNT:
		_advance_phase()

func notify_melee_hit() -> void:
	if _phase != 2:
		return
	_progress += 1
	_update_hud()
	if _progress >= MELEE_REQUIRED:
		_advance_phase()

func notify_dash() -> void:
	if _phase != 3:
		return
	_progress += 1
	_update_hud()
	if _progress >= DASH_REQUIRED:
		_advance_phase()

func _advance_phase() -> void:
	_phase    += 1
	_progress  = 0
	_clear_waypoints()
	match _phase:
		2:  # melee phase
			_update_hud()
		3:  # dash phase
			_update_hud()
		4:  # complete
			_on_training_complete()

func _on_training_complete() -> void:
	set_process(false)
	# Clear player reference so hooks stop firing
	if _player and is_instance_valid(_player):
		_player.training_grounds = null
	if _objective_hud:
		_objective_hud.show_objective("Basic Training", "Return to Jonin Takeda.")
	# Notify server training is done (advances quest progress)
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.training_complete.rpc_id(1)

func _update_hud() -> void:
	if not _objective_hud:
		return
	if not _objective_hud.has_method("show_objective"):
			return
	match _phase:
		1:
			_objective_hud.show_objective(
				"Basic Training",
				"Touch the waypoint orbs.",
				"%d / %d" % [_progress, WAYPOINT_COUNT]
			)
		2:
			_objective_hud.show_objective(
				"Basic Training",
				"Land 3 lunge attacks. (Press attack while moving)",
				"%d / %d" % [_progress, MELEE_REQUIRED]
			)
		3:
			_objective_hud.show_objective(
				"Basic Training",
				"Dash 3 times. (Press [Space] while moving)",
				"%d / %d" % [_progress, DASH_REQUIRED]
			)

func _process(_delta: float) -> void:
	# Check for nearby enemies as melee targets during phase 2
	pass
