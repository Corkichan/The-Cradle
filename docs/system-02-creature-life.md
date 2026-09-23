# System 2 — Creature Life

**Project:** The Cradle (Godot 4.7.2, GDScript, 2D pixel-art dungeon ecosystem sim)
**Status:** Implemented, verified, **not yet committed**
**Builds on:** System 0 — Simulation Core and Game Time (the fixed tick and the game
clock; **no document yet**, see the note below), and the dungeon:
[System 1](system-01-dungeon-grid.md) + [1.1](system-01.1-tile-expansion.md) +
[1.2](system-01.2-floor-expansion.md) + [1.3](system-01.3-floor-placement.md)
**First creature:** Rodent / Maniac Sewer Rat

> ### Extended by System 3
>
> [System 3 — Food](system-03-food.md) gave creatures something to eat. Sections marked
> **EXTENDED** below are still true but no longer complete; the linked document has the
> current picture.
>
> **Gap:** System 0 (`SimulationManager`) and System 0.2 (`GameTime`) have no document
> of their own. This system depends on both — the fixed 20 Hz tick and
> `GameTime.get_hour()` — so they are described where needed below, but they deserve
> their own write-up.

---

## 1. Scope

The first living thing in the dungeon, built to answer one question:

> Is it interesting to watch creatures live inside the dungeon?

A rodent spawns on a floor, wanders it, ages, gets hungry, sleeps at night, and
starves to death if it is never fed.

**Implemented**

| | |
|---|---|
| Species | data in a `.tres` file, not a class |
| Movement | 4-directional, one tile at a time, trips of several tiles |
| Driven by | simulation ticks — never `_process` |
| Needs | hunger, which rises with simulation time |
| Sleep | a species-defined window of the game clock |
| Death | starvation at hunger 100 |
| Floors | a creature belongs to one dungeon floor for life |
| Rendering | two static sprites, no animation |

**Not implemented:** food, eating, breeding, population, evolution, genetics, combat,
relationships, behaviour trees, pathfinding, adventurers, world events, save/load,
multiple species, animation, procedural generation.

**EXTENDED** — food and eating were built in [System 3](system-03-food.md). Everything
else on that list remains unbuilt.

---

## 2. Architecture

```
CreatureSpecies (.tres)   Resource   what a species IS: names, rates, timings, sprites
        |
Creature                  RefCounted one creature's state. Never draws, never decides
        ^ ticked by
CreatureSystem            RefCounted owns the collection, ticks it, spawns, validates
        | signals
CreatureLayer             Node2D     one CreatureView per creature, shows one floor
        |
CreatureView              Node2D     Sprite2D + Label, reads the model
```

**EXTENDED.** [System 3](system-03-food.md) added `CreatureBehaviour`, a static class
holding the decision — wander, seek food, eat — so `CreatureSystem` keeps only the
mechanics: what is legal, how a step happens, the random numbers. See §10.4.

Same split as the dungeon: the model is `RefCounted`, outside the scene tree, with no
`_process`, so it *cannot* depend on frame rate. The views read the model and never
write to it.

### There is no Rodent class

A rodent is `res://assets/creatures/rodent/maniac_sewer_rat.tres`. Nothing in the
creature code branches on species; a new creature is a new `.tres`. The scene is
`creature_view.tscn`, not `rodent.tscn`, for the same reason — a scene per species
would reintroduce the class-per-species problem at the scene level.

### The rule that matters most: creatures obey their OWN floor

Since System 1.2, `Dungeon`'s queries answer for whichever floor is being **viewed**.
A creature therefore holds its `DungeonFloor` directly:

```gdscript
## Held directly, NOT reached through [Dungeon], because Dungeon's queries answer
## for whichever floor is being viewed — a creature must keep obeying its own floor
## when the player looks elsewhere.
var dungeon_floor: DungeonFloor
```

Without this, switching the view to Floor 2 would make Floor 1's creatures start
walking according to Floor 2's shape. This is not hypothetical: deliberately breaking
it made floor-1 rats step onto floor-2-only tiles **14,048 times** in one test run.

