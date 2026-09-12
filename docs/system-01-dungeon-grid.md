# System 1 — Dungeon / Grid Foundation

**Project:** The Cradle (Godot 4.7.2, GDScript, 2D pixel-art dungeon ecosystem sim)
**Status:** Implemented, verified, **not yet committed**
**Depends on:** System 0 (Simulation Core), System 0.2 (Game Time) — both unchanged by this work

---

## 1. Scope

Build the minimal simulation space that future systems (creatures, environment, food)
will live in. A single dungeon floor as an 8 × 5 tile grid.

> **Note:** the grid was initially built at 30 × 30, then changed to 6 × 5, then to
> 8 × 5. Width and height were always independent, so each change was two constants
> in `Dungeon`; the non-square case is covered by tests.

**Explicitly out of scope and not implemented:** multiple floors, dungeon expansion,
digging/mining, procedural generation, walls, doors, decorations, environment
simulation, creature spawning, combat, economy, save/load, dungeon upgrades.

**Configuration**

| Setting | Value |
|---|---|
| Grid size | 8 × 5 tiles (40 tiles) — **rectangular, not square** |
| Floors | 1 |
| Tile size | 32 × 32 px |
| World size | 256 × 160 px |
| Initial terrain | `FLOOR`, all walkable |
| Coordinates | `Vector2i`, `(0,0)` to `(7,4)` |

---

## 2. Architecture

```
Dungeon            (RefCounted)  <- the entry point other systems query
  +-- DungeonFloor (RefCounted)  <- the grid; source of truth
        +-- DungeonTile x 40     <- grid_position, terrain, walkable

DungeonRenderer    (Node2D)      <- reads the model, never writes to it
```

### The separation rule

The data model is `RefCounted`, **not** `Node`. It is not in the scene tree, has no
`_process`, and therefore *cannot* depend on rendering frame rate — the constraint is
enforced structurally rather than by convention. The renderer holds a reference to the
dungeon and only reads it. The dungeon has no reference to the renderer and no concept
of being drawn.

Future systems query the model directly, as specified:

```gdscript
dungeon.is_walkable(position)
```

### Scene integration

```
Node2D (main.tscn root, scripts/main.gd — temporary harness)
+-- DungeonRenderer   (Node2D)
+-- Camera2D
+-- HUD               (CanvasLayer)
```

`SimulationManager` and `GameTime` remain autoload singletons and were **not modified**.
`Dungeon` is deliberately *not* an autoload — it is constructed and owned by the scene,
so multiple dungeons or a save/load flow stay possible later.

---

## 3. Files

### Created

| File | Lines | Purpose |
|---|---|---|
| `scripts/dungeon/dungeon_tile.gd` | 34 | `DungeonTile` — one cell |
| `scripts/dungeon/dungeon_floor.gd` | 55 | `DungeonFloor` — the grid and its queries |
| `scripts/dungeon/dungeon.gd` | 80 | `Dungeon` — facade + coordinate conversion |
| `scripts/dungeon/dungeon_renderer.gd` | 165 | Placeholder visuals (throwaway) |

### Modified

| File | Change |
|---|---|
| `scenes/main.tscn` | Added `DungeonRenderer`, `Camera2D`, `HUD` nodes |
| `scripts/main.gd` | Temporary debug harness: builds the dungeon, camera fit/zoom, edit tools |

### Untouched

`scripts/core/simulation_manager.gd`, `scripts/core/game_time.gd`, `project.godot`
(no new autoloads).

---

## 4. Public API

### `Dungeon`

