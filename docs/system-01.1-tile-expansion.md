# System 1.1 — Tile Expansion

**Project:** The Cradle (Godot 4.7.2, GDScript, 2D pixel-art dungeon ecosystem sim)
**Status:** Implemented, verified, committed (`0377ca5 Expansion Feature v.1.0.0`)
**Builds on:** [System 1 — Dungeon / Grid Foundation](system-01-dungeon-grid.md)
**Superseded in part by:** [System 1.2 — Floor Expansion](system-01.2-floor-expansion.md), which
made every query in this document answer for the *current* floor.

---

## 1. Scope

Let the player buy individual dungeon tiles with gold. One tile per purchase,
only adjacent to what already exists.

**Implemented**

| Rule | Value |
|---|---|
| Tiles per purchase | exactly 1 |
| Tile cost | 100 gold (configurable per instance) |
| Starting gold | 10,000 |
| Adjacency | 4-directional (up/down/left/right) |
| Diagonal-only positions | rejected |
| Disconnected positions | rejected |

**Explicitly not implemented:** procedural generation, multiple floors (that is
System 1.2), digging, walls, doors, save/load, a real economy, income,
refunds, undo.

---

## 2. The one structural change

The initial grid stored tiles in a **dense row-major `Array[DungeonTile]`**
sized `width * height`. That cannot hold 41 tiles.

Buying one tile at a time produces shapes that are not rectangles:

```
■■■■■■■■□          ■■■■■■■■
■■■■■■■■           ■■■■■■■■□□□
■■■■■■■■           ■■■■■■■■
```

`DungeonFloor` therefore moved to **sparse storage: a `Dictionary` keyed by
`Vector2i`**, plus a cached `Rect2i` bounding box grown incrementally on each
insert.

Why a dictionary rather than growing the array: a dense array would need *both*
reallocation on growth *and* a per-cell "does this exist" flag, because the
shape has holes. That is strictly more machinery than a hash lookup, at a tile
count where the performance difference is irrelevant.

### The semantic shift this caused

`is_valid_position()` changed meaning:

| Before | After |
|---|---|
| "inside the rectangle" | "a tile exists here" |

For the untouched initial 8 × 5 these are identical, which is why every
existing caller and test kept working without modification. The signature did
not change.

A consequence worth remembering: **cells inside `get_bounds()` can be empty.**
The bounding box is an iteration range and a camera framing rect — it is *not*
a membership test. Code that loops the bounds must null-check `get_tile()`.

**Positions may be negative.** Expanding left or up from the origin is legal, so
the bounding box origin is not pinned to `(0,0)`.

---

## 3. Architecture

```
Dungeon              (RefCounted)   <- facade; coordinate conversion
  +-- DungeonFloor   (RefCounted)   <- SPARSE Dictionary<Vector2i, DungeonTile>
        +-- DungeonTile             <- grid_position, terrain, walkable

DungeonExpansion     (RefCounted)   <- adjacency rules, pricing, gold, purchase
DungeonRenderer      (Node2D)       <- reads the model, never writes to it
```

Responsibilities, as separated:

- **`DungeonTile`** — no cost field, no purchase logic. A test reflects over its
  properties to assert no `cost` field exists.
- **`Dungeon` / `DungeonFloor`** — spatial data only. `Dungeon.add_tile()` is
  exposed for the expansion system; nothing else should grow the dungeon.
- **`DungeonExpansion`** — the only thing that decides what can be bought, what
  it costs, and whether it is affordable.
- **`DungeonRenderer`** — receives a plain `Array[Vector2i]` of positions to
  draw as ghosts. It does not know what expansion is or what it costs.

---

## 4. Public API

### `DungeonExpansion`

```gdscript
const DEFAULT_TILE_COST: int = 100
const STARTING_GOLD: int = 10000
const NEIGHBOUR_OFFSETS: Array[Vector2i] = [UP, DOWN, LEFT, RIGHT]

var gold: int
var tile_cost: int

_init(dungeon: Dungeon, p_tile_cost := DEFAULT_TILE_COST)

get_expansion_cost(grid_position: Vector2i) -> int
can_expand_at(grid_position: Vector2i)      -> bool
can_afford(grid_position: Vector2i)         -> bool
get_expandable_positions()                  -> Array[Vector2i]
purchase_tile(grid_position: Vector2i)      -> bool   # false = nothing changed
```

### `DungeonFloor` additions

```gdscript
get_bounds()    -> Rect2i        # bounding box; NOT a membership test
get_positions() -> Array         # every occupied position, order unspecified
add_tile(grid_position: Vector2i) -> DungeonTile   # null if one already exists
```

`Dungeon` forwards all three, and adds:

```gdscript
get_world_bounds() -> Rect2      # pixel bounds; origin can be negative
```

---

## 5. How the adjacency rule works

```gdscript
func can_expand_at(grid_position: Vector2i) -> bool:
	if _dungeon.is_valid_position(grid_position):
		return false                      # already a tile
	for offset in NEIGHBOUR_OFFSETS:      # UP, DOWN, LEFT, RIGHT only
		if _dungeon.is_valid_position(grid_position + offset):
			return true
	return false
```

Diagonals are simply **absent from the offset list**. That single omission
rejects both forbidden cases for the same reason — a diagonal-only position and
a disconnected position both have zero orthogonal neighbours in the dungeon. No
separate connectivity check is needed.

It is visible in the debug view: the ring of buyable tiles around an 8 × 5
rectangle is a cross, **with the four corners empty**.

`get_expandable_positions()` walks every tile's four neighbours and
de-duplicates. It is recomputed on each call rather than cached, so it cannot go
stale after a purchase.