---

## 3. Public API

### `CreatureSpecies` (Resource)

```gdscript
species_name, variant_name          : String

# Vitals
max_health          : float = 10.0
hunger_rate         : float   # hunger per simulation second
hungry_threshold    : float = 70.0
initial_hunger_max  : float = 30.0   # spawn hunger is random in [0, this]

# Movement
idle_time_min / idle_time_max : float   # rest between trips, sim seconds
move_duration                 : float   # sim seconds to cross one tile
trip_steps_min / trip_steps_max : int   # tiles walked per trip

# Sleep
sleep_start_hour, wake_hour : int   # 24h clock; may wrap past midnight
is_sleep_hour(hour: int) -> bool

# Visuals
side_texture, front_texture : Texture2D
side_faces_left             : bool
display_height_tiles        : float
```

### `Creature` (RefCounted)

```gdscript
# EXTENDED: SEEK_FOOD and EAT were added by System 3, along with an Intent enum,
# food_target, wants_food() and feed(). HUNGRY now means "wants food but knows of
# none in range".
enum State { IDLE, WANDER, HUNGRY, SLEEP, DEAD }
const MAX_HUNGER := 100.0
const STEP_DIRECTIONS := [UP, DOWN, LEFT, RIGHT]

id, species, dungeon_floor
grid_position, move_target, move_progress, facing, trip_steps_left
health, hunger, age, state, alive, asleep

is_moving() / is_hungry() / is_ready_to_move() / has_steps_left()
rest(duration) / begin_trip(steps) / start_move(target) -> bool
advance(delta: float, hour_of_day: int) -> bool   # true on arrival
```

### `CreatureSystem` (RefCounted)

```gdscript
signal creature_spawned(creature)
signal creature_died(creature)      # already removed when this fires

_init(rng_seed := -1, connect_to_simulation := true)

get_creatures() / get_creature_count() / get_creatures_on(dungeon_floor)
spawn(species, dungeon_floor, count := 1) -> Array[Creature]
is_tile_free(dungeon_floor, position, ignore := null) -> bool
can_move_to(creature, target) -> bool
try_move(creature, target) -> bool
tick(delta, hour_of_day := -1)      # -1 reads the game clock
```

---

## 4. Movement

A creature occupies one tile. A step is legal only when the target is:

1. exactly one orthogonal tile away (no diagonals, no jumps),
2. an existing **walkable** tile — one with floor placed — on **its own** floor,
3. not occupied by, or being entered by, another creature on that floor.

Where the creature is *standing* is deliberately not checked, so one on bare ground
can step onto floor placed beside it, but never back off onto bare ground.

`Creature.start_move()` independently refuses diagonals, jumps, a second step
mid-step, and any movement while asleep or dead — the model will not do the wrong
thing whoever asks it. Walkability is checked by the system, which is the part that
knows about the world.

### Trips

A creature walks **`trip_steps_min`–`trip_steps_max` tiles in one go**, then rests
`idle_time_min`–`idle_time_max` seconds. Within a trip it **prefers not to double
back**, so it covers ground instead of jittering on one spot.

Measured in the running game: each rat crossed **37–43 tiles per game minute**,
ranging over the whole floor.

If no legal step exists, the creature rests and tries again — a walled-in creature
simply stays put.

---

## 5. Simulation time

`CreatureSystem.tick` is connected to `SimulationManager.simulation_tick`. No creature
logic runs in `_process`. A paused simulation sends no ticks, and 10x speed sends them
ten times as often, so pause and speed are inherited rather than implemented.

`tick(delta, hour_of_day := -1)` reads `GameTime.get_hour()` when no hour is given.
Tests pass an hour explicitly, so sleeping behaviour never depends on what time the
shared clock happens to be at.

