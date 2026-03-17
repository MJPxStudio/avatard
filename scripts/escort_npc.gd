extends Node2D

# ============================================================
# ESCORT NPC
# Auto-triggers on first login. Locks player controls and
# walks them along a path to the Kage House entrance.
# When path completes, unlocks controls and advances quest.
# ============================================================

@export var walk_path:    Array[Vector2] = []   # waypoints NPC walks through
@export var walk_speed:   float  = 60.0
@export var npc_name_str: String = "Guard"
@export var wait_radius:  float  = 64.0  # pause if player falls behind

var _active:       bool    = false
var _path_index:   int     = 0
var _sprite:       AnimatedSprite2D = null
var _name_label:   Label   = null
var _player:       Node    = null

func _ready() -> void:
	_build_visual()

func _build_visual() -> void:
	_name_label = Label.new()
	_name_label.text     = npc_name_str
	_name_label.position = Vector2(-20, -32)
	_name_label.add_theme_font_size_override("font_size", 8)
	_name_label.add_theme_color_override("font_color", Color("ffffff"))
	_name_label.add_theme_color_override("font_shadow_color", Color(0,0,0,1))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_name_label)

	# Simple colored rect as placeholder sprite
	var rect      = ColorRect.new()
	rect.color    = Color(0.3, 0.5, 0.8, 1.0)
	rect.size     = Vector2(14, 20)
	rect.position = Vector2(-7, -20)
	add_child(rect)

func begin_escort(player: Node) -> void:
	if _active:
		return
	_player = player
	# Show opening dialogue first, then start walking after player dismisses it
	_show_intro_dialogue(player)

func _show_intro_dialogue(player: Node) -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		_start_walking()
		return
	if main.get_node_or_null("DialogueBox") != null:
		_start_walking()
		return
	var pages = [
		"Ah — you must be the new arrival. I've been waiting for you.",
		"The Jonin has requested to meet all newcomers personally.\nFollow me to the Kage House.",
	]
	var box = CanvasLayer.new()
	box.set_script(load("res://scripts/dialogue_box.gd"))
	box.name = "DialogueBox"
	main.add_child(box)
	box.open(npc_name_str, pages, {})
	# Wait for dialogue to close then start walking
	get_tree().create_timer(0.1).timeout.connect(_wait_for_dialogue_close, CONNECT_ONE_SHOT)

func _wait_for_dialogue_close() -> void:
	var main = get_tree().root.get_node_or_null("Main")
	var box = main.get_node_or_null("DialogueBox") if main else null
	if box != null and is_instance_valid(box):
		# Still open — keep polling
		get_tree().create_timer(0.3).timeout.connect(_wait_for_dialogue_close, CONNECT_ONE_SHOT)
	else:
		# Small extra delay so the dialogue fully frees before we lock controls
		get_tree().create_timer(0.3).timeout.connect(_start_walking, CONNECT_ONE_SHOT)

func _start_walking() -> void:
	if walk_path.is_empty():
		push_error("[ESCORT] walk_path is empty! Set waypoints in the Inspector.")
		return
	_active     = true
	_path_index = 0
	set_physics_process(true)
	# Don't lock player — they follow freely
	# Notify server
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.escort_started.rpc_id(1)

func _physics_process(delta: float) -> void:
	if not _active or walk_path.is_empty():
		return
	if _path_index >= walk_path.size():
		_finish_escort()
		return

	var target_pos = walk_path[_path_index]
	var to_target  = target_pos - global_position
	var dist       = to_target.length()

	if dist < 4.0:
		_path_index += 1
	else:
		var move = to_target.normalized() * walk_speed * delta
		global_position += move

func _finish_escort() -> void:
	_active = false
	# Make sure player is never left locked
	var p = get_tree().get_first_node_in_group("local_player")
	if p and p.has_method("set_escort_locked"):
		p.set_escort_locked(false)
	# Mark quest as ready to complete (player still needs to talk to Jonin)
	# The escort_completed signal tells server the escort phase is done
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.escort_completed.rpc_id(1)
	# Fade out and remove self
	var tw = get_tree().create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)
