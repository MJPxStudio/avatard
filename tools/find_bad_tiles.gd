@tool
extends EditorScript

func _run() -> void:
	for scene_path in ["res://scenes/village.tscn", "res://scenes/open_world.tscn"]:
		print("[TILE CHECK] Scanning %s..." % scene_path)
		var packed = load(scene_path)
		if packed == null:
			print("[TILE CHECK] Could not load %s" % scene_path)
			continue
		var scene = packed.instantiate()
		_check_node(scene)
		scene.free()
	print("[TILE CHECK] Done.")

func _check_node(node: Node) -> void:
	print("[TILE CHECK] Node: %s (%s)" % [node.name, node.get_class()])
	if node is TileMap:
		_scan_tilemap(node)
	elif node.get_class() == "TileMapLayer":
		_scan_tilemaplayer(node)
	for child in node.get_children():
		_check_node(child)

func _scan_tilemap(node: TileMap) -> void:
	print("[TILE CHECK] Scanning TileMap: %s" % node.name)
	var ts = node.tile_set
	if ts == null:
		print("[TILE CHECK]   No TileSet.")
		return
	for layer in range(node.get_layers_count()):
		for cell in node.get_used_cells(layer):
			var source_id = node.get_cell_source_id(layer, cell)
			var atlas_coords = node.get_cell_atlas_coords(layer, cell)
			if not ts.has_source(source_id):
				print("[TILE CHECK]   BAD SOURCE at cell %s layer %d source_id %d" % [str(cell), layer, source_id])
				continue
			var source = ts.get_source(source_id)
			if source is TileSetAtlasSource:
				if not source.has_tile(atlas_coords):
					print("[TILE CHECK]   BAD TILE at cell %s layer %d atlas %s source %d" % [str(cell), layer, str(atlas_coords), source_id])

func _scan_tilemaplayer(node: Node) -> void:
	print("[TILE CHECK] Scanning TileMapLayer: %s" % node.name)
	var ts = node.get("tile_set")
	if ts == null:
		print("[TILE CHECK]   No TileSet.")
		return
	var cells = node.get_used_cells()
	for cell in cells:
		var source_id = node.get_cell_source_id(cell)
		var atlas_coords = node.get_cell_atlas_coords(cell)
		if not ts.has_source(source_id):
			print("[TILE CHECK]   BAD SOURCE at cell %s source_id %d" % [str(cell), source_id])
			continue
		var source = ts.get_source(source_id)
		if source is TileSetAtlasSource:
			if not source.has_tile(atlas_coords):
				print("[TILE CHECK]   BAD TILE at cell %s atlas %s source %d" % [str(cell), str(atlas_coords), source_id])
