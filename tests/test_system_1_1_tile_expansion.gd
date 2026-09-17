extends "res://tests/test_suite.gd"


func _init() -> void:
	title = "System 1.1 - Tile Expansion"


func run() -> void:
	var d := Dungeon.new()
	var e := DungeonExpansion.new(d)

	section("defaults")
	check("gold", e.gold, 10000)
	check("tile cost", e.tile_cost, 100)
	var tile_has_cost := false
	for property in DungeonTile.new(Vector2i.ZERO).get_property_list():
		if String(property.name).to_lower().contains("cost"):
			tile_has_cost = true
	check_false("no cost field on DungeonTile", tile_has_cost)

	section("adjacency")
	check_true("right (8,2)", e.can_expand_at(Vector2i(8, 2)))
	check_true("left (-1,2)", e.can_expand_at(Vector2i(-1, 2)))
	check_true("above (3,-1)", e.can_expand_at(Vector2i(3, -1)))
	check_true("below (3,5)", e.can_expand_at(Vector2i(3, 5)))
	check_false("diagonal-only (8,5)", e.can_expand_at(Vector2i(8, 5)))
	check_false("diagonal-only (-1,-1)", e.can_expand_at(Vector2i(-1, -1)))
	check_false("disconnected (12,2)", e.can_expand_at(Vector2i(12, 2)))
	check_false("existing tile (4,2)", e.can_expand_at(Vector2i(4, 2)))
	check("offer = perimeter of 8x5", e.get_expandable_positions().size(), 26)

	section("purchasing")
	check_true("buy (8,2)", e.purchase_tile(Vector2i(8, 2)))
	check("40 -> 41 tiles", d.get_tile_count(), 41)
	check("10000 -> 9900 gold", e.gold, 9900)
	check("bought tile starts EMPTY", d.get_tile(Vector2i(8, 2)).terrain, DungeonTile.Terrain.EMPTY)
	check_false("bought tile not walkable until floor is placed", d.is_walkable(Vector2i(8, 2)))
	check_true("floor can be placed on a bought tile", d.place_floor(Vector2i(8, 2)))
	check_true("then walkable", d.is_walkable(Vector2i(8, 2)))
	check("bounds grew", d.get_bounds(), Rect2i(0, 0, 9, 5))
	check_false("same tile twice", e.purchase_tile(Vector2i(8, 2)))
	check("gold untouched by rebuy", e.gold, 9900)
	check_false("diagonal buy", e.purchase_tile(Vector2i(9, 3)))
	check_false("disconnected buy", e.purchase_tile(Vector2i(20, 20)))
	check("gold untouched by failed buys", e.gold, 9900)

	section("sparse storage")
	check_false("hole inside bounds is not a tile", d.is_valid_position(Vector2i(8, 0)))
	check("hole returns null", d.get_tile(Vector2i(8, 0)) == null, true)

	section("negative coordinates")
	var d2 := Dungeon.new()
	var e2 := DungeonExpansion.new(d2)
	check_true("buy (-1,0)", e2.purchase_tile(Vector2i(-1, 0)))
	check("bounds origin negative", d2.get_bounds(), Rect2i(-1, 0, 9, 5))
	check("world origin", d2.get_world_bounds().position, Vector2(-32, 0))
	check("roundtrip at -1", d2.world_to_grid(d2.grid_to_world(Vector2i(-1, 0))), Vector2i(-1, 0))

	section("affordability")
	var e3 := DungeonExpansion.new(Dungeon.new())
	e3.gold = 150
	check_true("afford 1", e3.purchase_tile(Vector2i(8, 0)))
	check_false("cannot afford 2nd at 50", e3.purchase_tile(Vector2i(8, 1)))
	check("gold still 50", e3.gold, 50)
	var e4 := DungeonExpansion.new(Dungeon.new(), 350)
	e4.purchase_tile(Vector2i(8, 0))
	check("custom price charged", e4.gold, 10000 - 350)
