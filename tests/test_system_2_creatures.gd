extends "res://tests/test_suite.gd"

const RODENT: CreatureSpecies = preload("res://assets/creatures/rodent/maniac_sewer_rat.tres")
const VIEW_SCENE: PackedScene = preload("res://scenes/creatures/creature_view.tscn")
const TICK: float = 0.05
## Hours passed to tick() so sleep behaviour never depends on the shared clock.
const DAY_HOUR: int = 12
const NIGHT_HOUR: int = 23


func _init() -> void:
	title = "System 2 - Creature Life"


func run() -> void:
	_test_identity()
	_test_spawning()
	_test_needs_floor_to_walk()
	_test_trips()
	_test_sleep()
	_test_starvation()
	_test_movement_rules()
	_test_timing_through_simulation()
	await _test_pause_and_speed()
	_test_age_and_hunger()
	_test_independence()
	_test_invariants_over_long_run()
	_test_own_floor_not_viewed_floor()
	await _test_view()
	await _test_layer()
	await _test_main_scene()


# --------------------------------------------------------------------------

## Species with fixed, round timings so tick counts are exact.
func _species(idle := 1.0, move := 0.5, rate := 1.0, threshold := 70.0,
		trip_min := 1, trip_max := 1) -> CreatureSpecies:
	var s := CreatureSpecies.new()
	s.species_name = "Rodent"
	s.variant_name = "Test Rat"
	s.idle_time_min = idle
	s.idle_time_max = idle
	s.move_duration = move
	s.hunger_rate = rate
	s.hungry_threshold = threshold
	s.initial_hunger_max = 0.0
	s.trip_steps_min = trip_min
	s.trip_steps_max = trip_max
	# Never sleeps unless a test says otherwise.
	s.sleep_start_hour = 0
	s.wake_hour = 0
	s.side_texture = RODENT.side_texture
	s.front_texture = RODENT.front_texture
	return s


## Places floor on every tile of [param f], so creatures may walk anywhere on it.
func _with_floor(f: DungeonFloor) -> DungeonFloor:
	for position in f.get_positions():
		f.place_floor(position)
	return f


func _floored(width := 8, height := 5) -> DungeonFloor:
	return _with_floor(DungeonFloor.new(width, height))


## A floor with a ragged edge and floorless tiles inside, for movement tests.
##    x: -1  0  1  2  3  4  5  6  7  8
##    y0     .  .  .  .  .  .  .  .
##    y1     .  #  .  .  .  .  .  .
##    y2  +  .  .  .  .  .  .  .  .  +      + = bought, # = no floor
##    y3     .  .  .  #  .  .  .  .
##    y4     .  .  .  .  .  .  .  .
func _ragged_floor() -> DungeonFloor:
	var f := DungeonFloor.new(8, 5)
	f.add_tile(Vector2i(-1, 2))
	f.add_tile(Vector2i(8, 2))
	_with_floor(f)
	f.remove_floor(Vector2i(1, 1))
	f.remove_floor(Vector2i(3, 3))
	return f


func _run_ticks(system: CreatureSystem, count: int, hour := DAY_HOUR) -> void:
	for i in count:
		system.tick(TICK, hour)


## Steps the shared clock into the middle of the day, for tests driven through
## SimulationManager with a species that does sleep.
func _advance_to_daytime() -> void:
	var guard := 0
	while (GameTime.get_hour() < 9 or GameTime.get_hour() > 18) and guard < 2000:
		SimulationManager.step(25)
		guard += 1


# --------------------------------------------------------------------------

func _test_identity() -> void:
	section("1-3 identity")
	var c := Creature.new(1, RODENT, DungeonFloor.new(8, 5), Vector2i(2, 2))
	check_true("rodent can be created", c != null)
	check("species", c.get_species_name(), "Rodent")
	check("variant", c.get_variant_name(), "Maniac Sewer Rat")
	check("id", c.id, 1)
	check("health from species", c.health, RODENT.max_health)
	check("age starts 0", c.age, 0.0)
	check("state IDLE", c.state, Creature.State.IDLE)
	check_true("no per-species class: a plain Creature", c.get_script() == Creature)


