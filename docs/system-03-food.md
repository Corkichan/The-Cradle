# System 3 — Food

**Project:** The Cradle (Godot 4.7.2, GDScript, 2D pixel-art dungeon ecosystem sim)
**Status:** Implemented, verified, **not yet committed**
**Builds on:** [System 2 — Creature Life](system-02-creature-life.md) and the dungeon
([1](system-01-dungeon-grid.md) / [1.1](system-01.1-tile-expansion.md) /
[1.2](system-01.2-floor-expansion.md) / [1.3](system-01.3-floor-placement.md))

---

## 1. Scope

The first real interaction between a creature and its environment, closing the loop:

```
hunger -> perception -> intent -> walk to food -> eat
       -> hunger falls -> food is consumed -> back to wandering
```

**Implemented**

| | |
|---|---|
| Food source | position, amount, nutrition — an object in the world |
| Perception | nearest pile within a radius, counted in steps |
| Intent | `WANDER` / `SEEK_FOOD` / `EAT` |
| Movement | greedy step, reusing the existing grid movement |
| Eating | deterministic mouthfuls, food and hunger fall together |
| Depletion | an emptied pile leaves the world and its sprite goes |
| Placement | debug scatter, plus **F** to drop one |

**Not implemented:** food types, spoilage, decay, farming, cooking, inventory, economy,
corpses-as-food, breeding, predator/prey, pathfinding, behaviour trees, utility AI,
line of sight, save/load.

---

## 2. Architecture

```
FoodSystem   RefCounted   owns every pile; answers "what food is near here"
  +-- FoodSource          position, amount, nutrition — pure data
FoodLayer    Node2D       one view per pile, current floor only
  +-- FoodView            the sprite and its remaining-amount label
```

### Food is environmental, never owned by a creature

A creature holds a **reference** to a `FoodSource` that lives in the world and takes
from it. Nothing about eating lives on the food itself, so a goblin, a slime or an
adventurer will use the same object unchanged. A pile holds its own `DungeonFloor`
directly, for the same reason creatures do — `Dungeon` answers for whichever floor is
being *viewed*.

### The dependency points one way, and that is load-bearing

Creatures know about food. **Food knows nothing about creatures.**

The first version broke this: `FoodSystem` held a `creature_system` field (to keep food
from landing under a creature) while `CreatureSystem` held `food_system`. Two
`RefCounted` objects referencing each other are never freed, and the very next boot
said so:

```
WARNING: 11 ObjectDB instances were leaked at exit
ERROR: 5 resources still in use at exit
```

Occupancy is now passed **in** as an optional parameter at the point of use:

```gdscript
can_place_at(dungeon_floor, position, occupants: CreatureSystem = null) -> bool
```

The rule stays testable, the cycle is gone, and the arrow only points one way.

### The creature behaviour split

`CreatureSystem` used to own the wander decision. System 2's doc said that when a
second behaviour arrived, behaviours should be pulled out rather than letting that
class become the place all creature logic lives. Food was that moment, so there is now:

```
CreatureBehaviour   static   WHAT to do: wander, seek food, eat
CreatureSystem              WHAT IS POSSIBLE: legality, stepping, random numbers
```

A handful of static functions, not a framework. The evidence it changed no behaviour:
all 186 System 2 checks passed untouched across the split.

---

## 3. Public API

### `FoodSource` (RefCounted)

```gdscript
const DEFAULT_AMOUNT := 100.0
const DEFAULT_NUTRITION := 25.0

id, dungeon_floor, grid_position, amount, nutrition

is_depleted() -> bool
take_bite()   -> float   # min(nutrition, amount); amount never goes below 0
```

### `FoodSystem` (RefCounted)

```gdscript
signal food_placed(food)
signal food_depleted(food)      # already removed when this fires

_init(rng_seed := -1)

get_sources() / get_count() / get_sources_on(floor) / has(food)
at(floor, position)                                  -> FoodSource
can_place_at(floor, position, occupants := null)     -> bool
place(floor, position, amount, nutrition, occupants) -> FoodSource   # null if refused
place_random(floor, count, amount, nutrition, occupants) -> Array[FoodSource]
find_nearest(floor, from, radius)                    -> FoodSource   # null if none
remove(food)
```