**Float accumulation matters here.** `0.05 / 0.5` added ten times gives
`0.9999999999999999`, so without a tolerance every step and every rest would overrun
by a whole tick — about 10% at the rodent's pace. `Creature._TIME_EPSILON` fixes it,
and a test pins exact tick counts so it cannot regress.

On screen, the sprite **eases** toward the model's position each frame, because
20 updates a second would otherwise look steppy. That easing is cosmetic only: it
cannot move a creature anywhere the simulation did not, and when the simulation pauses
the target stops and the sprite settles onto it.

---

## 6. Age, hunger, sleep, death

### Age

Starts at 0 and adds each tick's delta, so it is in simulation seconds. It is a plain
float rather than GameTime's integer ticks: GameTime needs exact day boundaries over
millions of ticks, age is only displayed. Creatures age while asleep.

### Hunger

Rises at `hunger_rate` per simulation second, from a **random starting value** in
`[0, initial_hunger_max]` so a group does not all cross the threshold on the same
tick. At `hungry_threshold` the state becomes `HUNGRY` and the label turns orange.

With no food system, a hungry creature keeps wandering: HUNGRY is reported, not acted
on. It is ready to become a behaviour state the moment there is something to eat.

### Sleep

Between `sleep_start_hour` and `wake_hour` on the game clock a creature is `asleep`:
it does not start trips, dims on screen, and its label turns blue. A step already
under way **finishes**, so it always comes to rest on a tile rather than between two.
Age and hunger keep going.

The window may wrap past midnight (22 → 6) or not (6 → 22), and equal hours mean the
species never sleeps. Swapping the rodent's two numbers makes it nocturnal, which is
what a real rat would be.

### Death

At `MAX_HUNGER` (100) the creature starves: `alive` goes false, health drops to 0, it
stops where it fell, `CreatureSystem` removes it and emits `creature_died`, and
`CreatureLayer` frees its sprite. A dead creature stops ageing and cannot be moved.

---

## 7. Balance, and one thing worth knowing

**With no food in the game, every creature starves eventually.** That is the expected
end state until Food exists, and it is what makes Food the obvious next system.

The numbers needed rebalancing twice when sleep and death met each other:

| | hunger_rate | Result |
|---|---|---|
| Original | 0.5 /s | dead in 200 sim s — about 1/9 of a day |
| First try | 0.08 /s | **all three rats starved in their sleep on the first night** |
| Now | 0.04 /s | sleeps through the night, hungry mid-morning, dies mid-afternoon on day two |

A night is 8 game hours = 600 simulation seconds, which at 0.08/s costs 48 hunger —
enough to kill a rat that went to bed at 58. This was found by running the game, not
by reading the code.

An obvious future refinement is a lower hunger rate while asleep; it was left out
because it was not asked for and one number achieved the same result.

### Current rodent

```
hunger_rate 0.04   hungry_threshold 70   initial_hunger_max 30
move_duration 1.0  trip 3-8 tiles        idle 1.5-4.0 s
sleep 22:00 -> 06:00
```

---

## 8. Sprites, floors and debug UI

**Sprites.** Two static images, no animation. The side sprite is used for east, west
and (lacking a back sprite) north; the front sprite for south. `Side.png` is drawn
**facing left**, so the flip happens when moving **east** — `side_faces_left` records
this, so art drawn either way works. Both use one scale, so a creature does not change
size when it turns.

The files are `Front.png` and `Side.png` with capital letters. Windows does not care;
exported builds treat `res://` paths as case-sensitive.

**Floors.** A creature belongs to one floor for life. Creatures on every floor keep
living whichever floor is being viewed; only the current floor's views are drawn, and
views are hidden rather than rebuilt on a switch. Nothing moves between floors.

**Debug controls** (in the throwaway harness):

| Key | Action |
|---|---|
| `S` | spawn a rodent on the floor being viewed |
| `L` | show / hide creature labels |
| `F` | drop a pile of food (System 3) |
| `V` | show the food search area of hungry creatures (System 3) |

The HUD shows `Rodents 3 (3 here, 3 asleep, 1 starved)`. Each label shows
`Rodent #1 WANDER` / `Age 12s Hunger 35`.