func _test_spawning() -> void:
	section("4 spawning")
	var f := _ragged_floor()
	var system := CreatureSystem.new(7, false)
	var spawned := system.spawn(RODENT, f, 3)
	check("3 spawned", spawned.size(), 3)
	var tiles := {}
	for c in spawned:
		check_true("#%d on walkable tile of its floor" % c.id, f.is_walkable(c.grid_position))
		tiles[c.grid_position] = true
	check("no two on one tile", tiles.size(), 3)
	check("ids unique", [spawned[0].id, spawned[1].id, spawned[2].id], [1, 2, 3])

	var crowd := CreatureSystem.new(7, false)
	var small := DungeonFloor.new(8, 5)
	check("spawn caps at free tiles", crowd.spawn(RODENT, small, 100).size(), 40)
	check("full floor spawns nothing more", crowd.spawn(RODENT, small, 1).size(), 0)

	section("spawning prefers floor, then bare ground")
	var half := DungeonFloor.new(2, 1)
	half.place_floor(Vector2i(1, 0))
	var pair := CreatureSystem.new(1, false).spawn(RODENT, half, 5)
	check("one creature per tile", pair.size(), 2)
	check("first goes on the floor tile", pair[0].grid_position, Vector2i(1, 0))
	check("second falls back to bare ground", pair[1].grid_position, Vector2i(0, 0))
	var bare := CreatureSystem.new(1, false).spawn(RODENT, DungeonFloor.new(8, 5), 3)
	check("with no floor at all, still spawns", bare.size(), 3)
	check_false("and stands on bare ground", bare[0].dungeon_floor.is_walkable(bare[0].grid_position))


## The rule: tiles start as bare ground, and nothing walks until floor is placed.
func _test_needs_floor_to_walk() -> void:
	section("creatures only walk on placed floor")
	var f := DungeonFloor.new(5, 5)
	var system := CreatureSystem.new(21, false)
	# Hunger off: this test runs for 330 simulated seconds, long enough for the
	# creature to starve, which would stop it moving for the wrong reason.
	var rat := Creature.new(1, _species(0.2, 0.3, 0.0), f, Vector2i(2, 2))
	system.get_creatures().append(rat)
	# Watch every tick, not just the end: a random walk can wander off and come
	# back, so checking the final position alone could pass by luck.
	var moved_ticks := 0
	for i in 400:
		system.tick(TICK, DAY_HOUR)
		if rat.grid_position != Vector2i(2, 2) or rat.is_moving():
			moved_ticks += 1
	check("no floor anywhere: never moves or starts a step in 20 s", moved_ticks, 0)
	for direction in Creature.STEP_DIRECTIONS:
		check_false("cannot step onto bare ground %s" % (Vector2i(2, 2) + direction),
			system.can_move_to(rat, Vector2i(2, 2) + direction))

	f.place_floor(Vector2i(3, 2))
	check_true("floor placed beside it: may step there", system.can_move_to(rat, Vector2i(3, 2)))
	var reached := false
	for i in 200:
		system.tick(TICK, DAY_HOUR)
		if rat.grid_position == Vector2i(3, 2):
			reached = true
			break
	check_true("walks onto the new floor", reached)
	var strayed := 0
	for i in 2000:
		system.tick(TICK, DAY_HOUR)
		if rat.grid_position != Vector2i(3, 2) or rat.is_moving():
			strayed += 1
	check("on a one-tile floor: never steps back onto bare ground", strayed, 0)

	for x in 5:
		f.place_floor(Vector2i(x, 2))
	var visited := {}
	var off_strip := 0
	for i in 4000:
		system.tick(TICK, DAY_HOUR)
		visited[rat.grid_position] = true
		if rat.grid_position.y != 2 or rat.move_target.y != 2:
			off_strip += 1
	check("floor laid as a strip: roams only the strip", off_strip, 0)
	check_true("and uses it", visited.size() >= 4)

	section("removing floor strands a creature")
	while rat.is_moving():
		system.tick(TICK, DAY_HOUR)
	var island := rat.grid_position
	for x in 5:
		if Vector2i(x, 2) != island:
			f.remove_floor(Vector2i(x, 2))
	_run_ticks(system, 1000)
	check("floor removed around it: stays on its island", rat.grid_position, island)