### Added to `CreatureSpecies`

```gdscript
@export_group("Food")
food_detection_radius : int   = 3     # steps
sated_threshold       : float = 30.0  # stops seeking at this hunger
eat_duration          : float = 1.0   # simulation seconds per mouthful
```

### Added to `Creature`

```gdscript
enum Intent { WANDER, SEEK_FOOD, EAT }
enum State  { IDLE, WANDER, HUNGRY, SEEK_FOOD, EAT, SLEEP, DEAD }

var intent: Intent
var food_target: FoodSource     # a REFERENCE to a pile in the world

wants_food() -> bool
set_intent(value) / forget_food_target()
feed(nutrition)                 # hunger never goes below 0
```

`CreatureSystem` gained one optional field, `food_system`. With none attached,
creatures wander exactly as they did in System 2.

---

## 4. Perception

`find_nearest(floor, from, radius)` returns the closest non-empty pile within the
radius, **on that floor only**. Ties go to the lowest id, so the same situation always
produces the same choice.

Distance is counted in **steps** (Manhattan), matching how creatures move. The area is
therefore a **diamond**, not a circle: food five tiles away diagonally is ten steps and
invisible.

It is re-evaluated **every tick**, which is what produces the behaviour the whole
system hangs on:

> A hungry creature with no food in range keeps wandering. The moment a pile enters
> its area, it locks on and walks straight there.

Measured in a real run, with a hungry rat and the only pile 11 steps away:

```
while it had no target, the closest it ever got was 6 steps
it locked on at 5 steps, which is inside the radius of 5
```

### Why the radius is 3

The area grows quadratically, which is easy to underestimate:

| radius | tiles |
|---|---|
| 1 | 5 |
| 2 | 13 |
| **3** | **25** |
| 4 | 41 |
| 5 | 61 |

The starting floor is **40 tiles**. At the original radius of 5 the search area covered
61 — larger than the entire dungeon — so a creature effectively knew about every pile
everywhere and could never be seen to search. At 3 it covers 25, and searching means
something. It is one number per species.

---

## 5. Intent, and how it relates to state

`Intent` is what the creature has decided to do. `State` is what you see, derived from
intent plus conditions:

```
DEAD > SLEEP > EAT > SEEK_FOOD > HUNGRY > WANDER > IDLE
```

`HUNGRY` now means something precise: **it wants food but knows of none in range**, so
it is still wandering. Once a pile is in range the state becomes `SEEK_FOOD`.

Hunger uses **hysteresis**: a creature starts caring at `hungry_threshold` (70) and does
not stop until hunger falls to `sated_threshold` (30), so one mouthful does not make it
abandon a meal.

---

## 6. Seeking and eating

**Walking there** is a greedy step: of the legal neighbours, the one that gets closest.
Deliberately not pathfinding. On an open floor it walks straight there; a wall between
creature and food can delay it, which is why food is expected to be reachable across
neighbouring tiles for now. When nothing gets it closer it steps sideways rather than
freezing.

**Eating** happens standing on the pile. One mouthful, then it chews for `eat_duration`
before the next:

```
amount -= nutrition      both clamped: amount never below 0, hunger never below 0
hunger -= nutrition
```

The last bite of a nearly empty pile is only what is left. At zero the pile is removed
from the world, `food_depleted` fires, the sprite is freed, and any other creature
targeting it lets go on its next tick and picks something else.

**Multiple creatures** may target the same pile; the first to arrive eats. Because two
creatures cannot share a tile, a second one waits beside it. No competition beyond that.

### Worked example

```
rodent hunger 70, pile amount 100, nutrition 25, sated 30
bite 1 -> hunger 45, pile 75
bite 2 -> hunger 20, pile 50   (20 <= 30, so it stops)
back to wandering, target released
```

