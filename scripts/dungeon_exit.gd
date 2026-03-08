extends Node2D

# ============================================================
# DUNGEON EXIT — walk into it to leave the dungeon
# ============================================================

func _ready() -> void:
	var lbl = Label.new()
	lbl.text = "[Exit]"
	lbl.position = Vector2(-16, -20)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	add_child(lbl)

	var vis = ColorRect.new()
	vis.size     = Vector2(32, 8)
	vis.position = Vector2(-16, -4)
	vis.color    = Color(0.3, 0.5, 0.8, 0.7)
	add_child(vis)

	var area   = Area2D.new()
	area.collision_layer = 0
	area.collision_mask  = 1
	var shape  = CollisionShape2D.new()
	var rect   = RectangleShape2D.new()
	rect.size  = Vector2(32, 16)
	shape.shape = rect
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)

var _transitioning: bool = false
var _ready_timer:   float = 1.5

func _process(delta: float) -> void:
	if _ready_timer > 0.0:
		_ready_timer -= delta

func _on_body_entered(body: Node) -> void:
	if _transitioning or _ready_timer > 0.0:
		return
	if body.is_in_group("local_player"):
		_transitioning = true
		var net = get_tree().root.get_node_or_null("Network")
		if net and net.is_network_connected():
			net.request_dungeon_exit.rpc_id(1)
