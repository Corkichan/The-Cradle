class_name Dungeon
extends RefCounted

## The dungeon data model and the entry point future systems query.
##
## Holds an ordered list of [DungeonFloor]s, one of which is current. Every
## spatial query on this class — [method is_walkable], [method get_tile] and the
## rest — answers for the CURRENT floor, so callers write
## `dungeon.is_walkable(pos)` and never have to thread a floor index through.
## Code that genuinely needs another floor asks for it with [method get_floor].
##
## Floors are fully independent: each owns its own tiles and expands on its own.
## There is no connection between them yet — no stairs, no movement.
##
## Pure data: not a Node, never processes, and has no opinion about rendering.

## Pixel size of one tile. The bridge between grid space and world space.
const TILE_SIZE: int = 32

const DEFAULT_WIDTH: int = 8
const DEFAULT_HEIGHT: int = 5

## Size every new floor starts at. Floors diverge from here by expanding.
var _floor_size: Vector2i
var _floors: Array[DungeonFloor] = []
var _current_floor_index: int = 0


func _init(width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> void:
	_floor_size = Vector2i(width, height)
	create_floor()


## How many floors exist. Always at least one.
func get_floor_count() -> int:
	return _floors.size()


## The floor at [param index], or null if there is no such floor.
func get_floor(index: int) -> DungeonFloor:
	if index < 0 or index >= _floors.size():
		return null
	return _floors[index]


## The floor every unqualified query on this class refers to.
func get_current_floor() -> DungeonFloor:
	return _floors[_current_floor_index]


func get_current_floor_index() -> int:
	return _current_floor_index


## Selects the floor subsequent queries answer for. Returns false and changes
## nothing if no such floor exists.
func set_current_floor(index: int) -> bool:
	if index < 0 or index >= _floors.size():
		return false
	_current_floor_index = index
	return true


## Appends a floor at the dungeon's default size and returns it. Whether the
## player can afford one is the expansion system's concern, not this class's;
## the selected floor is deliberately left alone.
func create_floor() -> DungeonFloor:
	var new_floor := DungeonFloor.new(_floor_size.x, _floor_size.y)
	_floors.append(new_floor)
	return new_floor


## Width of the dungeon's bounding box. Not every cell inside it holds a tile
## once the dungeon has been expanded.
func get_width() -> int:
	return get_current_floor().get_bounds().size.x


## Height of the dungeon's bounding box.
func get_height() -> int:
	return get_current_floor().get_bounds().size.y


## Smallest grid rectangle containing every tile.
func get_bounds() -> Rect2i:
	return get_current_floor().get_bounds()


## Every occupied grid position. Order is unspecified.
func get_positions() -> Array:
	return get_current_floor().get_positions()


## Places floor on the current floor's tile. See [method DungeonFloor.place_floor].
func place_floor(grid_position: Vector2i) -> bool:
	return get_current_floor().place_floor(grid_position)


## Removes floor from the current floor's tile. See [method DungeonFloor.remove_floor].
func remove_floor(grid_position: Vector2i) -> bool:
	return get_current_floor().remove_floor(grid_position)


func get_floor_tile_count() -> int:
	return get_current_floor().get_floor_tile_count()


## Adds an EMPTY tile, returning null if one already exists there. Called by the
## expansion system; nothing else should be growing the dungeon.
func add_tile(grid_position: Vector2i) -> DungeonTile:
	return get_current_floor().add_tile(grid_position)


func get_tile_count() -> int:
	return get_current_floor().get_tile_count()


## True if a tile exists at [param grid_position]. Once tiles have been bought
## the dungeon is not a rectangle, so this is membership, not a bounds check.
func is_valid_position(grid_position: Vector2i) -> bool:
	return get_current_floor().is_valid_position(grid_position)


## The tile at [param grid_position], or null if outside the dungeon.
func get_tile(grid_position: Vector2i) -> DungeonTile:
	return get_current_floor().get_tile(grid_position)


## True if a creature may occupy [param grid_position].
func is_walkable(grid_position: Vector2i) -> bool:
	return get_current_floor().is_walkable(grid_position)


## Top-left world pixel of the given tile. Use [method grid_to_world_center]
## for placing things that should sit in the middle of a tile.
func grid_to_world(grid_position: Vector2i) -> Vector2:
	return Vector2(grid_position) * TILE_SIZE


## Centre world pixel of the given tile.
func grid_to_world_center(grid_position: Vector2i) -> Vector2:
	return grid_to_world(grid_position) + Vector2.ONE * (TILE_SIZE / 2.0)


## The tile containing [param world_position]. May be outside the dungeon —
## check with [method is_valid_position]. Floors rather than truncates, so
## negative coordinates map to negative tiles instead of collapsing onto 0.
func world_to_grid(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / TILE_SIZE),
		floori(world_position.y / TILE_SIZE))


## Bounding box of the dungeon in world pixels. Its origin can be negative once
## the dungeon has been expanded left or up.
func get_world_bounds() -> Rect2:
	var bounds := get_bounds()
	return Rect2(Vector2(bounds.position) * TILE_SIZE, Vector2(bounds.size) * TILE_SIZE)


## Full dungeon size in world pixels.
func get_world_size() -> Vector2:
	return get_world_bounds().size