## Creatures cross several tiles per trip, so they cover ground.
func _test_trips() -> void:
	section("a trip crosses several tiles without pausing")
	var corridor := _floored(9, 1)
	var system := CreatureSystem.new(5, false)
	var rat := Creature.new(1, _species(2.0, 0.5, 0.0, 70.0, 4, 4), corridor, Vector2i(0, 0))
	system.get_creatures().append(rat)

	# 41 ticks: one to decide to set off, then 4 steps of 10 ticks each.
	var idled_mid_trip := 0
	for i in 41:
		system.tick(TICK, DAY_HOUR)
		if not rat.is_moving() and i > 0 and i < 40:
			idled_mid_trip += 1
	check("walked 4 tiles in one go", rat.grid_position, Vector2i(4, 0))
	check("never paused mid-trip", idled_mid_trip, 0)
	check_false("resting once the trip ends", rat.is_moving())
	check("trip counter spent", rat.trip_steps_left, 0)

	_run_ticks(system, 60)
	check_true("sets off again after resting", rat.grid_position.x > 4)

	section("prefers not to double back")
	var room := _floored(5, 5)
	var open_system := CreatureSystem.new(9, false)
	var rover := Creature.new(1, _species(0.1, 0.2, 0.0, 70.0, 6, 6), room, Vector2i(2, 2))
	open_system.get_creatures().append(rover)
	var steps := 0
	var reversals := 0
	var previous := rover.grid_position
	var last_direction := Vector2i.ZERO
	for i in 4000:
		open_system.tick(TICK, DAY_HOUR)
		if rover.grid_position != previous:
			steps += 1
			var direction := rover.grid_position - previous
			if last_direction != Vector2i.ZERO and direction == -last_direction:
				reversals += 1
			last_direction = direction
			previous = rover.grid_position
	check_true("keeps walking (>100 steps)", steps > 100)
	check_true("rarely doubles back", float(reversals) / float(steps) < 0.35)


## Creatures sleep through their species' night and stay put.
func _test_sleep() -> void:
	section("sleep window")
	var night := _species(0.2, 0.3, 0.0, 70.0, 4, 4)
	night.sleep_start_hour = 22
	night.wake_hour = 6
	check_true("22:00 asleep (start)", night.is_sleep_hour(22))
	check_true("23:00 asleep", night.is_sleep_hour(23))
	check_true("02:00 asleep (past midnight)", night.is_sleep_hour(2))
	check_false("06:00 awake (wake hour)", night.is_sleep_hour(6))
	check_false("12:00 awake", night.is_sleep_hour(12))
	check_false("21:00 awake", night.is_sleep_hour(21))
	var day_sleeper := _species()
	day_sleeper.sleep_start_hour = 6
	day_sleeper.wake_hour = 22
	check_true("window without wrap: 12:00 asleep", day_sleeper.is_sleep_hour(12))
	check_false("window without wrap: 23:00 awake", day_sleeper.is_sleep_hour(23))
	check_false("equal hours: never sleeps", _species().is_sleep_hour(3))

	section("asleep all night")
	var f := _floored(5, 5)
	var system := CreatureSystem.new(3, false)
	var rat := Creature.new(1, night, f, Vector2i(2, 2))
	system.get_creatures().append(rat)
	var stirred := 0
	for i in 2000:
		system.tick(TICK, NIGHT_HOUR)
		if rat.grid_position != Vector2i(2, 2) or rat.is_moving():
			stirred += 1
	check("never moves through the night", stirred, 0)
	check_true("marked asleep", rat.asleep)
	check("state SLEEP", rat.state, Creature.State.SLEEP)
	check_approx("but still ages", rat.age, 100.0, 1e-6)

	section("wakes at morning")
	var walked := false
	for i in 400:
		system.tick(TICK, 8)
		if rat.grid_position != Vector2i(2, 2):
			walked = true
	check_false("no longer asleep", rat.asleep)
	check_true("walks again once awake", walked)

	section("finishes the step it started when night falls")
	var walker := Creature.new(2, night, f, Vector2i(0, 4))
	system.get_creatures().append(walker)
	var guard := 0
	while not walker.is_moving() and guard < 500:
		system.tick(TICK, DAY_HOUR)
		guard += 1
	check_true("got it walking", walker.is_moving())
	var destination := walker.move_target
	_run_ticks(system, 200, NIGHT_HOUR)
	check("finished the step onto a whole tile", walker.grid_position, destination)
	check_false("then stopped", walker.is_moving())
	check_true("asleep", walker.asleep)


