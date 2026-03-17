extends RefCounted

# ============================================================
# DUNGEON GENERATOR
# Generates a floor layout as a graph of rooms
# Each room has: id, type, connections, enemy_spawns, cleared
# ============================================================

const RoomDB = preload("res://scripts/dungeon_room_db.gd")

# Generate a full floor layout
# Returns { rooms: Dict[id -> room_data], start_id, boss_id, room_order: Array }
static func generate_floor(
	difficulty:    String,
	floor_index:   int,
	theme_data,              # reference to theme (e.g. WolfDenData)
	dungeon_level: int = 1,  # dungeon min_level — controls door count and rarity
) -> Dictionary:

	var cfg = _get_difficulty_cfg(difficulty)
	var room_count = randi_range(cfg.min_rooms, cfg.max_rooms)

	var rooms      = {}
	var room_id    = 0
	var start_id   = 0
	var boss_id    = -1

	# Start room
	rooms[room_id] = _make_room(room_id, RoomDB.RoomType.START, [], 0, theme_data)
	var prev_id    = room_id
	room_id       += 1

	var main_path  = [start_id]
	var mid_count  = room_count - 2  # exclude start and boss

	var safe_count = 0
	var max_safe   = max(1, mid_count / 3)

	for i in range(mid_count):
		var exclude = [RoomDB.RoomType.START, RoomDB.RoomType.BOSS]
		if safe_count >= max_safe:
			exclude.append(RoomDB.RoomType.SHOP)
			exclude.append(RoomDB.RoomType.REST)
		# Never allow a safe room directly before the boss
		if i == mid_count - 1:
			exclude.append(RoomDB.RoomType.SHOP)
			exclude.append(RoomDB.RoomType.REST)

		var type  = RoomDB.weighted_random_type(exclude)
		var cfg_r = RoomDB.get_room_config(type)
		if cfg_r.get("safe", false):
			safe_count += 1

		var points = theme_data.get_floor_points(difficulty, floor_index) if cfg_r.get("points", 0) == 0 and not cfg_r.get("safe", false) else cfg_r.get("points", 0)
		var spawns = theme_data.fill_room(points, difficulty) if not cfg_r.get("safe", false) and type in [RoomDB.RoomType.COMBAT, RoomDB.RoomType.ELITE] else []

		# Claim this room's ID and advance the counter FIRST.
		# This means room_id is always "next free slot" after this line.
		var this_id = room_id
		room_id    += 1

		rooms[this_id] = _make_room(this_id, type, [prev_id], points, theme_data, spawns)
		rooms[prev_id]["connections"].append(this_id)

		# Branch rooms disabled — linear layout only until branching is fully supported
		# if i < mid_count - 1 and randf() < 0.25 and mid_count > 4:
		#	var branch_type   = RoomDB.weighted_random_type([RoomDB.RoomType.START, RoomDB.RoomType.BOSS, RoomDB.RoomType.MINIBOSS])
		#	var branch_points = theme_data.get_floor_points(difficulty, floor_index) if branch_type == RoomDB.RoomType.COMBAT else 0
		#	var branch_spawns = theme_data.fill_room(branch_points, difficulty) if branch_type == RoomDB.RoomType.COMBAT else []
		#	var branch_id     = room_id
		#	room_id          += 1
		#	rooms[branch_id]  = _make_room(branch_id, branch_type, [this_id], branch_points, theme_data, branch_spawns)
		#	rooms[this_id]["connections"].append(branch_id)

		main_path.append(this_id)
		prev_id = this_id
		# room_id already points to the next free slot — do not modify it here

	# Boss room — always the next free slot after all mid rooms
	boss_id         = room_id
	rooms[boss_id]  = _make_room(boss_id, RoomDB.RoomType.BOSS, [prev_id], 0, theme_data)
	rooms[prev_id]["connections"].append(boss_id)
	main_path.append(boss_id)
	room_id += 1

	# Treasure room — always directly after the boss, auto-clears, holds floor exit
	var treasure_id    = room_id
	rooms[treasure_id] = _make_room(treasure_id, RoomDB.RoomType.TREASURE, [boss_id], 0, theme_data)
	rooms[boss_id]["connections"].append(treasure_id)
	main_path.append(treasure_id)

	# ── Assign door rewards to every room's connections ─────────
	# Each non-boss connection gets a reward type stamped on the SOURCE room.
	# door_rewards: { target_room_id: RewardType }
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var door_range = RoomDB.doors_for_level(dungeon_level)
	for rid in rooms:
		var room = rooms[rid]
		var conns: Array = room.get("connections", [])
		if conns.is_empty():
			continue
		# Boss room connections always go to treasure — no choice
		if rid == boss_id:
			room["door_rewards"] = { conns[0]: RoomDB.RewardType.BOSS }
			continue
		# Treasure and start rooms: single exit, no reward label
		if room.get("type") in [RoomDB.RoomType.TREASURE, RoomDB.RoomType.START]:
			room["door_rewards"] = {}
			for c in conns:
				room["door_rewards"][c] = RoomDB.RewardType.BOON  # treated as pass-through
			continue
		# If this room connects to the boss — single Boss door, no reward choice
		if boss_id in conns:
			room["door_rewards"] = {"0": {"room_id": boss_id, "reward": RoomDB.RewardType.BOSS}}
			room["next_room_id"] = boss_id
			continue
		# This way we always show multiple doors regardless of branch count.
		# door_rewards format: { "0": reward_a, "1": reward_b } — index-keyed, not room-keyed.
		# dungeon_world shows one door per entry; player choice stored by reward type.
		var num_doors = rng.randi_range(door_range[0], door_range[1])
		var next_room = conns[0] if not conns.is_empty() else -1
		var door_rewards = {}
		var chosen_rewards: Array = []
		for i in range(num_doors):
			var reward = RoomDB.random_reward(rng)
			# No UPGRADE on floor 1 — player won't have boons yet
			if reward == RoomDB.RewardType.UPGRADE and floor_index == 0:
				reward = RoomDB.RewardType.BOON
			var attempts = 0
			while reward in chosen_rewards and attempts < 8:
				reward = RoomDB.random_reward(rng)
				if reward == RoomDB.RewardType.UPGRADE and floor_index == 0:
					reward = RoomDB.RewardType.BOON
				attempts += 1
			chosen_rewards.append(reward)
			# Key by index string — all doors lead to next_room but offer different rewards
			door_rewards[str(i)] = {"room_id": next_room, "reward": reward}
		room["door_rewards"] = door_rewards
		room["next_room_id"] = next_room

	return {
		"rooms":         rooms,
		"start_id":      start_id,
		"boss_id":       boss_id,
		"treasure_id":   treasure_id,
		"room_order":    main_path,
		"floor_index":   floor_index,
		"difficulty":    difficulty,
		"dungeon_level": dungeon_level,
	}

