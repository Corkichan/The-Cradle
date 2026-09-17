extends "res://tests/test_suite.gd"


func _init() -> void:
	title = "System 1.2 - Floor Expansion"


func run() -> void:
	var d := Dungeon.new()
	var e := DungeonExpansion.new(d)

	section("one floor to start")
	check("floor count", d.get_floor_count(), 1)
	check("current index", d.get_current_floor_index(), 0)
	check("get_floor(1) null", d.get_floor(1) == null, true)
	check("floor cost", e.get_floor_cost(), 5000)

	section("create")
	check("returns index 1", e.create_floor(), 1)
	check("2 floors", d.get_floor_count(), 2)
	check("10000 -> 5000 gold", e.gold, 5000)
	check("selection not auto-changed", d.get_current_floor_index(), 0)
	check("new floor 8x5", d.get_floor(1).get_bounds(), Rect2i(0, 0, 8, 5))
	check("new floor 40 tiles", d.get_floor(1).get_tile_count(), 40)
	check_true("distinct instances", d.get_floor(0) != d.get_floor(1))

	section("independence")
	d.set_current_floor(0)
	e.purchase_tile(Vector2i(8, 2))
	check("floor 1 grew", d.get_floor(0).get_tile_count(), 41)
	check("floor 2 untouched", d.get_floor(1).get_tile_count(), 40)
	d.set_current_floor(1)
	e.purchase_tile(Vector2i(-1, 0))
	check("floor 2 grew", d.get_floor(1).get_tile_count(), 41)
	check("floor 1 untouched", d.get_floor(0).get_tile_count(), 41)
	check_false("floor 1 lacks (-1,0)", d.get_floor(0).is_valid_position(Vector2i(-1, 0)))
	check_false("floor 2 lacks (8,2)", d.get_floor(1).is_valid_position(Vector2i(8, 2)))

	section("placed floor is per dungeon floor")
	d.set_current_floor(0)
	check_true("place floor on floor 1 (3,3)", d.place_floor(Vector2i(3, 3)))
	check_true("floor 1 (3,3) walkable", d.get_floor(0).is_walkable(Vector2i(3, 3)))
	check_false("floor 2 (3,3) still bare", d.get_floor(1).is_walkable(Vector2i(3, 3)))
	check("floor 2 has no floor placed", d.get_floor(1).get_floor_tile_count(), 0)

	section("facade answers for current floor")
	d.set_current_floor(0)
	check_true("current=1 sees (8,2)", d.is_valid_position(Vector2i(8, 2)))
	d.set_current_floor(1)
	check_false("current=2 does not see (8,2)", d.is_valid_position(Vector2i(8, 2)))
	check_true("current=2 sees (-1,0)", d.is_valid_position(Vector2i(-1, 0)))

	section("gold")
	var e2 := DungeonExpansion.new(Dungeon.new())
	e2.gold = 4999
	check("short -> -1", e2.create_floor(), -1)
	check("gold untouched", e2.gold, 4999)
	e2.gold = 5000
	check("exact -> 1", e2.create_floor(), 1)
	check("lands on 0", e2.gold, 0)
	var e3 := DungeonExpansion.new(Dungeon.new())
	e3.purchase_tile(Vector2i(8, 2))
	e3.create_floor()
	check("tile + floor share one balance", e3.gold, 10000 - 100 - 5000)

	section("many floors")
	var d4 := Dungeon.new()
	for i in 4:
		d4.create_floor()
	check("5 floors", d4.get_floor_count(), 5)
	check_false("set_current_floor(5) rejected", d4.set_current_floor(5))
	check_false("set_current_floor(-1) rejected", d4.set_current_floor(-1))
	var custom := Dungeon.new(3, 9)
	custom.create_floor()
	check("custom size carries to new floors", custom.get_floor(1).get_bounds().size, Vector2i(3, 9))
