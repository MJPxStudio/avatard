extends Node2D

# ============================================================
# DUNGEON PORTAL (client-side)
# Place in a zone scene. Set dungeon_id in the editor/script.
# Shows a prompt label, sends enter request to server on walk-in.
# ============================================================

@export var dungeon_id: String = "cave_of_trials"

var _prompt:        Label    = null
var _proximity:     Area2D   = null
var _trigger:       Area2D   = null
var _player_near:   bool     = false
var _transitioning: bool     = false
var _ready_timer:   float    = 1.5   # ignore triggers for first 1.5s after scene load

func _ready() -> void:
	_build_visual()
	_build_prompt()
	_build_proximity_area()
	_build_trigger_area()

func _build_visual() -> void:
	# Dark cave entrance rectangle
	var rect  = ColorRect.new()
	rect.size     = Vector2(32, 40)
	rect.position = Vector2(-16, -40)
	rect.color    = Color(0.08, 0.06, 0.06, 1.0)
	add_child(rect)

	# Doorway arch (top strip, darker)
	var arch  = ColorRect.new()
	arch.size     = Vector2(32, 8)
	arch.position = Vector2(-16, -48)
	arch.color    = Color(0.15, 0.10, 0.08, 1.0)
	add_child(arch)

	# Label above
	var lbl = Label.new()
	lbl.text = "Dungeon"
	lbl.position = Vector2(-24, -64)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3, 1.0))
	add_child(lbl)

func _build_prompt() -> void:
	_prompt = Label.new()
	_prompt.text = "[E] Enter Dungeon"
	_prompt.position = Vector2(-40, -80)
	_prompt.add_theme_font_size_override("font_size", 8)
	_prompt.add_theme_color_override("font_color", Color(1, 1, 0.8, 1))
	_prompt.visible = false
	add_child(_prompt)

func _build_proximity_area() -> void:
	_proximity = Area2D.new()
	_proximity.collision_layer = 0
	_proximity.collision_mask  = 1   # local player layer
	var shape  = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 40
	shape.shape   = circle
	_proximity.add_child(shape)
	_proximity.body_entered.connect(_on_proximity_entered)
	_proximity.body_exited.connect(_on_proximity_exited)
	add_child(_proximity)

func _build_trigger_area() -> void:
	_trigger = Area2D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask  = 1
	var shape = CollisionShape2D.new()
	var rect  = RectangleShape2D.new()
	rect.size     = Vector2(28, 36)
	shape.shape   = rect
	_trigger.add_child(shape)
	_trigger.body_entered.connect(_on_trigger_entered)
	add_child(_trigger)

func _on_proximity_entered(body: Node) -> void:
	if body.is_in_group("local_player"):
		_player_near = true
		_prompt.visible = true

func _on_proximity_exited(body: Node) -> void:
	if body.is_in_group("local_player"):
		_player_near = false
		_prompt.visible = false

func _process(delta: float) -> void:
	if _ready_timer > 0.0:
		_ready_timer -= delta

func _on_trigger_entered(body: Node) -> void:
	if _transitioning or _ready_timer > 0.0:
		return
	if body.is_in_group("local_player"):
		_transitioning = true
		_do_enter()

func _do_enter() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if not net or not net.is_network_connected():
		_transitioning = false
		return
	# Send enter request to server — server validates and responds with
	# dungeon_enter_accepted or dungeon_enter_denied
	net.request_dungeon_enter.rpc_id(1, dungeon_id)

func reset_transition() -> void:
	_transitioning = false
