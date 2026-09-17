extends "res://tests/test_suite.gd"


func _init() -> void:
	title = "System 1 - Dungeon / Grid Foundation"


func run() -> void:
	var d := Dungeon.new()

	section("dimensions")
	check("width", d.get_width(), 8)
	check("height", d.get_height(), 5)
	check("tile count", d.get_tile_count(), 40)
	check("bounds", d.get_bounds(), Rect2i(0, 0, 8, 5))
	check("world size", d.get_world_size(), Vector2(256, 160))
	check_true("non-square", d.get_width() != d.get_height())

	section("membership")
	for pair in [[Vector2i(0, 0), true], [Vector2i(7, 4), true], [Vector2i(7, 0), true],
			[Vector2i(0, 4), true], [Vector2i(-1, 0), false], [Vector2i(0, -1), false],
			[Vector2i(8, 0), false], [Vector2i(0, 5), false], [Vector2i(8, 5), false],
			[Vector2i(4, 7), false]]:
		check("is_valid_position%s" % pair[0], d.is_valid_position(pair[0]), pair[1])

	section("lookup")
	check("get_tile(7,4)", d.get_tile(Vector2i(7, 4)).grid_position, Vector2i(7, 4))
	check("get_tile out of bounds is null", d.get_tile(Vector2i(8, 0)) == null, true)
	check_false("is_walkable out of bounds", d.is_walkable(Vector2i(-1, 0)))

	section("coordinates")
	check("grid_to_world(0,0)", d.grid_to_world(Vector2i(0, 0)), Vector2(0, 0))
	check("grid_to_world(7,4)", d.grid_to_world(Vector2i(7, 4)), Vector2(224, 128))
	check("grid_to_world_center(0,0)", d.grid_to_world_center(Vector2i(0, 0)), Vector2(16, 16))
	check("world_to_grid(31.9,31.9)", d.world_to_grid(Vector2(31.9, 31.9)), Vector2i(0, 0))
	check("world_to_grid(32,32)", d.world_to_grid(Vector2(32, 32)), Vector2i(1, 1))
	check("world_to_grid(255,159)", d.world_to_grid(Vector2(255, 159)), Vector2i(7, 4))
	check("world_to_grid(-0.5,-0.5) floors", d.world_to_grid(Vector2(-0.5, -0.5)), Vector2i(-1, -1))

	section("every tile")
	var inconsistent := 0
	var bad_roundtrip := 0
	var not_floor := 0
	for position in d.get_positions():
		var tile := d.get_tile(position)
		if tile.grid_position != position:
			inconsistent += 1
		if d.world_to_grid(d.grid_to_world_center(position)) != position:
			bad_roundtrip += 1
		if tile.terrain != DungeonTile.Terrain.EMPTY or tile.walkable:
			not_floor += 1
	check("self-consistent", inconsistent, 0)
	check("grid/world roundtrip", bad_roundtrip, 0)
	check("all start EMPTY and not walkable", not_floor, 0)
	check("no floor placed yet", d.get_floor_tile_count(), 0)

	section("placing floor")
	check_true("place floor on (2,1)", d.place_floor(Vector2i(2, 1)))
	check("(2,1) is FLOOR", d.get_tile(Vector2i(2, 1)).terrain, DungeonTile.Terrain.FLOOR)
	check_true("(2,1) now walkable", d.is_walkable(Vector2i(2, 1)))
	check_false("neighbour (3,1) still not walkable", d.is_walkable(Vector2i(3, 1)))
	check("1 floor tile", d.get_floor_tile_count(), 1)
	check_false("placing twice is refused", d.place_floor(Vector2i(2, 1)))
	check_false("no tile, no floor", d.place_floor(Vector2i(8, 0)))
	check_false("still no tile at (8,0)", d.is_valid_position(Vector2i(8, 0)))
	check_true("remove floor from (2,1)", d.remove_floor(Vector2i(2, 1)))
	check("(2,1) back to EMPTY", d.get_tile(Vector2i(2, 1)).terrain, DungeonTile.Terrain.EMPTY)
	check_false("(2,1) not walkable again", d.is_walkable(Vector2i(2, 1)))
	check_false("removing from bare ground is refused", d.remove_floor(Vector2i(2, 1)))
	check("tile count unchanged by building", d.get_tile_count(), 40)

	section("tile defaults")
	check_false("new tile: not walkable", DungeonTile.new(Vector2i.ZERO).walkable)
	check_true("tile made as FLOOR: walkable", DungeonTile.new(Vector2i.ZERO, DungeonTile.Terrain.FLOOR).walkable)

	section("custom size")
	check("3x9 tiles", Dungeon.new(3, 9).get_tile_count(), 27)
	check("Terrain enum: EMPTY, FLOOR", DungeonTile.Terrain.keys(), ["EMPTY", "FLOOR"])