## Hunger reaching the limit kills the creature.
func _test_starvation() -> void:
	section("starving to death")
	var f := _floored(5, 5)
	var system := CreatureSystem.new(4, false)
	var rat := Creature.new(1, _species(1.0, 0.5, 10.0, 70.0), f, Vector2i(2, 2))
	system.get_creatures().append(rat)
	var died: Array[Creature] = []
	system.creature_died.connect(func(c: Creature) -> void: died.append(c))

	_run_ticks(system, 139)
	check_true("alive at 69.5 hunger", rat.alive)
	check_false("not hungry yet", rat.is_hungry())
	_run_ticks(system, 1)
	check("HUNGRY at 70", rat.state, Creature.State.HUNGRY)
	_run_ticks(system, 59)
	check_approx("99.5 hunger", rat.hunger, 99.5, 1e-6)
	check_true("still alive just under the limit", rat.alive)

	_run_ticks(system, 1)
	check_false("dead at 100 hunger", rat.alive)
	check("state DEAD", rat.state, Creature.State.DEAD)
	check("hunger pinned at the limit", rat.hunger, 100.0)
	check("health drops to 0", rat.health, 0.0)
	check_false("not left asleep", rat.asleep)
	check("removed from the system", system.get_creature_count(), 0)
	check("creature_died fired once", died.size(), 1)
	check("for that rodent", died[0].id, 1)

	var resting_place := rat.grid_position
	var final_age := rat.age
	_run_ticks(system, 400)
	check("a dead creature stops ageing", rat.age, final_age)
	check("and stays where it fell", rat.grid_position, resting_place)
	check_false("cannot be told to move", system.try_move(rat, resting_place + Vector2i.RIGHT))

	section("the others live on")
	var pair_system := CreatureSystem.new(6, false)
	var doomed := Creature.new(1, _species(1.0, 0.5, 10.0), f, Vector2i(0, 0))
	var survivor := Creature.new(2, _species(1.0, 0.5, 0.0), f, Vector2i(4, 4))
	pair_system.get_creatures().append(doomed)
	pair_system.get_creatures().append(survivor)
	_run_ticks(pair_system, 250)
	check("only the starving one died", pair_system.get_creature_count(), 1)
	check("the survivor remains", pair_system.get_creatures()[0].id, 2)
	check_true("and is still alive", survivor.alive)
	check_approx("unharmed by its neighbour dying", survivor.hunger, 0.0, 1e-6)


func _test_movement_rules() -> void:
	var f := _ragged_floor()
	var system := CreatureSystem.new(1, false)
	var s := _species()

	section("5 invalid tiles")
	var corner := Creature.new(90, s, f, Vector2i(0, 0))
	system.get_creatures().append(corner)
	check_false("out of bounds (-1,0)", system.can_move_to(corner, Vector2i(-1, 0)))
	check_false("out of bounds (0,-1)", system.can_move_to(corner, Vector2i(0, -1)))
	var edge := Creature.new(91, s, f, Vector2i(7, 1))
	system.get_creatures().append(edge)
	check_false("sparse hole (8,1) inside bounds", system.can_move_to(edge, Vector2i(8, 1)))
	var bought := Creature.new(92, s, f, Vector2i(8, 2))
	system.get_creatures().append(bought)
	check_false("from bought tile into hole (8,3)", system.can_move_to(bought, Vector2i(8, 3)))
	check_true("but can walk back onto the floor", system.can_move_to(bought, Vector2i(7, 2)))

	section("6 no diagonals, no jumps")
	check_false("system rejects diagonal", system.can_move_to(corner, Vector2i(1, 1)))
	check_false("system rejects 2-tile jump", system.can_move_to(corner, Vector2i(2, 0)))
	check_false("system rejects staying put", system.can_move_to(corner, Vector2i(0, 0)))
	check_false("model rejects diagonal too", corner.start_move(Vector2i(1, 1)))
	check_false("model rejects jump too", corner.start_move(Vector2i(0, 3)))
	check_false("still not moving", corner.is_moving())

	section("7 non-walkable")
	var near_block := Creature.new(93, s, f, Vector2i(1, 0))
	system.get_creatures().append(near_block)
	check_false("no floor at (1,1)", system.can_move_to(near_block, Vector2i(1, 1)))

	section("8 valid step")
	check_true("try_move (0,0)->(0,1)", system.try_move(corner, Vector2i(0, 1)))
	check_true("is moving", corner.is_moving())
	check("state WANDER while stepping", corner.state, Creature.State.WANDER)
	check("facing down", corner.facing, Vector2i.DOWN)
	check_false("cannot start a second step mid-step", system.try_move(corner, Vector2i(1, 0)))
	for i in 10:
		corner.advance(TICK, DAY_HOUR)
	check("arrived after exactly 0.5 s", corner.grid_position, Vector2i(0, 1))
	check_false("stopped", corner.is_moving())

	section("occupancy")
	var a := Creature.new(94, s, f, Vector2i(5, 0))
	var b := Creature.new(95, s, f, Vector2i(6, 0))
	system.get_creatures().append(a)
	system.get_creatures().append(b)
	check_false("cannot step onto another creature", system.can_move_to(a, Vector2i(6, 0)))
	check_true("b steps away to (6,1)", system.try_move(b, Vector2i(6, 1)))
	check_false("cannot step onto a tile being left", system.can_move_to(a, Vector2i(6, 0)))
	var c := Creature.new(96, s, f, Vector2i(5, 1))
	system.get_creatures().append(c)
	check_false("cannot step onto a tile being entered", system.can_move_to(c, Vector2i(6, 1)))

	section("boxed in")
	var box := _floored(3, 3)
	box.remove_floor(Vector2i(1, 0))
	box.remove_floor(Vector2i(0, 1))
	var boxed := CreatureSystem.new(1, false)
	var trapped := Creature.new(1, _species(0.2), box, Vector2i(0, 0))
	boxed.get_creatures().append(trapped)
	_run_ticks(boxed, 400)
	check("no legal step: stays idle in place", trapped.grid_position, Vector2i(0, 0))
	check_false("never started moving", trapped.is_moving())


