@tool
extends EditorScript

func _run() -> void:
	var scene = load("res://scenes/village.tscn").instantiate()
	print("[TILE CHECK] Scanning village.tscn...")
	_check_node(scene)
	scene.free()
	print("[TILE CHECK] Done.")

func _check_node(node: Node) -> void:
	if node is TileMap:
		print("[TILE CHECK] Found TileMap: %s" % node.name)
		var ts = node.tile_set
		if ts == null:
			print("[TILE CHECK]   No TileSet assigned.")
			return
		for layer in range(node.get_layers_count()):
			for cell in node.get_used_cells(layer):
				var source_id = node.get_cell_source_id(layer, cell)
				var atlas_coords = node.get_cell_atlas_coords(layer, cell)
				if not ts.has_source(source_id):
					print("[TILE CHECK]   BAD SOURCE at cell %s layer %d — source_id %d does not exist" % [str(cell), layer, source_id])
					continue
				var source = ts.get_source(source_id)
				if source is TileSetAtlasSource:
					if not source.has_tile(atlas_coords):
						print("[TILE CHECK]   BAD TILE at cell %s layer %d — atlas_coords %s not in source %d" % [str(cell), layer, str(atlas_coords), source_id])
	for child in node.get_children():
		_check_node(child)
