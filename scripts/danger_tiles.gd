extends Node

# ============================================================
# DANGER TILES — reusable client-side warning grid
#
# Usage:
#   var handle = DangerTiles.spawn(pos, radius, duration, color)
#   DangerTiles.despawn(handle)          # cancel early
#   DangerTiles.grow(handle, new_radius) # expand radius mid-life
# ============================================================

const TILE_SIZE    = 16
const BASE_FLASH_INTERVAL = 0.6   # slow flash early
const FAST_FLASH_INTERVAL = 0.08  # rapid flash in last 2 seconds

var _active: Dictionary = {}  # handle -> { node, timer, duration, flash_timer, flash_on, radius, color }
var _counter: int = 0

func spawn(pos: Vector2, radius: float, duration: float, color: Color = Color(1.0, 0.35, 0.0, 0.55)) -> int:
	var handle = _counter
	_counter  += 1

	var scene_root = get_tree().current_scene
	if scene_root == null:
		return handle

	var container      = Node2D.new()
	container.z_index  = 2
	container.global_position = pos
	scene_root.add_child(container)

	var entry = {
		"node":        container,
		"pos":         pos,
		"duration":    duration,
		"elapsed":     0.0,
		"flash_timer": 0.0,
		"flash_on":    true,
		"radius":      radius,
		"color":       color,
	}
	_active[handle] = entry
	_rebuild_grid(entry)
	return handle

func despawn(handle: int) -> void:
	if not _active.has(handle):
		return
	var entry = _active[handle]
	if is_instance_valid(entry["node"]):
		entry["node"].queue_free()
	_active.erase(handle)

func grow(handle: int, new_radius: float) -> void:
	if not _active.has(handle):
		return
	var entry = _active[handle]
	entry["radius"] = new_radius
	_rebuild_grid(entry)

func _process(delta: float) -> void:
	for handle in _active.keys().duplicate():
		var entry = _active[handle]
		if not is_instance_valid(entry["node"]):
			_active.erase(handle)
			continue

		entry["elapsed"] += delta
		var remaining = entry["duration"] - entry["elapsed"]

		# Flash interval speeds up in last 2 seconds
		var interval = lerp(BASE_FLASH_INTERVAL, FAST_FLASH_INTERVAL,
			clampf(1.0 - (remaining / 2.0), 0.0, 1.0))

		entry["flash_timer"] += delta
		if entry["flash_timer"] >= interval:
			entry["flash_timer"] = 0.0
			entry["flash_on"]    = not entry["flash_on"]
			entry["node"].visible = entry["flash_on"]

		if entry["elapsed"] >= entry["duration"]:
			if is_instance_valid(entry["node"]):
				entry["node"].queue_free()
			_active.erase(handle)

func _rebuild_grid(entry: Dictionary) -> void:
	var container: Node2D = entry["node"]
	var radius:    float  = entry["radius"]
	var color:     Color  = entry["color"]

	# Clear existing tiles
	for child in container.get_children():
		child.queue_free()

	# Fill circle with 16x16 tiles
	var r_tiles = int(ceil(radius / TILE_SIZE))
	for tx in range(-r_tiles, r_tiles + 1):
		for ty in range(-r_tiles, r_tiles + 1):
			var cx = (tx + 0.5) * TILE_SIZE
			var cy = (ty + 0.5) * TILE_SIZE
			if Vector2(cx, cy).length() <= radius:
				var rect        = ColorRect.new()
				rect.size       = Vector2(TILE_SIZE - 1, TILE_SIZE - 1)  # 1px gap for grid look
				rect.position   = Vector2(tx * TILE_SIZE, ty * TILE_SIZE)
				rect.color      = color
				container.add_child(rect)
