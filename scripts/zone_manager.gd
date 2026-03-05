extends Node

var pending_spawn: Vector2 = Vector2.ZERO
var pending_zone:  String  = ""

func _ready() -> void:
	# After every scene change, fade in
	get_tree().node_added.connect(_on_node_added)

var _fade_pending: bool = false

func _on_node_added(node: Node) -> void:
	if node.is_in_group("local_player") and not _fade_pending:
		_fade_pending = true
		call_deferred("_do_fade_in")

func _do_fade_in() -> void:
	_fade_pending = false
	# Find camera
	var camera = get_tree().get_first_node_in_group("camera")
	if camera == null:
		return
	var fade = ColorRect.new()
	fade.color        = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vsize     = get_viewport().get_visible_rect().size
	fade.size     = vsize
	fade.position = -vsize / 2.0
	camera.add_child(fade)
	var tween = get_tree().create_tween()
	tween.tween_property(fade, "color", Color(0, 0, 0, 0), 0.4)
	tween.tween_callback(fade.queue_free)

func apply_spawn(player: Node) -> void:
	if pending_spawn != Vector2.ZERO:
		player.global_position = pending_spawn
		player.grid_pos        = pending_spawn
		player.target_pos      = pending_spawn
	pending_spawn = Vector2.ZERO