There are **no creatures at startup** — place floor, then press `S`.

---

## 9. Test results — 186 checks in the System 2 suite, 432 overall

Run them with:

```
godot --headless --path . res://tests/test_runner.tscn
```

```
identity      species and variant come from the .tres; a plain Creature, no subclass
spawning      on free tiles, never two on one tile, capped by space
              prefers floor, falls back to bare ground
floor rule    never moves with no floor; walks onto floor placed beside it
              never steps back onto bare ground; stranded when floor is removed
trips         a 4-tile trip takes exactly 41 ticks with no pause in the middle
              rarely doubles back
sleep         window logic incl. wrapping, non-wrapping and never-sleeping
              motionless all night, still ageing; wakes in the morning
              finishes the step it started when night falls
starvation    dead at exactly 100; removed; signal fires once; sprite freed
              frozen afterwards; other creatures unaffected
movement      out of bounds, sparse holes, floorless tiles, diagonals, jumps,
              occupied tiles and reserved tiles all refused
timing        steps advance on simulation ticks with exact tick counts
pause/speed   nothing changes while paused; 10x runs ~10x faster
age/hunger    exact rates; HUNGRY at the threshold
independence  separate objects, separate hunger, separate paths
invariants    20,000 ticks on a ragged floor: never on a missing or floorless tile,
              never a diagonal or multi-tile step, never two on one tile
floors        floor-1 creatures ignore floor 2's shape while floor 2 is viewed
view          correct sprite and flip per direction; same scale; follows the model
layer         only the viewed floor is drawn; a dead creature's view is freed
main scene    starts empty; place floor, press S, they walk
```

### The tests were checked against deliberate bugs

Passing tests prove nothing if they cannot fail. Five mutations, all caught:

| Broken on purpose | Failures |
|---|---|
| Ignore walkability when moving | 12 |
| Obey the *viewed* floor instead of its own | 2 (incl. 14,048 illegal steps) |
| Remove the float tolerance | 5 |
| Allow diagonal steps | 5 |
| Treat "tile exists" as "tile has floor" | 15 |

One of those runs exposed a weak test: a check that compared only a creature's *final*
position could pass by luck when a random walk returned to its start. It now watches
every tick.

---

## 10. Architectural decisions

1. **A species is data**, not a class, and neither is the view scene.
2. **Creatures query their own floor**, never the `Dungeon` facade (§2).
3. **The model holds data and integrates time; the system decides.** `Creature` never
   picks a destination; `CreatureSystem` validates and chooses.
4. ~~**The wander choice lives in `CreatureSystem`** because it is the only behaviour.~~
   **Done in [System 3](system-03-food.md).** Seeking food was that second behaviour, so
   the decisions moved into `CreatureBehaviour` and `CreatureSystem` kept the mechanics.
   All 186 checks here passed unchanged across the split, which is the evidence it was
   behaviour-preserving.
5. **Views ease toward the model** — cosmetic only (§5).
6. **`creature_died` fires after removal**, so a listener never sees a dead creature
   in the collection.

---

## 11. Open questions

1. ~~**Food is the obvious next system**~~ — built in [System 3](system-03-food.md).
   Creatures now seek and eat, though nothing produces food yet, so a dungeon left alone
   still starves.
2. **Hunger does not slow while asleep.** Realistic and cheap to add; left out as
   unrequested.
3. **Labels overlap** when two creatures stand on neighbouring tiles. `L` hides them.
4. **Occupancy is checked creature-against-creature each tick** — fine for dozens,
   wants a tile lookup before hundreds.
5. **`health` is stored but unused** except being zeroed on death.
6. **No corpses.** A dead creature vanishes; Food may want to change that.
7. **No back sprite**, so creatures moving north show the side view.
8. **`Dungeon` and the creature system are owned by the throwaway harness** and need a
   permanent home.
9. **Runtime only** — no save/load, so everything resets on restart.
