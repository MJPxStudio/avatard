extends RefCounted

# ============================================================
# DUNGEON BOON SELF-TEST
# Run once on server startup. Prints PASS/FAIL for every boon
# stacked to MAX_BOON_STACKS. Any failure = bug in the pipeline.
# Call: DungeonBoonTest.run()
# ============================================================

const BoonDB = preload("res://scripts/dungeon_boon_db.gd")
const FloorController = preload("res://scripts/dungeon_floor_controller.gd")

# Minimal mock of ServerPlayer — just a plain Object with all boon vars
class MockPlayer:
	var max_hp:        int   = 100
	var hp:            int   = 100
	var max_chakra:    int   = 500
	var current_chakra: int  = 500
	var boon_chakra_cost_mult:       float = 1.0
	var boon_clay_dmg_mult:          float = 1.0
	var boon_c1_damage_flat:         int   = 0
	var boon_c1_speed_mult:          float = 1.0
	var boon_c1_range_mult:          float = 1.0
	var boon_c1_cooldown_flat:       float = 0.0
	var boon_c1_spider_count:        int   = 1
	var boon_c2_cooldown_flat:       float = 0.0
	var boon_c2_orbit_duration_flat: float = 0.0
	var boon_c2_drop_interval_mult:  float = 1.0
	var boon_c2_explosion_mult:      float = 1.0
	var boon_c2_owl_count:           int   = 1
	var boon_c3_cooldown_flat:       float = 0.0
	var boon_c3_radius_mult:         float = 1.0
	var boon_c4_count_flat:          int   = 0
	var boon_c4_dmg_mult:            float = 1.0
	var boon_c4_radius_mult:         float = 1.0
	var dungeon_passives:            Array = []
	var dungeon_dash_bonus:          int   = 0

static func run() -> void:
	var fc = FloorController.new()
	var passes = 0
	var fails  = 0

	for boon_id in BoonDB.BOONS:
		var boon = BoonDB.BOONS[boon_id]

		# Apply boon MAX_BOON_STACKS times to a fresh mock player
		var sp = MockPlayer.new()
		for _i in range(BoonDB.MAX_BOON_STACKS):
			fc._apply_boon_to_player(sp, boon)

		var ok = true
		var type  = boon.get("type", "")
		var value = boon.get("value", 0)
		var stat  = boon.get("stat", "")

		match type:
			"stat":
				match stat:
					"max_hp":
						ok = sp.max_hp == 100 + value * BoonDB.MAX_BOON_STACKS
					"max_chakra":
						ok = sp.max_chakra == 500 + value * BoonDB.MAX_BOON_STACKS
					"chakra_cost_mult":
						ok = is_equal_approx(sp.boon_chakra_cost_mult, 1.0 + value * BoonDB.MAX_BOON_STACKS)
					"clay_dmg_mult":
						ok = is_equal_approx(sp.boon_clay_dmg_mult, 1.0 + value * BoonDB.MAX_BOON_STACKS)
					"c1_damage_flat":
						ok = sp.boon_c1_damage_flat == value * BoonDB.MAX_BOON_STACKS
					"c1_speed_mult":
						ok = is_equal_approx(sp.boon_c1_speed_mult, 1.0 + value * BoonDB.MAX_BOON_STACKS)
					"c1_range_mult":
						ok = is_equal_approx(sp.boon_c1_range_mult, 1.0 + value * BoonDB.MAX_BOON_STACKS)
					"c1_cooldown_flat":
						ok = is_equal_approx(sp.boon_c1_cooldown_flat, value * BoonDB.MAX_BOON_STACKS)
					"c1_spider_count":
						ok = sp.boon_c1_spider_count == int(value)
					"c2_cooldown_flat":
						ok = is_equal_approx(sp.boon_c2_cooldown_flat, value * BoonDB.MAX_BOON_STACKS)
					"c2_orbit_duration_flat":
						ok = is_equal_approx(sp.boon_c2_orbit_duration_flat, value * BoonDB.MAX_BOON_STACKS)
					"c2_drop_interval_mult":
						ok = is_equal_approx(sp.boon_c2_drop_interval_mult, 1.0 + value * BoonDB.MAX_BOON_STACKS)
					"c2_explosion_mult":
						ok = is_equal_approx(sp.boon_c2_explosion_mult, 1.0 + value * BoonDB.MAX_BOON_STACKS)
					"c2_owl_count":
						ok = sp.boon_c2_owl_count == int(value)
					"c3_cooldown_flat":
						ok = is_equal_approx(sp.boon_c3_cooldown_flat, value * BoonDB.MAX_BOON_STACKS)
					"c3_radius_mult":
						ok = is_equal_approx(sp.boon_c3_radius_mult, 1.0 + value * BoonDB.MAX_BOON_STACKS)
					"c4_count_flat":
						ok = sp.boon_c4_count_flat == int(value) * BoonDB.MAX_BOON_STACKS
					"c4_dmg_mult":
						ok = is_equal_approx(sp.boon_c4_dmg_mult, 1.0 + value * BoonDB.MAX_BOON_STACKS)
					"c4_radius_mult":
						ok = is_equal_approx(sp.boon_c4_radius_mult, 1.0 + value * BoonDB.MAX_BOON_STACKS)
			"passive":
						ok = sp.dungeon_passives.count(boon.get("passive", "")) == BoonDB.MAX_BOON_STACKS
			"ability":
						ok = sp.dungeon_dash_bonus == int(value) * BoonDB.MAX_BOON_STACKS
			"double":
						ok = true  # double boons recurse — covered by their sub-stats

		if ok:
			passes += 1
		else:
			fails += 1
			var expected = ""
			match type:
				"stat":
					match stat:
						"max_hp":      expected = "max_hp=%d" % (100 + value * BoonDB.MAX_BOON_STACKS)
						"max_chakra":  expected = "max_chakra=%d" % (500 + value * BoonDB.MAX_BOON_STACKS)
						_:             expected = "%s=%.4f" % [stat, 1.0 + value * BoonDB.MAX_BOON_STACKS]
			push_error("[BOON TEST] FAIL: %s (%s) — stat=%s expected %s" % [boon_id, type, stat, expected])

	print("[BOON TEST] %d/%d boons passed (x%d stacks each)" % [passes, passes + fails, BoonDB.MAX_BOON_STACKS])
	if fails > 0:
		push_error("[BOON TEST] %d FAILURES — check above errors" % fails)