func _test_timing_through_simulation() -> void:
	section("9 steps advance with simulation ticks")
	var f := _floored()
	var system := CreatureSystem.new(3, true)
	var rat: Creature = system.spawn(_species(1.0, 0.5), f, 1)[0]
	var start := rat.grid_position

	SimulationManager.step(19)
	check_false("still resting at 0.95 s", rat.is_moving())
	SimulationManager.step(1)
	check_true("sets off exactly at 1.0 s", rat.is_moving())
	var target := rat.move_target
	SimulationManager.step(5)
	check_approx("halfway after 0.25 s of a 0.5 s step", rat.move_progress, 0.5, 1e-6)
	check("has not arrived yet", rat.grid_position, start)
	SimulationManager.step(5)
	check("arrives after exactly 0.5 s", rat.grid_position, target)
	check_false("stopped", rat.is_moving())
	check_true("moved one orthogonal tile", Creature.STEP_DIRECTIONS.has(target - start))
	SimulationManager.step(19)
	check_false("rests again before the next step", rat.is_moving())
	SimulationManager.step(1)
	check_true("and sets off again after 1.0 s", rat.is_moving())


func _test_pause_and_speed() -> void:
	var f := _floored()
	var system := CreatureSystem.new(5, true)
	var rats := system.spawn(_species(0.1, 0.3), f, 3)

	section("10 pause stops creatures")
	SimulationManager.set_speed(1.0)
	SimulationManager.resume()
	await real_seconds(0.5)
	SimulationManager.pause()
	var snapshot := _snapshot(rats)
	await real_seconds(0.6)
	check("nothing changed while paused", _snapshot(rats), snapshot)
	check_true("but they had been living", rats[0].age > 0.0)

	section("11 simulation speed drives creature time")
	var age_1x := await _age_gained(rats[0], 1.0, 1.0)
	var age_10x := await _age_gained(rats[0], 10.0, 1.0)
	check_between("~1 creature-second per real second at 1x", age_1x, 0.9, 1.1)
	check_between("~10 creature-seconds per real second at 10x", age_10x, 9.2, 10.8)
	check_between("10x runs ~10 times faster", age_10x / age_1x, 8.5, 11.5)
	SimulationManager.set_speed(1.0)


func _age_gained(rat: Creature, speed: float, seconds: float) -> float:
	SimulationManager.set_speed(speed)
	SimulationManager.resume()
	await frames(2)
	var before := rat.age
	var start := Time.get_ticks_usec()
	await real_seconds(seconds)
	SimulationManager.pause()
	return (rat.age - before) / elapsed_since(start)


func _snapshot(rats: Array[Creature]) -> Array:
	var out := []
	for r in rats:
		out.append([r.grid_position, r.move_target, r.move_progress, r.age, r.hunger, r.state])
	return out