```gdscript
const TILE_SIZE: int = 32
const DEFAULT_WIDTH: int = 8
const DEFAULT_HEIGHT: int = 5

_init(width := DEFAULT_WIDTH, height := DEFAULT_HEIGHT)

get_floor()      -> DungeonFloor
get_width()      -> int
get_height()     -> int
get_tile_count() -> int

is_valid_position(grid_position: Vector2i) -> bool
get_tile(grid_position: Vector2i)          -> DungeonTile   # null if out of bounds
is_walkable(grid_position: Vector2i)       -> bool          # false if out of bounds

grid_to_world(grid_position: Vector2i)        -> Vector2    # tile top-left px
grid_to_world_center(grid_position: Vector2i) -> Vector2    # tile centre px
world_to_grid(world_position: Vector2)        -> Vector2i   # may be out of bounds
get_world_size()                              -> Vector2
```

### `DungeonFloor`

```gdscript
var width: int
var height: int

_init(p_width: int, p_height: int)

is_valid_position(grid_position: Vector2i) -> bool
get_tile(grid_position: Vector2i)          -> DungeonTile
is_walkable(grid_position: Vector2i)       -> bool
get_tile_count()                           -> int
```

### `DungeonTile`

```gdscript
enum Terrain { FLOOR }

var grid_position: Vector2i
var terrain: Terrain
var walkable: bool
```

### `DungeonRenderer` (throwaway)

```gdscript
var dungeon: Dungeon            # assign to render; setter triggers redraw
var hover_tile: Vector2i        # highlight one tile
var selection: Rect2i           # drag-preview rectangle, grid coords
var selection_color: Color      # preview tint, set by the caller
var view_zoom: float            # camera scale, so lines/labels stay screen-sized
```

---

## 5. Design decisions

These are the points most worth reviewing.

### 5.1 Kept the four-layer Dungeon -> Floor -> Grid -> Tile structure

It looks like over-abstraction for a 40-element array with one floor. Kept anyway
because multiple floors are on the roadmap, and the thin `Dungeon` facade is what keeps
`dungeon.is_walkable(pos)` stable at every call site when floors arrive. Without it,
adding floors later rewrites every caller into
`dungeon.get_floor(n).is_walkable(pos)`. The seam is cheap now and expensive to retrofit.

### 5.2 `walkable` is stored on the tile, not derived from `terrain`

A future system can block a floor tile — creature occupancy, a placed object, a
reserved build site — without inventing a new terrain type for it. Terrain answers
"what is this made of"; `walkable` answers "can something enter". They are not the same
question and they will diverge.

### 5.3 One tile class, data on it — no per-terrain subclasses