---

## 6. Currency

A plain `gold: int` on `DungeonExpansion`, starting at 10,000.

`purchase_tile()` checks adjacency first, then affordability, and **deducts only
on success** — a rejected purchase leaves the balance untouched. Pricing lives
on the expansion system, not the tile, so it can change without touching spatial
data.

`get_expansion_cost(position)` already takes a position despite ignoring it, so
distance- or floor-based pricing later needs no call-site changes.

This is placeholder scaffolding. A real economy system should own the balance
and expansion should query an interface.

---

## 7. Debug UI

The throwaway harness (`scripts/main.gd`) gained an `EXPAND` edit mode, reached
by cycling `Tab` (`ADD` -> `DELETE` -> `EXPAND`).

| Input | Action |
|---|---|
| `Tab` | cycle edit mode |
| left click in `EXPAND` | buy one tile |
| left drag in `ADD` / `DELETE` | block / clear an area |

In `EXPAND` mode, buyable positions render as green ghost tiles; hovering one
shows `BUYABLE cost 100 click to buy` or `NOT ENOUGH GOLD`. The HUD shows
`Gold` and `Tile Cost`.

Expansion is click-only, never a drag — each purchase is exactly one tile.

### Renderer changes

- Iterates `get_bounds()` and **skips empty cells**.
- Draws the dungeon outline **per tile edge** wherever a tile meets empty space,
  because the boundary stops being a rectangle as soon as a tile is bought.
- Draws ghost tiles from the `expandable` array supplied by the caller.

---

## 8. Test results — 82 data-model + 19 UI checks, all passing

Run headless in the real engine.

```
initial      8x5, 40 tiles, gold 10000, cost 100, no cost field on DungeonTile
adjacency    (8,2) (-1,2) (3,-1) (3,5) buyable
             (8,5) (-1,-1) (8,-1) DIAGONAL-ONLY rejected
             (12,2) (3,9) DISCONNECTED rejected
             offer count 26 == perimeter of an 8x5 rectangle
purchase     40->41 tiles, 10000->9900 gold, new tile FLOOR + walkable
             bounds grew 8x5 -> 9x5
             same tile twice REJECTED, count and gold unchanged
             diagonal / disconnected buys REJECTED, gold never touched
negative     buy (-1,0) -> bounds (-1,0,9,5), world origin (-32,0)
             grid<->world roundtrip holds at negative coordinates
afford       250 gold buys 2 then refuses the 3rd
             exactly-100 works and lands on 0
             custom price 350 charges 350
regression   all System 1 grid behaviour; System 0 ticks; GameTime day rollover
UI           Tab reaches EXPAND, 26 ghosts, click buys, ghosts refresh
             non-adjacent click buys nothing
             9 purchases -> 49 tiles, 9100 gold, ragged shape renders correctly
```

### A latent crash found by this work

`_end_drag` in the harness called `.walkable` on the result of `get_tile()`.
Once the dungeon could be non-rectangular, that could be `null` for an empty
cell inside the bounding box, so an `ADD` drag across a ragged dungeon would
have crashed. Null-guarded, with a test that drags across both tiles and holes.

This is the general hazard introduced by sparse storage: **any loop over
`get_bounds()` must null-check.**

---

## 9. Open questions / TBD

1. **Flat pricing.** `get_expansion_cost` takes a position but ignores it.
2. **No refund, no sell-back, no undo.**
3. **Gold lives on the expansion system** — should move to a real economy.
4. **`get_expandable_positions()` recomputes every call.** Fine at 49 tiles; if
   it is ever called per-frame on a large dungeon, cache and invalidate on
   purchase.
5. **Bounds never shrink**, because tiles are never removed. Correct today,
   relevant if removal is ever added.
6. **Runtime only** — no save/load, so purchases reset on restart.

---

## Appendix — `scripts/dungeon/dungeon_expansion.gd` (tile portion)

```gdscript
class_name DungeonExpansion
extends RefCounted

const DEFAULT_TILE_COST: int = 100
const STARTING_GOLD: int = 10000

## Four-directional adjacency. Diagonals are deliberately absent: a tile touching
## the dungeon only at a corner is not connected to it.
const NEIGHBOUR_OFFSETS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
]

var gold: int = STARTING_GOLD
var tile_cost: int = DEFAULT_TILE_COST

var _dungeon: Dungeon


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
```

## Appendix — `scripts/dungeon/dungeon_floor.gd` (sparse storage)

```gdscript
class_name DungeonFloor
extends RefCounted

## Storage is SPARSE — a Dictionary keyed by [Vector2i] rather than a rectangular
## array — because expansion buys one tile at a time and the resulting shape is
## not a rectangle. 41 tiles cannot be expressed as width x height.
##
## Positions may be negative: expanding left or up from the origin is legal.

var _tiles: Dictionary = {}
## Cached bounding box of every tile. Grown incrementally in [method add_tile];
## never shrinks, because tiles are never removed.
var _bounds: Rect2i = Rect2i()


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


func get_tile(grid_position: Vector2i) -> DungeonTile:
	return _tiles.get(grid_position)


func is_walkable(grid_position: Vector2i) -> bool:
	var tile: DungeonTile = _tiles.get(grid_position)
	return tile != null and tile.walkable


func get_tile_count() -> int:
	return _tiles.size()


## Smallest grid rectangle containing every tile. Used for iteration and for
## framing the view; it is NOT a membership test — cells inside the bounds can
## be empty.
func get_bounds() -> Rect2i:
	return _bounds


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
```