static func _make_room(
	id:         int,
	type:       int,
	from:       Array,
	points:     int,
	theme_data,
	spawns:     Array = [],
) -> Dictionary:
	var size = _room_size(type)
	return {
		"id":          id,
		"type":        type,
		"label":       RoomDB.get_room_config(type).get("label", "Room"),
		"connections": [],
		"from":        from,
		"points":      points,
		"spawns":      spawns,
		"cleared":     false,
		"safe":        RoomDB.get_room_config(type).get("safe", false),
		"tiles_w":     size[0],
		"tiles_h":     size[1],
	}

# Returns [tiles_w, tiles_h] — never smaller than the 960x540 viewport (30x17 tiles).
# All values are even so rooms centre cleanly on the origin.
static func _room_size(type: int) -> Array:
	match type:
		RoomDB.RoomType.START:
			return [32, 20]
		RoomDB.RoomType.COMBAT:
			var w = [32, 34, 36, 38, 40][randi() % 5]
			var h = [20, 22, 24, 26][randi() % 4]
			return [w, h]
		RoomDB.RoomType.ELITE:
			var w = [36, 38, 40, 42][randi() % 4]
			var h = [22, 24, 26, 28][randi() % 4]
			return [w, h]
		RoomDB.RoomType.MINIBOSS:
			var w = [40, 42, 44, 46][randi() % 4]
			var h = [26, 28, 30][randi() % 3]
			return [w, h]
		RoomDB.RoomType.BOSS:
			var w = [48, 50, 52, 54][randi() % 4]
			var h = [32, 34, 36][randi() % 3]
			return [w, h]
		RoomDB.RoomType.SHOP:
			return [32, 20]
		RoomDB.RoomType.REST:
			return [32, 20]
		RoomDB.RoomType.TREASURE:
			var w = [34, 36, 38][randi() % 3]
			var h = [22, 24][randi() % 2]
			return [w, h]
	return [32, 20]  # fallback

static func _get_difficulty_cfg(difficulty: String) -> Dictionary:
	match difficulty:
		"easy":   return { "min_rooms": 4,  "max_rooms": 6  }
		"medium": return { "min_rooms": 6,  "max_rooms": 9  }
		"hard":   return { "min_rooms": 8,  "max_rooms": 12 }
	return { "min_rooms": 4, "max_rooms": 6 }