func _test_age_and_hunger() -> void:
	var f := _floored()
	var system := CreatureSystem.new(1, false)

	section("12 age")
	var rat: Creature = system.spawn(_species(1.0, 0.5, 1.0), f, 1)[0]
	_run_ticks(system, 200)
	check_approx("200 ticks = 10 s old", rat.age, 10.0, 1e-6)

	section("13 hunger")
	check_approx("rate 1/s: +10 in 10 s", rat.hunger, 10.0, 1e-6)
	var real_rat := Creature.new(50, RODENT, f, Vector2i(0, 0), 0.0)
	for i in 400:
		real_rat.advance(TICK, DAY_HOUR)
	check_approx("Maniac Sewer Rat: 0.04/s -> 0.8 in 20 s", real_rat.hunger, 0.8, 1e-6)

	section("14 HUNGRY at threshold")
	var hungry := Creature.new(51, _species(1.0, 0.5, 10.0, 70.0), f, Vector2i(3, 3), 0.0)
	for i in 139:
		hungry.advance(TICK, DAY_HOUR)
	check_false("69.5 hunger: not hungry", hungry.is_hungry())
	check_true("state not HUNGRY", hungry.state != Creature.State.HUNGRY)
	hungry.advance(TICK, DAY_HOUR)
	check_approx("hunger 70", hungry.hunger, 70.0, 1e-6)
	check("state HUNGRY at >= 70", hungry.state, Creature.State.HUNGRY)
	check_true("still alive at the threshold", hungry.alive)

	section("hungry creatures keep wandering")
	var wanderer_system := CreatureSystem.new(4, false)
	var starving: Creature = wanderer_system.spawn(_species(0.2, 0.3, 1.0, 5.0), f, 1)[0]
	_run_ticks(wanderer_system, 120)
	check("already HUNGRY", starving.state, Creature.State.HUNGRY)
	var from := starving.grid_position
	var moved := false
	for i in 400:
		wanderer_system.tick(TICK, DAY_HOUR)
		if starving.grid_position != from:
			moved = true
	check_true("still moves around while hungry", moved)


func _test_independence() -> void:
	section("15 creatures are independent")
	var f := _floored()
	var system := CreatureSystem.new(11, false)
	var rats := system.spawn(RODENT, f, 3)
	check_true("distinct objects", rats[0] != rats[1] and rats[1] != rats[2])
	check_true("individual starting hunger",
		rats[0].hunger != rats[1].hunger or rats[1].hunger != rats[2].hunger)
	var others_before := [rats[1].grid_position, rats[2].grid_position]
	for direction in Creature.STEP_DIRECTIONS:
		if system.try_move(rats[0], rats[0].grid_position + direction):
			break
	check_true("rat #1 set off", rats[0].is_moving())
	check("rats #2 and #3 untouched", [rats[1].grid_position, rats[2].grid_position], others_before)
	check_false("#2 not dragged into moving", rats[1].is_moving())
	var traces := [{}, {}, {}]
	for i in 2000:
		system.tick(TICK, DAY_HOUR)
		for n in 3:
			traces[n][rats[n].grid_position] = true
	check_true("each wandered its own path",
		traces[0].size() > 1 and traces[1].size() > 1 and traces[2].size() > 1)
	check_true("paths differ", traces[0].keys() != traces[1].keys())


## The core claim: however long they live, rodents only ever stand on walkable
## tiles of their own floor, one step at a time, never sharing a tile.
func _test_invariants_over_long_run() -> void:
	section("invariants over 20,000 ticks on a ragged floor")
	var f := _ragged_floor()
	var system := CreatureSystem.new(2024, false)
	# Hunger off, so this isolates movement: a creature dying mid-run would be
	# removed from the system while this test still tracked its tile.
	var rats := system.spawn(_species(2.0, 1.0, 0.0, 70.0, 3, 8), f, 6)
	var illegal_tile := 0
	var illegal_step := 0
	var shared_tile := 0
	var steps := 0
	var visited := {}
	var previous: Array[Vector2i] = []
	for r in rats:
		previous.append(r.grid_position)

	for t in 20000:
		system.tick(TICK, DAY_HOUR)
		var claimed := {}
		for n in rats.size():
			var r: Creature = rats[n]
			if not f.is_walkable(r.grid_position) or not f.is_walkable(r.move_target):
				illegal_tile += 1
			if r.grid_position != previous[n]:
				steps += 1
				if not Creature.STEP_DIRECTIONS.has(r.grid_position - previous[n]):
					illegal_step += 1
				previous[n] = r.grid_position
			for tile in [r.grid_position, r.move_target]:
				if claimed.has(tile) and claimed[tile] != n:
					shared_tile += 1
				claimed[tile] = n
			visited[r.grid_position] = true

	check("never on a missing or floorless tile", illegal_tile, 0)
	check("never a diagonal or multi-tile step", illegal_step, 0)
	check("never two on one tile", shared_tile, 0)
	check_true("they actually wander (>300 steps)", steps > 300)
	check_false("never entered floorless (1,1)", visited.has(Vector2i(1, 1)))
	check_false("never entered floorless (3,3)", visited.has(Vector2i(3, 3)))
	check_true("reached a bought tile at the ragged edge",
		visited.has(Vector2i(-1, 2)) or visited.has(Vector2i(8, 2)))


