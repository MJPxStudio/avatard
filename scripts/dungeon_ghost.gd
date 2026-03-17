extends CanvasLayer

# ============================================================
# DUNGEON GHOST MODE (client-side)
# Active when local player dies inside a dungeon.
# Locks player movement, free-camera follows a living teammate.
# Arrow UI cycles spectate targets.
# Chat still works.
# Removed on checkpoint revive or dungeon end.
# ============================================================

var _target_index:   int    = 0
var _living_peers:   Array  = []   # peer_ids of living players
var _panel:          Control = null
var _status_lbl:     Label  = null
var _left_btn:       Button = null
var _right_btn:      Button = null
var _target_lbl:     Label  = null
var _spectating_lbl: Label  = null

signal revived()

func _ready() -> void:
	layer   = 45
	visible = false
	_build_ui()
	var net = get_tree().root.get_node_or_null("Network")
	if net:
		net.checkpoint_revived.connect(_on_checkpoint_revive)
		net.dungeon_wiped_received.connect(_on_wiped)
		net.dungeon_complete_received.connect(_on_complete)
		net.player_became_ghost_received.connect(_on_someone_became_ghost)

func _build_ui() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top    = -60
	_panel.offset_bottom = 0
	add_child(_panel)

	_spectating_lbl = Label.new()
	_spectating_lbl.text = "SPECTATING"
	_spectating_lbl.anchor_left  = 0.5; _spectating_lbl.anchor_right = 0.5
	_spectating_lbl.offset_left  = -80; _spectating_lbl.offset_right = 80
	_spectating_lbl.offset_top   = 0;   _spectating_lbl.offset_bottom = 16
	_spectating_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectating_lbl.add_theme_font_size_override("font_size", 9)
	_spectating_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 1.0, 0.85))
	_panel.add_child(_spectating_lbl)

	_left_btn = Button.new()
	_left_btn.text         = "◄"
	_left_btn.offset_left  = -120; _left_btn.offset_right  = -80
	_left_btn.offset_top   = 18;   _left_btn.offset_bottom = 42
	_left_btn.anchor_left  = 0.5;  _left_btn.anchor_right  = 0.5
	_left_btn.pressed.connect(_cycle_prev)
	_panel.add_child(_left_btn)

	_target_lbl = Label.new()
	_target_lbl.anchor_left  = 0.5; _target_lbl.anchor_right = 0.5
	_target_lbl.offset_left  = -74; _target_lbl.offset_right = 74
	_target_lbl.offset_top   = 20;  _target_lbl.offset_bottom = 40
	_target_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_lbl.add_theme_font_size_override("font_size", 9)
	_target_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_panel.add_child(_target_lbl)

	_right_btn = Button.new()
	_right_btn.text         = "►"
	_right_btn.offset_left  = 80;  _right_btn.offset_right  = 120
	_right_btn.offset_top   = 18;  _right_btn.offset_bottom = 42
	_right_btn.anchor_left  = 0.5; _right_btn.anchor_right  = 0.5
	_right_btn.pressed.connect(_cycle_next)
	_panel.add_child(_right_btn)

func activate(living_peers: Array) -> void:
	_living_peers = living_peers.duplicate()
	_target_index = 0
	visible       = true
	_update_target_label()
	# Lock local player movement
	var lp = get_tree().get_first_node_in_group("local_player")
	if lp:
		lp.set_physics_process(false)
		lp.modulate = Color(0.5, 0.5, 1.0, 0.5)   # ghostly tint
	_attach_camera_to_target()

func deactivate() -> void:
	visible = false
	var lp = get_tree().get_first_node_in_group("local_player")
	if lp:
		lp.set_physics_process(true)
		lp.modulate = Color(1.0, 1.0, 1.0, 1.0)
		# Clear death state so _physics_process doesn't early-return anymore
		lp.is_dead = false
		lp.current_hp = max(1, lp.max_hp / 2)
		if lp.has_method("_update_hud"):
			lp._update_hud()
		# Clear respawn screen if one was shown
		if lp.get("respawn_screen") != null and is_instance_valid(lp.respawn_screen):
			lp.respawn_screen.queue_free()
			lp.respawn_screen = null
	_detach_camera()
	revived.emit()

func _on_checkpoint_revive(peer_ids: Array, revive_pos: Vector2) -> void:
	var my_id = multiplayer.get_unique_id()
	if my_id not in peer_ids:
		return
	var lp = get_tree().get_first_node_in_group("local_player")
	if lp:
		# Move player to revive position before re-enabling physics
		lp.global_position = revive_pos
	deactivate()
	# Re-clamp camera to dungeon room bounds after reparent may have cleared limits
	var gs = get_tree().root.get_node_or_null("GameState")
	var dw = gs.world_node if gs and gs.get("world_node") else null
	if dw and dw.has_method("_clamp_camera"):
		dw._clamp_camera()

func _cycle_prev() -> void:
	if _living_peers.is_empty():
		return
	_target_index = (_target_index - 1 + _living_peers.size()) % _living_peers.size()
	_update_target_label()
	_attach_camera_to_target()

func _cycle_next() -> void:
	if _living_peers.is_empty():
		return
	_target_index = (_target_index + 1) % _living_peers.size()
	_update_target_label()
	_attach_camera_to_target()

func _update_target_label() -> void:
	if _living_peers.is_empty():
		_target_lbl.text = "No survivors"
		return
	var pid = _living_peers[_target_index]
	var gs  = get_tree().root.get_node_or_null("GameState")
	var name_str = str(pid)
	if gs and gs.has_method("get_player_name"):
		name_str = gs.get_player_name(pid)
	_target_lbl.text = name_str

func _attach_camera_to_target() -> void:
	if _living_peers.is_empty():
		return
	var pid = _living_peers[_target_index]
	var gs  = get_tree().root.get_node_or_null("GameState")
	if not gs:
		return
	var target_node = gs.remote_player_nodes.get(pid, null)
	if not target_node or not is_instance_valid(target_node):
		return
	# Move local player's camera to follow the spectate target
	var lp = get_tree().get_first_node_in_group("local_player")
	if not lp:
		return
	var cam = lp.get_node_or_null("Camera2D")
	if not cam:
		return
	# Reparent camera to spectate target
	var old_parent = cam.get_parent()
	if old_parent:
		old_parent.remove_child(cam)
	target_node.add_child(cam)
	cam.global_position = target_node.global_position

func _detach_camera() -> void:
	var lp = get_tree().get_first_node_in_group("local_player")
	if not lp:
		return
	var cam = lp.get_node_or_null("Camera2D")
	# Camera may have been reparented — find it and put it back
	if not cam:
		# Search all remote player nodes for the camera
		var gs = get_tree().root.get_node_or_null("GameState")
		if gs:
			for pid in gs.remote_player_nodes:
				var rp = gs.remote_player_nodes[pid]
				cam = rp.get_node_or_null("Camera2D")
				if cam:
					rp.remove_child(cam)
					break
	if cam:
		lp.add_child(cam)
		cam.position = Vector2.ZERO

func _on_someone_became_ghost(peer_id: int) -> void:
	# Remove from living list if they were being spectated
	_living_peers.erase(peer_id)
	if _living_peers.is_empty():
		_target_lbl.text = "No survivors"
		return
	_target_index = _target_index % _living_peers.size()
	_update_target_label()
	_attach_camera_to_target()

func _on_wiped(_exit_scene: String, _exit_pos: Vector2) -> void:
	deactivate()

func _on_complete() -> void:
	deactivate()