Water, soil, rock, mushrooms and environmental properties become **fields on
`DungeonTile`**, not subclasses. A class hierarchy per terrain type would make a tile's
type immutable in practice (you cannot change an object's class), which is wrong for a
simulation where terrain is expected to change at runtime.

### 5.4 `world_to_grid` uses `floori`, not `int()`

`int()` truncates toward zero, so world position `-0.5` maps to tile `0` — meaning a
click just outside the top-left corner would silently read as valid tile `(0,0)`.
`floori` maps it to `-1`, which `is_valid_position` correctly rejects. There is a
regression test pinning this.

### 5.5 Flat row-major tile array

`_tiles[y * width + x]` rather than nested arrays, so all index maths lives in one
private `_index()` method. Bounds checking happens once in `is_valid_position`.

### 5.6 `grid_to_world` returns the tile's top-left corner

The convention was unspecified. Top-left is natural for drawing; `grid_to_world_center`
is provided alongside for placing entities. Both are tested, including a
round-trip through `world_to_grid` for every tile.

### 5.7 Renderer decorations are drawn at a constant *screen* size

Line widths and label text are divided by the camera zoom (`view_zoom`), and the
labels are drawn under an inverse-scale transform so they rasterise at their true
pixel size instead of being magnified.

This was found when the grid shrank from 30 × 30 to a handful of tiles. Decorations had
been drawn in *world* units, so the camera scaled them: at 30 × 30 the fit zoom was
0.66× and they shrank; at 6 × 5 it was 3.96× and they blew up roughly 6×, clipping the
corner label off-screen and turning the 2 px border into an 8 px slab. Sizing them in screen
space makes the renderer correct at any grid size and any zoom level, and it also fixed
pre-existing behaviour where line widths grew when zooming in on a large grid.

### 5.8 `Dungeon` is not an autoload

`SimulationManager` and `GameTime` are genuinely global clocks. A dungeon is game state —
making it an autoload would complicate save/load and rule out more than one instance.
It is owned by the scene instead.

---

## 6. Rendering (placeholder — explicitly throwaway)

No art assets were created. The renderer draws rectangles and lines only:

- Checkerboarded tiles (two shades) so individual tiles stay countable
- Grid lines and axis numbers, marking **every tile** on axes of 12 or fewer and
  every 5th beyond that
- Border outline around the dungeon bounds
- `(0,0)` and `(7,4)` corner labels
- Blocked (non-walkable) tiles drawn in grey
- Hover-tile outline and drag-selection rectangle

It redraws only when something changes (property setters call `queue_redraw`), so it
costs nothing per frame and the simulation remains independent of rendering.

### Camera

The grid is 256 × 160 px and the viewport is 1280 × 720, so a `Camera2D` zooms to fit
(~2.89×) with an 8% margin for the axis labels. The framing reserves a 440 px strip for
the debug HUD and centres the dungeon in what remains, so the HUD never covers the axis
labels. The renderer still draws at true 32 px scale; only the camera scales. All of
this is derived from the dungeon's world size, so it adapts automatically to any grid
dimensions. This is a debug-visibility decision — real camera policy is a future system.

### Debug harness (`scripts/main.gd`)

Temporary. Marked for deletion in its own header comment. Provides:

| Input | Action |
|---|---|
| Mouse wheel / `+` `-` | Zoom, anchored at the cursor |
| `R` | Reset view to fit |
| Left click / drag | Apply current edit mode to a rectangular area |
| `Tab` | Switch edit mode: `ADD` (place grey) / `DELETE` (clear) |
| `Space`, `1`–`4`, `F1`–`F3`, right arrow | Pre-existing System 0 controls |

Two notes on the editing tool:

- **The drag previews only; the data model is written once, on release.**
- **The edit mode is explicit, not inferred from the tile under the cursor.** An earlier
  version decided add-vs-delete from the start tile; that made the same gesture produce
  opposite results depending on where you pressed, and dragging over mixed terrain left
  a checkerboard of toggles.

Clicking a tile flips `tile.walkable` on the **data model** — grey tiles genuinely
return `false` from `dungeon.is_walkable()`. This is not a cosmetic overlay. It reuses
the existing `walkable` field; no new terrain type or tile field was added for it.

---

## 7. Test results

All tests run headless in the real engine (`godot --headless`), not mocked.
Temporary test scripts were deleted after running; they are not part of the codebase.

### Required verification (12 points from the spec) — 48/48 checks pass

Re-run from scratch against the 8 × 5 grid after the resize.

```
1/2  dimensions       8x5, 40 tiles, world size 256x160 px, non-square confirmed
3/4  valid            (0,0) (7,4) (7,0) (0,4)
5/6  invalid          (-1,0) (0,-1) (8,0) (0,5) (8,5) (-1,-1) (4,7) (8,4)
7    tile lookup      corners + interior; out-of-bounds returns null
                      transposed (4,7) correctly null while (7,4) is valid
                      40/40 tiles self-consistent (tile.grid_position == key)
8    grid -> world    (0,0)->(0,0)  (1,0)->(32,0)  (0,1)->(0,32)  (7,4)->(224,128)
                      centre (0,0)->(16,16)
9    world -> grid    31.9->0, 32->1, (255,159)->(7,4), (256,160) out of bounds
                      -0.5 -> -1 (floors, does not truncate)
                      round-trip correct for all 40 tiles
10   initial terrain  0 non-FLOOR, 0 non-walkable, Terrain enum size == 1
--   custom sizes     Dungeon.new(3, 9) -> 27 tiles; (2,8) valid, (8,2) invalid
11   SimulationManager  starts at 0 ticks; live rate 20 ticks/sec at 1x
12   GameTime           Y1 D1 00:00 -> 01:00 after 75 sim s -> Y1 D2 after 1 day
```

The transposed-coordinate and 3 × 9 cases exist specifically because the grid is not
square: they would both pass trivially on a square grid and would hide a width/height
mix-up.

### Interaction tests — 18/18 and 14/14 pass

(Run against the 30 × 30 grid before the resize; the interaction code is
size-independent and was re-smoke-tested at the current size.)

Driven with real `InputEventMouseButton` / `InputEventMouseMotion` / `InputEventKey`
through the engine input system.

```
Zoom
  cursor-anchored zoom: world point under cursor drifts 0.0000 px over 8 steps
  clamps hold at 0.5x and 12.0x of fit zoom
  reset restores zoom 0.6600 and position (480,480)

Drag selection
  preview updates on press and motion; blocked count stays 0 until release
  release applies the whole rectangle atomically
  reverse drags normalise correctly (bottom-right -> top-left)
  drag off the edge clamps into bounds, no crash, still 900 tiles
  single click behaves as a 1x1 drag

Edit modes
  default ADD (amber preview); Tab -> DELETE (red preview); Tab -> ADD
  ADD over an already-grey region adds without un-greying (no toggling)
  DELETE starting on a walkable tile still deletes
  ADD starting on a grey tile still adds
```

### Visual verification

Screenshots captured programmatically. At 30 × 30, tiles `(3,2)`, `(15,15)` and
`(29,29)` were darkened and each landed exactly on its coordinate, with `(15,15)`
sitting precisely on the intersection of the two "15" major grid lines. At 8 × 5, all
eight column labels and all five row labels render clear of the HUD, with `(0,0)` and
`(7,4)` at the correct corners.

### Regressions

None. Clean boot with no errors or warnings. Systems 0 and 0.2 verified still working
as part of the same suite.

---

## 8. Deviations from the specification

| Spec said | What was done | Why |
|---|---|---|
| "Use the existing `scene/` directory. Do NOT rename it to `scenes/`." | Used `scenes/` | `scene/` no longer exists — it had already been renamed to `scenes/` and committed before this task. Renaming it back would be exactly the churn the instruction forbids, and would break the Godot UID cache. |
| Suggested `dungeon.gd` / `dungeon_floor.gd` / `dungeon_tile.gd`, adjustable if simpler | Followed the suggestion exactly, plus `dungeon_renderer.gd` | No simplification taken; see §5.1 |
| "The grid should be centered or positioned cleanly in the viewport" | Added a `Camera2D` that zooms to fit, framed clear of the HUD | At the original 30 × 30 the 960 px grid did not fit a 720 px viewport at 1:1; at 8 × 5 it is far smaller than the viewport and needs zooming in. Fitting by computation handles both, and every tile must be visible to verify the system |

Nothing else diverged. No external packages or plugins were added. No art assets were
created. Nothing was committed.

---

## 9. Open questions / TBD

Points a reviewer may want to rule on:

1. **`grid_to_world` convention** — currently top-left, with `grid_to_world_center`
   alongside. Should entity placement default to centre?
2. **Terrain -> walkable defaults** — with one terrain value, `walkable` is set per-tile
   at construction. When `WALL` / `WATER` arrive, is a `terrain -> default walkable`
   lookup table wanted, or does each creator set both explicitly?
3. **Bounds-check cost** — `get_tile()` validates bounds on every call. Irrelevant at
   40 tiles; may want an unchecked fast path for hot loops (pathfinding) later.
4. **`Dungeon` ownership** — currently owned by the temporary harness scene. Needs a
   permanent home before System 2. Autoload, a `World` node, or passed explicitly?
5. **Tile storage** — one `RefCounted` per tile (40 today). Readable and extensible, but if tile
   counts grow by orders of magnitude, parallel `PackedArray`s would be faster. Not a
   concern at this size.
6. **No save/load** — blocked tiles set via the debug tool are runtime-only and reset
   on restart. Correct for this scope; noting it explicitly.
7. **No undo** on the editing tool, and no cancel mid-drag.

---

## 10. Review checklist before committing

- [ ] `git status`: `scenes/main.tscn` and `scripts/main.gd` modified, `scripts/dungeon/` untracked
- [ ] Include the `.uid` files for the four new scripts — Godot regenerates them
      otherwise and the scene's `ext_resource` reference can drift
- [ ] `scripts/main.gd` is still the throwaway harness and now also owns camera setup
      and dungeon construction; both need a permanent home when it is replaced
- [ ] Cosmetic only: the HUD text overlaps the grid's left edge

---

## Appendix — full source of the data model

### `scripts/dungeon/dungeon_tile.gd`

```gdscript
class_name DungeonTile
extends RefCounted

## A single cell of a dungeon floor. Pure data: a tile never draws itself.
##
## Deliberately minimal. Future systems (soil moisture, mushroom growth,
## creature occupancy) add fields here rather than subclassing per terrain —
## one tile type with data on it, not a class hierarchy.

## Terrain kinds. Only FLOOR exists at this stage; walls, water, soil and rock
## are future systems.
enum Terrain {
	FLOOR,
}

## Where this tile sits on its floor's grid.
var grid_position: Vector2i
## What this tile is made of.
var terrain: Terrain
## Whether creatures may enter. Stored rather than derived from [member terrain]
## so future systems can block a floor tile without inventing a new terrain.
var walkable: bool


func _init(p_grid_position: Vector2i, p_terrain: Terrain = Terrain.FLOOR,
		p_walkable: bool = true) -> void:
	grid_position = p_grid_position
	terrain = p_terrain
	walkable = p_walkable


func _to_string() -> String:
	return "DungeonTile(%s, %s, walkable=%s)" % [
		grid_position, Terrain.keys()[terrain], walkable]
```

### `scripts/dungeon/dungeon_floor.gd`

```gdscript
class_name DungeonFloor
extends RefCounted

## One floor of the dungeon: a fixed-size grid of [DungeonTile].
##
## Pure data. This is the source of truth about what exists where; renderers
## read from it and never write to it.

## Grid width in tiles.
var width: int
## Grid height in tiles.
var height: int

## Row-major tile storage, indexed by `y * width + x`. Flat rather than nested
## arrays so index maths stays in one place ([method _index]).
var _tiles: Array[DungeonTile] = []


func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	_tiles.resize(width * height)
	for y in height:
		for x in width:
			var pos := Vector2i(x, y)
			_tiles[_index(pos)] = DungeonTile.new(pos)


## True if [param grid_position] lies inside this floor's bounds.
func is_valid_position(grid_position: Vector2i) -> bool:
	return grid_position.x >= 0 and grid_position.x < width \
		and grid_position.y >= 0 and grid_position.y < height


## The tile at [param grid_position], or null if out of bounds. Callers that
## already checked bounds can use the result directly; others should null-check.
func get_tile(grid_position: Vector2i) -> DungeonTile:
	if not is_valid_position(grid_position):
		return null
	return _tiles[_index(grid_position)]


## True if the tile exists and may be entered. Out-of-bounds is never walkable.
func is_walkable(grid_position: Vector2i) -> bool:
	var tile := get_tile(grid_position)
	return tile != null and tile.walkable


## Total number of tiles on this floor.
func get_tile_count() -> int:
	return _tiles.size()


func _index(grid_position: Vector2i) -> int:
	return grid_position.y * width + grid_position.x
```

### `scripts/dungeon/dungeon.gd`

```gdscript
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


func get_width() -> int:
	return _floor.width


func get_height() -> int:
	return _floor.height


func get_tile_count() -> int:
	return _floor.get_tile_count()


## True if [param grid_position] is inside the dungeon.
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


## Full dungeon size in world pixels.
func get_world_size() -> Vector2:
	return Vector2(get_width(), get_height()) * TILE_SIZE
```
