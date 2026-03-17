extends Node2D

# ============================================================
# NPC — Interactable character with multi-page dialogue.
# dialogue is an Array of pages, each page is a String.
# Player presses interact (F) while in proximity to talk.
# ============================================================

const QuestDB = preload("res://scripts/quest_db.gd")

@export var npc_name:           String        = "NPC"
@export var dialogue:          Array[String] = []   # one entry per dialogue page
@export var opens_mission_board: bool          = false  # tick for Mission Assignment Jonin

var _in_range:    bool  = false
var _prompt:      Label = null
var _quest_indicator: Label = null

func _ready() -> void:
	add_to_group("npc")
	_build_visual()
	_build_proximity()

func _build_visual() -> void:
	# Quest indicator (! or ?) — always visible when quest is available
	_quest_indicator = Label.new()
	_quest_indicator.visible  = false
	_quest_indicator.z_index  = 11
	_quest_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_indicator.add_theme_font_size_override("font_size", 14)
	_quest_indicator.add_theme_color_override("font_color",        Color(1.0, 0.85, 0.1, 1.0))
	_quest_indicator.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_quest_indicator.add_theme_constant_override("shadow_offset_x", 1)
	_quest_indicator.add_theme_constant_override("shadow_offset_y", 1)
	_quest_indicator.text     = "!"
	_quest_indicator.position = Vector2(-6, -52)
	add_child(_quest_indicator)

	# Prompt label above NPC — hidden until player is nearby
	_prompt                      = Label.new()
	_prompt.visible              = false
	_prompt.z_index              = 10
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 9)
	_prompt.add_theme_color_override("font_color",        Color(1.0, 1.0, 0.5, 1.0))
	_prompt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_prompt.text     = "[F] Talk"
	_prompt.position = Vector2(-22, -36)
	add_child(_prompt)

func _build_proximity() -> void:
	var area            = Area2D.new()
	area.collision_mask = 1
	area.name           = "ProximityArea"
	var shape           = CollisionShape2D.new()
	var rect            = RectangleShape2D.new()
	rect.size           = Vector2(64, 64)
	shape.shape         = rect
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_proximity_entered)
	area.body_exited.connect(_on_proximity_exited)

func _process(_delta: float) -> void:
	_update_quest_indicator()

func _update_quest_indicator() -> void:
	if _quest_indicator == null:
		return
	var player = get_tree().get_first_node_in_group("local_player")
	if player == null:
		_quest_indicator.visible = false
		return
	var ctx = QuestDB.get_quest_context(npc_name, player.quest_state)
	if ctx.is_empty():
		_quest_indicator.visible = false
		return
	if ctx["action"] == "offer":
		_quest_indicator.text    = "!"
		_quest_indicator.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1, 1.0))
	else:
		_quest_indicator.text    = "?"
		_quest_indicator.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 1.0))
	_quest_indicator.visible = true

func _on_proximity_entered(body: Node) -> void:
	if body is CharacterBody2D and body.is_in_group("local_player"):
		_in_range = true
		if _prompt:
			_prompt.visible = true

func _on_proximity_exited(body: Node) -> void:
	if body is CharacterBody2D and body.is_in_group("local_player"):
		_in_range = false
		if _prompt:
			_prompt.visible = false

func _input(event: InputEvent) -> void:
	if not _in_range:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F:
			_open_dialogue()

func _open_dialogue() -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	# Single player reference used throughout
	var player = get_tree().get_first_node_in_group("local_player")
	var qs = player.quest_state if player else {}
	var ctx = QuestDB.get_quest_context(npc_name, qs)
	# Notify server — used for deliver mission completion checks
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.is_network_connected():
		net.notify_npc_talk.rpc_id(1, npc_name)
	# Open mission board if flagged and no quest to complete
	if opens_mission_board and ctx.is_empty():
		var board = player.get_meta("mission_board") if player and player.has_meta("mission_board") else null
		if board:
			board.open()
		return
	# Check no dialogue already open
	if main.get_node_or_null("DialogueBox") != null:
		return
	var pages: Array
	if not ctx.is_empty():
		pages = ctx["pages"]
	elif not dialogue.is_empty():
		pages = dialogue
	else:
		return
	var box = CanvasLayer.new()
	box.set_script(load("res://scripts/dialogue_box.gd"))
	box.name = "DialogueBox"
	main.add_child(box)
	box.open(npc_name, pages, ctx)
