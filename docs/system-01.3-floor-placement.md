# System 1.3 — Floor Placement

**Project:** The Cradle (Godot 4.7.2, GDScript, 2D pixel-art dungeon ecosystem sim)
**Status:** Implemented, verified, **not yet committed**
**Builds on:** [System 1 — Dungeon / Grid Foundation](system-01-dungeon-grid.md),
[System 1.1 — Tile Expansion](system-01.1-tile-expansion.md),
[System 1.2 — Floor Expansion](system-01.2-floor-expansion.md)
**Read with:** [System 2 — Creature Life](system-02-creature-life.md), which is what
placed floor is *for*

---

## 1. Scope

A tile belonging to the dungeon is not somewhere anything can walk. The player has
to **build floor on it first**.

| Rule | Behaviour |
|---|---|
| Starting 8 × 5 tiles | exist, but bare — nothing walks on them |
| Tiles bought by expansion | also bare |
| Placing floor | makes a tile walkable |
| Removing floor | returns it to bare ground |
| Cost | free for now |

**Not implemented:** cost per floor tile, build time, floor types or materials, walls,
doors, anything else built on a tile.

---

## 2. The change

### A tile now says what is built on it

`DungeonTile.Terrain` gained a second value, and `EMPTY` is the default:

```gdscript
enum Terrain {
	EMPTY, ## Part of the dungeon, nothing built yet. Not walkable.
	FLOOR, ## Floor placed by the player. Walkable.
}

func _init(p_grid_position: Vector2i, p_terrain: Terrain = Terrain.EMPTY) -> void:
	grid_position = p_grid_position
	terrain = p_terrain
	walkable = p_terrain == Terrain.FLOOR
```

A tile reporting `FLOOR` before any floor had been placed would have misled every
system that reads terrain later, so the state is modelled rather than faked with the
`walkable` flag alone.

### walkable now starts from terrain, but is still its own field

This answers the open question left in System 1 §9.2. `walkable` is **initialised**
from terrain and not **derived** from it, so System 1 §5.2 still holds: a later system
can block a floor tile — occupancy, a placed object, a reserved build site — without
inventing a terrain for it.

The one place both change together is `DungeonFloor`, so they cannot drift apart:

```gdscript
place_floor(grid_position)  -> bool   # EMPTY -> FLOOR, walkable
remove_floor(grid_position) -> bool   # FLOOR -> EMPTY, not walkable
get_floor_tile_count()      -> int
```

Both return `false` when there is no tile there, or when the tile is already in the
state asked for — so a double placement is refused rather than silently repeated.
`Dungeon` forwards all three, acting on the **current** floor, exactly like its other
spatial queries.

### The renderer colours by terrain

It used to grey out a tile when `walkable` was false. It now greys out `EMPTY`. The
picture is the same today, but it now shows *what is built* rather than *what may be
entered* — the two will diverge as soon as anything else blocks a tile.

---

## 3. Debug UI

The two paint modes from System 1.1 became build tools. `Tab` cycles:

| Mode | Action |
|---|---|
| `PLACE_FLOOR` (default) | drag an area to build floor on it |
| `REMOVE_FLOOR` | drag an area to strip floor back to bare ground |
| `EXPAND` | buy a new tile (unchanged) |

The HUD shows `floor 25/40` — tiles built out of tiles owned.

---

## 4. Consequences for creatures

Covered fully in System 2, summarised here because it is the visible effect:

- A creature may only **step onto** a tile with floor.
- Where it is **standing** is not checked, so a creature on bare ground can walk onto
  floor placed beside it, but can never step back off onto bare ground.
- Spawning prefers floor tiles, and only falls back to bare ground when there is no
  floor free.
- Removing floor around a creature strands it where it stands.

---

## 5. Test results — 47 checks in System 1's suite, plus coverage elsewhere

```
tile defaults     a new tile is EMPTY and not walkable
                  a tile constructed as FLOOR is walkable
placing           place_floor makes it FLOOR and walkable
                  neighbours are unaffected
                  placing twice is refused; placing on a missing tile is refused
                  building never changes the tile count
removing          remove_floor returns it to EMPTY and unwalkable
                  removing from bare ground is refused
enum              Terrain is exactly [EMPTY, FLOOR]
expansion (1.1)   a bought tile starts EMPTY; floor can then be placed on it
floors (1.2)      floor placed on floor 1 leaves floor 2 bare
creatures (2)     see System 2 §9
```

Before any test was touched, the existing suite was run against the new rule and
failed in 27 places — every one a test that had assumed tiles start walkable. That is
the blast radius of the change, and it is worth knowing it was measured rather than
guessed.

The rule was also mutation-tested: making creatures treat "a tile exists" as "the tile
has floor" produced 15 failures.

---

## 6. Open questions

1. **Placing floor is free.** Tile expansion costs gold; building probably should too.
2. **No build time** — floor appears the instant the drag is released.
3. **Removing floor under a moving creature** lets it finish its step onto the tile it
   was already entering, and then it is stranded. Harmless, but it is the one moment
   a creature can be standing somewhere it could not have stepped to.
4. **One floor type.** Materials, or floors that affect what grows on them, are a
   later system.
