class_name DungeonFloor
extends RefCounted

## One floor of the dungeon: a set of [DungeonTile] addressed by grid position.
##
## Pure data. This is the source of truth about what exists where; renderers
## read from it and never write to it.
##
## Storage is SPARSE — a Dictionary keyed by [Vector2i] rather than a rectangular
## array — because expansion buys one tile at a time and the resulting shape is
## not a rectangle. 41 tiles cannot be expressed as width x height. A dense array
## would need both reallocation on growth and a per-cell "does this exist" flag,
## which is strictly more machinery than a dictionary lookup.
##
## Positions may be negative: expanding left or up from the origin is legal.

var _tiles: Dictionary = {}
## Cached bounding box of every tile. Grown incrementally in [method add_tile];
## never shrinks, because tiles are never removed.
var _bounds: Rect2i = Rect2i()


## Builds the starting rectangle. Expansion beyond it is the expansion system's
## job, not this class's.
func _init(p_width: int, p_height: int) -> void:
	for y in p_height:
		for x in p_width:
			add_tile(Vector2i(x, y))


## True if a tile exists at [param grid_position].
##
## Note this means "a tile is here", not "inside some rectangle" — once tiles
## have been bought the dungeon is not a rectangle, so membership is the only
## meaningful test.
func is_valid_position(grid_position: Vector2i) -> bool:
	return _tiles.has(grid_position)


## The tile at [param grid_position], or null if no tile exists there.
func get_tile(grid_position: Vector2i) -> DungeonTile:
	return _tiles.get(grid_position)


## True if a tile exists there and may be entered.
func is_walkable(grid_position: Vector2i) -> bool:
	var tile: DungeonTile = _tiles.get(grid_position)
	return tile != null and tile.walkable


## Total number of tiles on this floor.
func get_tile_count() -> int:
	return _tiles.size()


## Smallest grid rectangle containing every tile. Used for iteration and for
## framing the view; it is NOT a membership test — cells inside the bounds can
## be empty.
func get_bounds() -> Rect2i:
	return _bounds


## Every occupied grid position. Order is unspecified.
func get_positions() -> Array:
	return _tiles.keys()


## Adds a floor tile. Returns the new tile, or null if one already existed there
## — callers use that to reject double purchases.
func add_tile(grid_position: Vector2i) -> DungeonTile:
	if _tiles.has(grid_position):
		return null
	var tile := DungeonTile.new(grid_position)
	_tiles[grid_position] = tile
	_grow_bounds(grid_position)
	return tile


func _grow_bounds(grid_position: Vector2i) -> void:
	if _tiles.size() == 1:
		_bounds = Rect2i(grid_position, Vector2i.ONE)
		return
	# Rect2i.end is exclusive, so including a tile means expanding to both its
	# top-left corner and one past its bottom-right.
	_bounds = _bounds.expand(grid_position).expand(grid_position + Vector2i.ONE)