---

## 7. Visuals

`Icon43.png`, the provided sprite, is 32 × 32 with a transparent background — exactly
one tile. It arrived as an attachment rather than a file in the project, so it was
copied to `assets/food/Icon43.png`.

Drawn at **0.8 tiles** so it reads as an object resting on the floor, with a small
label showing what is left. `FoodLayer` sits **between** the dungeon and the creatures
in the scene, so a creature standing on food covers it. No animation.

Because there is exactly one kind of food, the texture is preloaded in `FoodView`. When
food types arrive it moves into a resource, the way creature sprites live on
`CreatureSpecies`.

### Debug controls

| Key | Action |
|---|---|
| `F` | drop one pile on a free floor tile of the floor being viewed |
| `V` | show each hungry creature's food search area |

The area overlay draws the diamond: **amber** while it has found nothing, **green** once
a pile is inside it. The HUD reads `Food 3 (225 left, 0 seeking, 1 eating)`.

**Startup placement puts down nothing on a fresh dungeon**, because no tile has floor
yet (System 1.3). It prints `No floor yet, so no food placed - build some floor, then
press F`, and does place 4 piles if floor already exists.

---

## 8. Test results — 105 checks in the System 3 suite, 432 overall

```
godot --headless --path . res://tests/test_runner.tscn
```

```
food data     amount and nutrition, configurable; bites never go negative;
              the last bite is only what is left
placement     on floor; refused outside the dungeon, on bare ground, on a tile
              that already has food, and under a creature; scatter caps by space;
              a dungeon with no floor takes none
perception    finds within radius, blind beyond it, prefers the nearer pile,
              ignores emptied piles and other floors, counts steps not diagonals
intent        not hungry -> WANDER; hungry with food in range -> SEEK_FOOD;
              hungry with nothing in range -> keeps wandering, reports HUNGRY
movement      walks to the pile and never away from it; still gets there with a
              hole in the floor in the way
eating        arrives and eats; hunger and amount fall together; chews for
              eat_duration between mouthfuls; stops at the sated threshold;
              a creature that is not hungry ignores food it is standing on
depletion     emptied pile is removed, signal fires once, the eater lets go
multiple      two creatures target one pile; the first eats it; the other
              re-evaluates; two creatures eat two piles independently
pause/speed   paused, nothing about the meal changes; 10x eats ~10x faster
main scene    food system wired in, F drops food, a hungry rodent finds and eats
```

### The tests were checked against deliberate bugs

| Broken on purpose | Failures |
|---|---|
| Eating does not reduce the pile | 8 |
| Perception ignores the radius | 6 |
| Never stops seeking (no sated threshold) | 6 |
| An emptied pile is never removed | 5 |

The radius mutation **was not caught at first**, and that was worth more than the three
that were. It exposed two real problems:

1. **The radius was enforced twice.** `best_distance` started at `radius + 1`, which
   made the explicit check redundant — deleting one copy changed nothing. A rule kept
   in two places is a rule no test can prove you still have. It now lives in one place.
2. **One check was flaky.** The main-scene test scattered food and a creature at random
   with unseeded RNG, so whether the creature ever wandered within range was luck. It
   now plants a pile beside the creature.

With both fixed, the mutation fails 6 checks.

---

## 9. Open questions

1. **A creature only reconsiders while hungry.** It will not drop a distant pile for a
   closer one that appears mid-walk.
2. **No pathfinding**, so a wall between creature and food can stall the approach.
3. **No competition** beyond first-come-first-served and not sharing a tile.
4. **Food never decays, spreads or regrows** — it only appears when the player drops it.
5. **No corpses.** A starved creature leaves nothing behind; that is the obvious link
   between System 2's death and this system.
6. **One food type**, with its texture preloaded in the view (§7).
7. **`find_nearest` and `at` scan every pile.** Fine for a handful; wants a per-tile
   lookup before hundreds.
8. **Runtime only** — no save/load, so food resets on restart.
