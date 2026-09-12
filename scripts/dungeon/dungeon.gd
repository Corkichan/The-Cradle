class_name Dungeon
extends RefCounted

## The dungeon data model and the entry point future systems query.
##
## Holds one floor today. It exists as a thin layer over [DungeonFloor] so that
## callers write `dungeon.is_walkable(pos)` and keep working unchanged when
## multiple floors arrive — at which point this gains a "current floor" concept
## instead of every caller being rewritten.
##
## Pure data: not a Node, never processes, and has no opinion about rendering.

## Pixel size of one tile. The bridge between grid space and world space.
const TILE_SIZE: int = 32

const DEFAULT_WIDTH: int = 8
const DEFAULT_HEIGHT: int = 5

var _floor: DungeonFloor


func _init(width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> void:
	_floor = DungeonFloor.new(width, height)


## The only floor that currently exists.
func get_floor() -> DungeonFloor:
	return _floor


## Width of the dungeon's bounding box. Not every cell inside it holds a tile
## once the dungeon has been expanded.
func get_width() -> int:
	return _floor.get_bounds().size.x


## Height of the dungeon's bounding box.
func get_height() -> int:
	return _floor.get_bounds().size.y


## Smallest grid rectangle containing every tile.
func get_bounds() -> Rect2i:
	return _floor.get_bounds()


## Every occupied grid position. Order is unspecified.
func get_positions() -> Array:
	return _floor.get_positions()


## Adds a floor tile, returning null if one already exists there. Called by the
## expansion system; nothing else should be growing the dungeon.
func add_tile(grid_position: Vector2i) -> DungeonTile:
	return _floor.add_tile(grid_position)


func get_tile_count() -> int:
	return _floor.get_tile_count()


## True if a tile exists at [param grid_position]. Once tiles have been bought
## the dungeon is not a rectangle, so this is membership, not a bounds check.
func is_valid_position(grid_position: Vector2i) -> bool:
	return _floor.is_valid_position(grid_position)


## The tile at [param grid_position], or null if outside the dungeon.
func get_tile(grid_position: Vector2i) -> DungeonTile:
	return _floor.get_tile(grid_position)


## True if a creature may occupy [param grid_position].
func is_walkable(grid_position: Vector2i) -> bool:
	return _floor.is_walkable(grid_position)


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