## Dungeon's queries answer for the VIEWED floor. Creatures must ignore that and
## obey their own floor, or switching floors would reshape their world.
func _test_own_floor_not_viewed_floor() -> void:
	section("13 floors: creatures obey their own floor, not the viewed one")
	var dungeon := Dungeon.new()
	dungeon.create_floor()
	var floor_1 := dungeon.get_floor(0)
	var floor_2 := dungeon.get_floor(1)
	for y in 5:
		floor_2.add_tile(Vector2i(8, y))
		floor_2.add_tile(Vector2i(-1, y))
	_with_floor(floor_1)
	_with_floor(floor_2)

	var system := CreatureSystem.new(99, false)
	var roamer := _species(2.0, 1.0, 0.0, 70.0, 3, 8)
	var upstairs := system.spawn(roamer, floor_1, 4)
	var downstairs := system.spawn(roamer, floor_2, 2)
	check("4 on floor 1", system.get_creatures_on(floor_1).size(), 4)
	check("2 on floor 2", system.get_creatures_on(floor_2).size(), 2)

	dungeon.set_current_floor(1)
	check_true("viewed floor now has (8,0)", dungeon.is_valid_position(Vector2i(8, 0)))

	var strayed := 0
	var ages_before := upstairs.map(func(r): return r.age)
	for t in 20000:
		system.tick(TICK, DAY_HOUR)
		for r in upstairs:
			if not floor_1.is_walkable(r.grid_position) or not floor_1.is_walkable(r.move_target):
				strayed += 1
	check("floor-1 rats never used floor 2's extra tiles", strayed, 0)
	check_true("floor-1 rats kept living while floor 2 was viewed",
		upstairs[0].age > ages_before[0] + 900.0)
	var floor_2_visits := {}
	for t in 5000:
		system.tick(TICK, DAY_HOUR)
		for r in downstairs:
			floor_2_visits[r.grid_position] = true
	var used_extra := false
	for position in floor_2_visits:
		if position.x == 8 or position.x == -1:
			used_extra = true
	check_true("floor-2 rats DO use floor 2's extra tiles", used_extra)
	var changed_floor := 0
	for r in upstairs:
		if r.dungeon_floor != floor_1:
			changed_floor += 1
	for r in downstairs:
		if r.dungeon_floor != floor_2:
			changed_floor += 1
	check("no creature changed floor", changed_floor, 0)


func _test_view() -> void:
	section("sprites")
	var f := _floored()
	var rat := Creature.new(7, RODENT, f, Vector2i(3, 2))
	var view: CreatureView = VIEW_SCENE.instantiate()
	tree.root.add_child(view)
	view.bind(rat)
	var sprite: Sprite2D = view.get_node("Sprite2D")

	check("snaps to tile centre", view.position, Vector2(3 * 32 + 16, 2 * 32 + 16))
	var scale_side := sprite.scale

	rat.facing = Vector2i.LEFT
	view.sync(0.0, true)
	check("west: side sprite", sprite.texture, RODENT.side_texture)
	check_false("west: art already faces left, not flipped", sprite.flip_h)

	rat.facing = Vector2i.RIGHT
	view.sync(0.0, true)
	check("east: side sprite", sprite.texture, RODENT.side_texture)
	check_true("east: flipped", sprite.flip_h)

	rat.facing = Vector2i.DOWN
	view.sync(0.0, true)
	check("south: front sprite", sprite.texture, RODENT.front_texture)
	check_false("south: not flipped", sprite.flip_h)
	check("same scale when turning", sprite.scale, scale_side)

	rat.facing = Vector2i.UP
	view.sync(0.0, true)
	check("north: side sprite (no back sprite yet)", sprite.texture, RODENT.side_texture)
	check_true("north: keeps last horizontal facing (east)", sprite.flip_h)

	var label: Label = view.get_node("Label")
	check_true("label names the rodent", label.text.begins_with("Rodent #7"))
	check_true("label shows state", label.text.contains("IDLE"))

	section("view follows the model")
	rat.facing = Vector2i.RIGHT
	rat.start_move(Vector2i(4, 2))
	rat.move_progress = 0.5
	view.sync(0.0, true)
	check("drawn halfway across the step", view.position, Vector2(3.5 * 32 + 16, 2 * 32 + 16))
	view.queue_free()
	await frames(1)


