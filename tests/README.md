# Tests

Every system in The Cradle has a suite here. They run headless in the real Godot
engine — no mocks, no test framework, no plugin.

## Running them

```
godot --headless --path . res://tests/test_runner.tscn
```

On this machine Godot lives at
`D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`.

The runner exits **0** when everything passes and **1** otherwise, so it drops
straight into CI or a git hook.

```
godot --headless --path . res://tests/test_runner.tscn -- --verbose
godot --headless --path . res://tests/test_runner.tscn -- --only=system_2
```

`--verbose` prints every check instead of just failures. `--only=<fragment>` runs the
suites whose filename contains that fragment.

Expected output, about 15 seconds:

```
System 0 / 0.2 - Simulation Core and Game Time
  26 passed, 0 failed
System 1 - Dungeon / Grid Foundation
  47 passed, 0 failed
System 1.1 - Tile Expansion
  35 passed, 0 failed
System 1.2 - Floor Expansion
  33 passed, 0 failed
System 2 - Creature Life
  186 passed, 0 failed
System 3 - Food
  105 passed, 0 failed

==== ALL PASS: 432 passed, 0 failed, 6 suites, 15.2s ====
```

## Files

| File | Covers |
|---|---|
| `test_runner.gd/.tscn` | runs the suites in order, prints the summary, sets the exit code |
| `test_suite.gd` | base class: `check`, `check_true/false/approx/between`, `frames`, `real_seconds` |
| `test_system_0_simulation.gd` | fixed tick, pause, speed, game time, day and year rollover |
| `test_system_1_grid.gd` | grid, coordinates, tile defaults, placing and removing floor |
| `test_system_1_1_tile_expansion.gd` | adjacency rules, buying tiles, gold |
| `test_system_1_2_floor_expansion.gd` | multiple floors, independence, floor cost |
| `test_system_2_creatures.gd` | creature life: movement, trips, sleep, hunger, death |
| `test_system_3_food.gd` | food: placement, perception, seeking, eating, depletion |

## Writing a suite

Extend the base by path, so test classes stay out of the project's global class names:

```gdscript
extends "res://tests/test_suite.gd"

func _init() -> void:
	title = "System 3 - Something New"

func run() -> void:          # may await
	section("a heading")
	check("two and two", 2 + 2, 4)
	check_true("it is true", true)
	await frames(2)
```

Then add the path to `SUITES` in `test_runner.gd`.

## Things to know

**Suite order matters.** All suites share the `SimulationManager` and `GameTime`
autoloads. System 0 checks their starting values, so it must run first. The runner
holds the simulation **paused** between suites so real frames cannot advance it behind
a test's back; suites that need live time resume it themselves and pause again.

**Creature tests pass an hour explicitly.** `CreatureSystem.tick(delta, hour)` takes
the hour so sleeping behaviour never depends on where the shared clock happens to be.
Tests that go through `SimulationManager` with a species that sleeps call
`_advance_to_daytime()` first.

**Long-running creature tests switch hunger off.** A test that runs for hundreds of
simulated seconds will otherwise have its subject starve partway through and stop
moving for the wrong reason.

**A syntax error in a suite hangs the runner** rather than failing it — Godot's
`load()` never returns. If a run hangs, check the suite with:

```
godot --headless --path . --check-only --script res://tests/test_system_2_creatures.gd
```

Note that `--check-only` does not register autoloads, so it falsely reports
`GameTime` and `SimulationManager` as unknown identifiers. Ignore those two; any other
parse error is real.

## Do the tests actually catch bugs?

They are checked against deliberately broken code rather than assumed to work. Nine
mutations have been run so far:

| Broken on purpose | Caught |
|---|---|
| Creatures ignore walkability | 12 failures |
| Creatures obey the *viewed* floor, not their own | 2 (incl. 14,048 illegal steps) |
| Remove the float tolerance from step timing | 5 |
| Allow diagonal steps | 5 |
| Treat "a tile exists" as "the tile has floor" | 15 |
| Eating does not reduce the pile | 8 |
| Perception ignores the detection radius | **not caught at first** — see below |
| A creature never stops seeking food | 6 |
| An emptied pile is never removed | 5 |

Eight of the nine were caught immediately. The ninth was the most useful, because it
was not: the radius turned out to be enforced in **two** places, so deleting one copy
changed nothing, and the check that should have noticed was **flaky** — it relied on
randomly scattered food landing near a randomly placed creature. Both were fixed and
the mutation now fails six checks.

Two other runs exposed weak checks that could pass by luck: one compared only a
creature's final position after a random walk, which can wander away and come back.
They now watch every tick.

If you change behaviour on purpose, expect failures here, and read them before
updating them: in this project they have repeatedly been the first sign of a real
design consequence rather than a stale expectation — the clearest being that adding
starvation quietly made two long-running movement tests kill their own subject.
