extends Area2D
class_name ZoneDoor

var destination_scene: String  = ""
var destination_zone:  String  = ""
var spawn_position:    Vector2 = Vector2.ZERO

var _transitioning: bool = false

func _ready() -> void:
	collision_mask = 1
	body_entered.connect(_on_body_entered)

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
	# Hand off to Main immediately — Main handles the fade
	var main = get_tree().root.get_node_or_null("Main")
	if main and main.has_method("transition_to_zone"):
		main.transition_to_zone(destination_scene, spawn_position)
	else:
		push_error("[ZONE DOOR] Main node not found")