func _test_layer() -> void:
	section("layer shows only the viewed floor")
	var dungeon := Dungeon.new()
	dungeon.create_floor()
	var system := CreatureSystem.new(8, false)
	var layer := CreatureLayer.new()
	tree.root.add_child(layer)
	layer.current_floor = dungeon.get_floor(0)
	layer.system = system
	var on_1 := system.spawn(RODENT, dungeon.get_floor(0), 3)
	var on_2 := system.spawn(RODENT, dungeon.get_floor(1), 2)

	check("a view per creature", layer.get_child_count(), 5)
	check("floor 1 views visible", on_1.filter(func(r): return layer.get_view(r).visible).size(), 3)
	check("floor 2 views hidden", on_2.filter(func(r): return layer.get_view(r).visible).size(), 0)
	layer.current_floor = dungeon.get_floor(1)
	check("after switch: floor 1 hidden", on_1.filter(func(r): return layer.get_view(r).visible).size(), 0)
	check("after switch: floor 2 visible", on_2.filter(func(r): return layer.get_view(r).visible).size(), 2)
	layer.labels_visible = false
	check_false("labels toggle off", layer.get_view(on_2[0]).get_node("Label").visible)

	section("a dead creature's view is taken away")
	var doomed: Creature = on_2[0]
	# The rodent's hunger climbs 0.002 per tick, so nudge it to the brink first.
	doomed.hunger = Creature.MAX_HUNGER - 0.01
	_run_ticks(system, 10)
	check_false("it starved", doomed.alive)
	check("gone from the system", system.get_creatures().has(doomed), false)
	check("layer forgot it", layer.get_view(doomed) == null, true)
	await frames(2)
	check("its view is freed", layer.get_child_count(), 4)
	check("the others keep theirs", layer.get_view(on_1[0]) != null, true)
	layer.queue_free()
	await frames(1)


func _test_main_scene() -> void:
	section("main scene: starts with no rodents")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)
	var system: CreatureSystem = main._creatures
	var layer: CreatureLayer = main.get_node("CreatureLayer")
	var dungeon: Dungeon = main._dungeon
	check("no rodents at startup", system.get_creature_count(), 0)
	check("no views drawn", layer.get_child_count(), 0)
	check("dungeon starts with no floor placed", dungeon.get_floor_tile_count(), 0)
	SimulationManager.step(200)
	check("still none after 10 s", system.get_creature_count(), 0)

	section("main scene: place floor, spawn with S, it lives")
	_advance_to_daytime()
	check_between("clock is daytime", float(GameTime.get_hour()), 9.0, 18.0)
	for position in dungeon.get_positions():
		dungeon.place_floor(position)
	main._spawn_rodent_here()
	check("S spawns one rodent", system.get_creature_count(), 1)
	var rat: Creature = system.get_creatures()[0]
	check("a Maniac Sewer Rat", rat.get_variant_name(), "Maniac Sewer Rat")
	check("on the current floor", rat.dungeon_floor, dungeon.get_current_floor())
	check_true("standing on floor", dungeon.is_walkable(rat.grid_position))
	check("one view drawn", layer.get_child_count(), 1)
	check_true("and visible", layer.get_view(rat).visible)
	main._spawn_rodent_here()
	main._spawn_rodent_here()
	check("S again: 3 rodents", system.get_creature_count(), 3)

	var rats := system.get_creatures()
	var starts := rats.map(func(r): return r.grid_position)
	var age_before: float = rats[0].age
	var stepped := {}
	for i in 400:
		SimulationManager.step(1)
		for n in rats.size():
			if rats[n].grid_position != starts[n]:
				stepped[n] = true
	check_approx("they tick with the simulation", rats[0].age - age_before, 20.0, 1e-6)
	check("all 3 walk on the placed floor", stepped.size(), 3)
	main.queue_free()
	await frames(2)
