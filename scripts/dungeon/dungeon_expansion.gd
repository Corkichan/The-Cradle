class_name DungeonExpansion
extends RefCounted

## Buying dungeon growth: new tiles on the current floor, and whole new floors.
##
## Owns the rules of expansion — what is purchasable, what it costs, whether it
## is affordable — and is the only thing that grows the dungeon. [DungeonTile]
## knows nothing about money, and [Dungeon] knows nothing about purchasing.
##
## Both kinds of purchase spend the SAME gold. There is deliberately one
## balance, not one per feature.

## Cost of one tile, in gold. Lives here rather than on the tile so pricing can
## change without touching spatial data.
const DEFAULT_TILE_COST: int = 100
## Cost of one new floor, in gold. Configurable per instance so no UI code
## needs to know the number.
const DEFAULT_FLOOR_COST: int = 5000
## Prototype starting balance.
const STARTING_GOLD: int = 10000

## Four-directional adjacency. Diagonals are deliberately absent: a tile touching
## the dungeon only at a corner is not connected to it.
const NEIGHBOUR_OFFSETS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
]

## Placeholder currency. A real economy system will own this later; it exists
## now only so the expansion mechanic can be exercised.
var gold: int = STARTING_GOLD
var tile_cost: int = DEFAULT_TILE_COST
var floor_cost: int = DEFAULT_FLOOR_COST

var _dungeon: Dungeon


func _init(dungeon: Dungeon, p_tile_cost: int = DEFAULT_TILE_COST,
		p_floor_cost: int = DEFAULT_FLOOR_COST) -> void:
	_dungeon = dungeon
	tile_cost = p_tile_cost
	floor_cost = p_floor_cost


## Price of expanding onto [param grid_position]. Flat for now; the position is
## taken so distance- or size-based pricing needs no call-site changes.
func get_expansion_cost(_grid_position: Vector2i) -> int:
	return tile_cost


## True if a tile can be bought here: nothing there yet, and orthogonally
## touching at least one existing tile. This is what rejects both diagonal-only
## and disconnected positions — neither has an orthogonal neighbour in the
## dungeon.
func can_expand_at(grid_position: Vector2i) -> bool:
	if _dungeon.is_valid_position(grid_position):
		return false
	for offset in NEIGHBOUR_OFFSETS:
		if _dungeon.is_valid_position(grid_position + offset):
			return true
	return false


## True if the current balance covers the cost.
func can_afford(grid_position: Vector2i) -> bool:
	return gold >= get_expansion_cost(grid_position)


## Every position that could be bought right now. Derived from the dungeon each
## call rather than cached, so it cannot go stale after a purchase.
func get_expandable_positions() -> Array[Vector2i]:
	var found: Dictionary = {}
	var result: Array[Vector2i] = []
	for position in _dungeon.get_positions():
		for offset in NEIGHBOUR_OFFSETS:
			var candidate: Vector2i = position + offset
			if found.has(candidate) or _dungeon.is_valid_position(candidate):
				continue
			found[candidate] = true
			result.append(candidate)
	return result


## Buys one tile. Returns false and changes nothing if the position is not
## expandable or the balance is short — gold is only spent on success.
func purchase_tile(grid_position: Vector2i) -> bool:
	if not can_expand_at(grid_position):
		return false
	if not can_afford(grid_position):
		return false
	gold -= get_expansion_cost(grid_position)
	_dungeon.add_tile(grid_position)
	return true


## Price of one new floor.
func get_floor_cost() -> int:
	return floor_cost


## True if the current balance covers a new floor.
func can_afford_floor() -> bool:
	return gold >= floor_cost


## Buys a floor and returns its index, or -1 if the balance is short — gold is
## only spent on success.
##
## Deliberately does NOT change the selected floor. Which floor is being looked
## at is a selection decision; a caller that buys a floor without wanting to
## jump to it should not be surprised. The debug harness switches explicitly
## using the returned index.
func create_floor() -> int:
	if not can_afford_floor():
		return -1
	gold -= floor_cost
	_dungeon.create_floor()
	return _dungeon.get_floor_count() - 1
