extends Area2D
class_name ZoneDoor

var destination_scene: String  = ""
var destination_zone:  String  = ""
var spawn_position:    Vector2 = Vector2.ZERO

var _transitioning: bool  = false
var _prompt:        Label = null

func _ready() -> void:
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	_build_prompt()
	_build_proximity_area()

func _build_prompt() -> void:
	_prompt                      = Label.new()
	_prompt.visible              = false
	_prompt.z_index              = 10
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 10)
	_prompt.add_theme_color_override("font_color",        Color(1.0, 1.0, 0.5, 1.0))
	_prompt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_prompt)
	# destination_zone is set before add_child in world scripts so it's available now
	call_deferred("_finalize_prompt")

func _finalize_prompt() -> void:
	var zone_name    = destination_zone if destination_zone != "" else "???"
	_prompt.text     = "[ %s ]" % zone_name
	_prompt.position = Vector2(-50, -28)

func _build_proximity_area() -> void:
	# Separate larger Area2D — shows label when player is nearby,
	# without triggering the transition
	var prox               = Area2D.new()
	prox.collision_mask    = 1
	prox.name              = "ProximityArea"
	var shape              = CollisionShape2D.new()
	var rect               = RectangleShape2D.new()
	rect.size              = Vector2(224, 224)  # ~7 tiles in all directions
	shape.shape            = rect
	prox.add_child(shape)
	add_child(prox)
	prox.body_entered.connect(_on_proximity_entered)
	prox.body_exited.connect(_on_proximity_exited)

func _on_proximity_entered(body: Node) -> void:
	if body is CharacterBody2D and body.is_in_group("local_player"):
		if _prompt:
			_prompt.visible = true

func _on_proximity_exited(body: Node) -> void:
	if body is CharacterBody2D and body.is_in_group("local_player"):
		if _prompt:
			_prompt.visible = false

func _on_body_entered(body: Node) -> void:
	if _transitioning:
		return
	if body is CharacterBody2D and body.is_in_group("local_player"):
		_transitioning = true
		_do_transition()

func _do_transition() -> void:
	if destination_scene == "":
		push_error("[ZONE DOOR] No destination_scene set!")
		_transitioning = false
		return
	if not ResourceLoader.exists(destination_scene):
		print("[ZONE DOOR] Scene not found: %s" % destination_scene)
		_transitioning = false
		return
	var main = get_tree().root.get_node_or_null("Main")
	if main and main.has_method("transition_to_zone"):
		main.transition_to_zone(destination_scene, spawn_position)
	else:
		push_error("[ZONE DOOR] Main node not found")
