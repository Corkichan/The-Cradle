# System 1.2 — Floor Expansion

**Project:** The Cradle (Godot 4.7.2, GDScript, 2D pixel-art dungeon ecosystem sim)
**Status:** Implemented, verified, **not yet committed**
**Builds on:** [System 1 — Dungeon / Grid Foundation](system-01-dungeon-grid.md),
[System 1.1 — Tile Expansion](system-01.1-tile-expansion.md)

---

## 1. Scope

Let the dungeon contain more than one floor. Each floor is an independent grid
the player can inspect and expand; only the selected one is rendered.

**Implemented**

| Rule | Value |
|---|---|
| Initial floors | 1, at 8 × 5 (unchanged) |
| New floor size | 8 × 5 (the dungeon's configured default) |
| Floor cost | 5,000 gold (configurable per instance) |
| Floor limit | none |
| Currency | the **same** gold as tile expansion |
| Rendering | only the selected floor |

**Explicitly not implemented:** stairs, ladders, elevators, doors between
floors, movement or pathfinding between floors, floor connectivity, floor
deletion, unlock progression, save/load, a real economy.

Floors exist as separate dungeon spaces. Nothing connects them.

---

## 2. How multiple floors are represented

`Dungeon` went from holding one `DungeonFloor` to holding an ordered list plus a
selected index:

```gdscript
var _floor_size: Vector2i          # size new floors start at
var _floors: Array[DungeonFloor] = []
var _current_floor_index: int = 0
```

Every pre-existing spatial query on `Dungeon` — `is_walkable`, `get_tile`,
`get_bounds`, `get_positions`, `add_tile`, `get_width`, `get_height`,
`get_tile_count` — now forwards to `get_current_floor()` instead of a single
`_floor`. That was a mechanical one-line substitution per method.

```
Dungeon                     (RefCounted)
  +-- DungeonFloor  [0]     <- own tiles, own bounds, own expansion state
  |     +-- DungeonTile ...
  +-- DungeonFloor  [1]
  |     +-- DungeonTile ...
  +-- DungeonFloor  [2]
        +-- DungeonTile ...
```

No new classes. No inheritance. `DungeonFloor`, `DungeonTile` and
`DungeonRenderer` were **not modified at all**.

### Why the facade absorbed this instead of callers

The System 1 doc predicted this exact moment (§5.1): *"the thin `Dungeon` facade
is what keeps `dungeon.is_walkable(pos)` stable at every call site when multiple
floors arrive."*

It held. `get_floor()` turned out to have no callers outside `Dungeon` itself,
so changing its signature broke nothing, and because every query still reads
`dungeon.is_walkable(pos)`, **neither the renderer nor the expansion system
needed to become floor-aware.** The alternative — threading an index through as
`dungeon.get_floor(n).is_walkable(pos)` — would have touched every call site for
no benefit.

Code that genuinely needs a specific floor asks for it: `get_floor(index)`.

### Floor independence

Each `DungeonFloor` owns its own sparse tile Dictionary and its own bounding
box, so size, shape and expansion state diverge freely. Expanding floor 1 cannot
reach floor 2 because the expansion system writes through
`Dungeon.add_tile()`, which resolves to the current floor.

Verified directly: with floor 1 at `(0,0,10,5)` and floor 2 at `(-1,0,9,5)`,
floor 1 has `(8,2)` and not `(-1,0)`, and floor 2 the reverse.

---

## 3. Public API

### `Dungeon` — floor management

```gdscript
get_floor_count()           -> int              # always >= 1
get_floor(index: int)       -> DungeonFloor     # null if no such floor
get_current_floor()         -> DungeonFloor
get_current_floor_index()   -> int
set_current_floor(index)    -> bool             # false = rejected, nothing changed
create_floor()              -> DungeonFloor     # appends at the default size
```

Every other `Dungeon` method answers for the **current** floor.

### `DungeonExpansion` — floor purchasing

```gdscript
const DEFAULT_FLOOR_COST: int = 5000
var floor_cost: int

_init(dungeon, p_tile_cost := DEFAULT_TILE_COST, p_floor_cost := DEFAULT_FLOOR_COST)

get_floor_cost()    -> int
can_afford_floor()  -> bool
create_floor()      -> int    # new floor index, or -1 if the balance is short
```

---

## 4. How floor creation works

`DungeonExpansion.create_floor()` returns the new floor's index, or **`-1`** when
gold is short. Gold is deducted only on success.

The cost is a constant with a per-instance override passed through the
constructor, so **no UI code knows the number** — the debug button reads its own
label from `get_floor_cost()`.

`Dungeon.create_floor()` itself is free and unconditional: affordability is the
expansion system's concern, not the data model's.

### One deliberate deviation from the brief

The spec said creation should "switch to the newly created floor".
`DungeonExpansion.create_floor()` **does not change the selection** — it returns
the index and lets the caller decide.

Which floor is being *looked at* is a selection decision. A future caller that
buys a floor without wanting to jump to it should not be ambushed by a view
change. The debug harness switches explicitly using the returned index, so the
**user-visible behaviour is exactly as specified**, and the purchase and the
switch are tested independently.

---

## 5. How floor switching works

`Dungeon.set_current_floor(index)` returns `false` and changes nothing for an
out-of-range index (including negatives).

The harness's `_switch_floor()` then does four things:

1. recomputes the expandable ghost positions for the new floor,
2. rebuilds the floor button bar so the current floor is marked,
3. **reframes the camera**, and
4. queues a renderer redraw.

Reframing matters because floors diverge: in testing, floor 1 reached 10 × 6
while floor 2 was 9 × 5. A fixed frame would crop one of them.

---

## 6. How gold is shared

There is exactly one `gold` field, on `DungeonExpansion`. Both purchase kinds
spend it. No second currency, no economy system.

```
start                 10000
buy tile               9900   (-100)
build floor            4900   (-5000)
buy tile on floor 2    4800   (-100)
```

---

## 7. How the renderer handles the active floor

**The renderer required no changes whatsoever.**

It only ever calls `dungeon.get_bounds()`, `get_tile()`, `get_positions()`,
`is_valid_position()` and `grid_to_world()` — all of which now answer for the
current floor. Switching floors is therefore just `queue_redraw()`.

Only the selected floor is ever drawn. There is no per-floor rendering, no
layering, no hidden floors kept alive in the scene tree.

The brief suggested passing the selected `DungeonFloor` to the renderer
directly. It still receives the `Dungeon`, because it also needs
`grid_to_world` / `TILE_SIZE`, which live there. Passing a bare floor would mean
duplicating coordinate conversion into the renderer — more code for an identical
result.

---

## 8. Debug UI

A button bar at the top-left of the HUD:

```
[ Floor 1 ]  Floor 2  Floor 3   Build New Floor - 5000 Gold
```

- The current floor is bracketed.
- Clicking a floor button switches to it.
- `Build New Floor` **auto-disables** when gold is short; pressing it anyway
  prints `Not enough Gold (need 5000, have 4500)` and changes nothing.
- HUD gained `floor N of M` and `Floor Cost`.

The bar is rebuilt whenever the floor list, the selection, or the balance
changes. That is cheap and avoids tracking button state separately.

### A hazard this introduced

Adding focusable `Control`s means **`Tab` drives UI focus navigation instead of
reaching `_unhandled_key_input`** — which would have silently broken the
`ADD` / `DELETE` / `EXPAND` mode switch from System 1.1.

Mitigation: every button sets `focus_mode = Control.FOCUS_NONE`, and the
container sets `MOUSE_FILTER_IGNORE` so only the buttons themselves swallow
clicks and everything else falls through to the grid.

There is a regression test asserting `Tab` still cycles modes *and* that nothing
holds focus. Anything added to the HUD later that can take focus must do the
same.

---

## 9. Test results — 99 data-model + 31 UI checks, all passing

Run headless in the real engine. All 15 required cases plus the full prior
suites for System 0, System 1 and System 1.1.

```
new dungeon    1 floor, 8x5, 40 tiles; get_floor(1) and get_floor(-1) null
creation       returns index 1; count 1->2; gold 10000->5000
               new floor is 8x5 with 40 tiles
               selection deliberately NOT auto-changed
independence   floors are distinct instances with distinct tile objects
               blocking floor 1's (0,0) leaves floor 2's walkable
               floor 1 -> 42 tiles while floor 2 STILL 40
               floor 2 -> 41 tiles while floor 1 STILL 42
               floor 1 bounds (0,0,10,5); floor 2 bounds (-1,0,9,5)
facade         current=1 sees (8,2) and not (-1,0); current=2 the reverse
               can_expand_at is per-floor
gold           4999 refused; 5000 exact works and lands on 0
               custom cost 250 charges 250, not 5000
many floors    5 distinct floors; each grew by exactly 1 tile
               set_current_floor(5) and (-1) rejected, selection unchanged
shared gold    10000 -> 9900 -> 4900 -> 4800
custom size    a dungeon built at 3x9 creates later floors at 3x9
regression     all System 1 + 1.1 behaviour; System 0 ticks; GameTime rollover
UI             Tab reaches the harness with Buttons present; nothing took focus
               build button switches floor and relabels the bar
               build button disables below 5000 gold
               switching re-renders the other floor's distinct shape
clean boot     no errors, no warnings
```

Two failures during development were both wrong test expectations, not code
defects: one compared a null `Object` by string (`<Object#null>` vs `<null>`),
the other used a miscalculated overlap count.

---

## 10. Architectural decisions

### 10.1 Extended the facade rather than threading a floor index

See §2. The seam built in System 1 absorbed the change; no caller moved.

### 10.2 Floor creation lives on `DungeonExpansion`, not a new class

It already owns gold, and both operations are "spend money to grow the
dungeon". A separate `FloorExpansion` class would have needed a shared wallet
object between them — more machinery than a prototype currency warrants, and
the brief explicitly forbids a second currency or an economy system.

### 10.3 `create_floor()` does not change the selection

See §4.

### 10.4 `_floor_size` is captured at construction

A dungeon built at a custom size creates later floors at that size rather than
snapping to 8 × 5. Tested.

### 10.5 Floors are a flat array, indices are stable

There is no floor deletion, so `_floors` only grows and an index is a permanent
handle. If deletion is ever added, the current index needs revalidating and any
stored index becomes unsafe.

---

## 11. Open questions / TBD

1. **Flat floor pricing** — floor 5 costs the same as floor 2. Scaling by
   `get_floor_count()` is a one-method change.
2. **No floor deletion.** See §10.5.
3. **Per-floor vs global editor state.** Blocked tiles are per-floor (they live
   on tiles), but edit mode and camera zoom are global. Switching floors resets
   the camera and keeps the mode. Probably right; worth confirming.
4. **`Dungeon` ownership** still sits with the throwaway harness, which now also
   owns the floor UI. Both need a permanent home before System 2.
5. **Stairs will be the first thing to need a cross-floor reference.** A
   connection has a position on *two* floors, which is the first real pressure
   on the "floors are fully independent" assumption.
6. **Runtime only** — floors and purchases reset on restart.

---

## Appendix — `scripts/dungeon/dungeon.gd` (floor management)

```gdscript
class_name Dungeon
extends RefCounted

## Holds an ordered list of [DungeonFloor]s, one of which is current. Every
## spatial query on this class — [method is_walkable], [method get_tile] and the
## rest — answers for the CURRENT floor, so callers write
## `dungeon.is_walkable(pos)` and never have to thread a floor index through.
## Code that genuinely needs another floor asks for it with [method get_floor].
##
## Floors are fully independent: each owns its own tiles and expands on its own.
## There is no connection between them yet — no stairs, no movement.

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


# ... every spatial query below forwards to get_current_floor():

func get_width() -> int:
	return get_current_floor().get_bounds().size.x


func is_valid_position(grid_position: Vector2i) -> bool:
	return get_current_floor().is_valid_position(grid_position)


func get_tile(grid_position: Vector2i) -> DungeonTile:
	return get_current_floor().get_tile(grid_position)


func is_walkable(grid_position: Vector2i) -> bool:
	return get_current_floor().is_walkable(grid_position)


func add_tile(grid_position: Vector2i) -> DungeonTile:
	return get_current_floor().add_tile(grid_position)
```

## Appendix — `scripts/dungeon/dungeon_expansion.gd` (floor portion)

```gdscript
## Cost of one new floor, in gold. Configurable per instance so no UI code
## needs to know the number.
const DEFAULT_FLOOR_COST: int = 5000

var floor_cost: int = DEFAULT_FLOOR_COST


func _init(dungeon: Dungeon, p_tile_cost: int = DEFAULT_TILE_COST,
		p_floor_cost: int = DEFAULT_FLOOR_COST) -> void:
	_dungeon = dungeon
	tile_cost = p_tile_cost
	floor_cost = p_floor_cost


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
```
