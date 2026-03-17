extends Area2D

# ============================================================
# TRAINING TRIGGER ZONE
# Place in the training area scene.
# When the local player walks in while q_basic_training is
# active, activates the TrainingGrounds node.
# ============================================================

@export var training_grounds_path: NodePath = NodePath("")

var _triggered: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask  = 1
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	if not body.is_in_group("local_player"):
		return
	var qs = body.quest_state if "quest_state" in body else {}
	# Activate if q_basic_training is active OR if player has any intro quest active (for testing)
	if qs.get("q_basic_training", {}).get("status") != "active":
			return
	_triggered = true
	_activate(body)

func _activate(player: Node) -> void:
	var tg: Node = null
	if training_grounds_path != NodePath(""):
		tg = get_node_or_null(training_grounds_path)
		# Fallback — search the world node (village scene) not current_scene (Main)
	if tg == null:
		var gs = get_tree().root.get_node_or_null("GameState")
		var world = gs.world_node if gs and "world_node" in gs else null
		if world:
			tg = world.get_node_or_null("TrainingGrounds")
			# Last resort — find by group or search whole tree
	if tg == null:
		for node in get_tree().get_nodes_in_group("training_grounds"):
			tg = node
			break
	if tg == null or not tg.has_method("activate"):
		push_error("[TRAINING TRIGGER] Could not find TrainingGrounds node.")
		return
	var obj_hud = player.get_meta("objective_hud") if player.has_meta("objective_hud") else null
	tg.activate(player, obj_hud)
	# Set reference on player so attack/dash hooks can find it
	player.training_grounds = tg
