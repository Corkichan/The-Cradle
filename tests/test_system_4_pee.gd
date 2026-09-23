extends "res://tests/test_suite.gd"

const RODENT: CreatureSpecies = preload("res://assets/creatures/rodent/maniac_sewer_rat.tres")
const TICK: float = 0.05
const DAY_HOUR: int = 12


func _init() -> void:
	title = "System 4 - Rodent Pee"


func run() -> void:
	_test_tile_data()
	_test_interval()
	_test_urinates_on_its_tile()
	_test_accumulates()
	_test_independent_creatures()
	_test_does_not_interrupt()
	_test_visual()
	await _test_pause_and_speed()
	_test_main_scene()


# --------------------------------------------------------------------------

## Stands still (no trips), never sleeps, never hungry, so only urination moves.
##
## [param interval] is still the seconds between puddles, but it is now produced
## by the water model: hydration is spent at 1 per second and the bladder holds
## [param interval] of it, so one puddle falls every [param interval] seconds
## for as long as the creature has water in it.
func _species(interval := 10.0, amount := 1.0) -> CreatureSpecies:
	var s := CreatureSpecies.new()
	s.species_name = "Rodent"
	s.variant_name = "Test Rat"
	s.idle_time_min = 1000.0
	s.idle_time_max = 1000.0
	s.move_duration = 0.5
	s.hunger_rate = 0.0
	s.hungry_threshold = 70.0
	s.sated_threshold = 30.0
	s.initial_hunger_max = 0.0
	s.trip_steps_min = 1
	s.trip_steps_max = 1
	s.sleep_start_hour = 0
	s.wake_hour = 0
	s.hydration_rate = 1.0
	s.bladder_capacity = interval
	s.urination_amount = amount
	s.side_texture = RODENT.side_texture
	s.front_texture = RODENT.front_texture
	return s


func _floored(width := 8, height := 5) -> DungeonFloor:
	var f := DungeonFloor.new(width, height)
	for position in f.get_positions():
		f.place_floor(position)
	return f


func _run_ticks(system: CreatureSystem, count: int) -> void:
	for i in count:
		system.tick(TICK, DAY_HOUR)


## Steps the shared clock into the middle of the day. The main-scene test uses
## the real rodent, which sleeps at night and then leaves nothing — without this
## the test would pass or fail depending on what time the clock happened to be at.
func _advance_to_daytime() -> void:
	var guard := 0
	while (GameTime.get_hour() < 9 or GameTime.get_hour() > 18) and guard < 2000:
		SimulationManager.step(25)
		guard += 1


func _place(system: CreatureSystem, species: CreatureSpecies, f: DungeonFloor,
		position: Vector2i, id := 1) -> Creature:
	var creature := Creature.new(id, species, f, position, 0.0)
	# spawn() rests new creatures; without it the idle timer starts at zero and
	# the creature takes a step on the very first tick, so a test watching one
	# tile would be watching the wrong one.
	creature.rest(species.idle_time_min)
	system.get_creatures().append(creature)
	return creature


# --------------------------------------------------------------------------

func _test_tile_data() -> void:
	section("4 pee lives on the tile")
	var f := _floored()
	var tile := f.get_tile(Vector2i(2, 2))
	check("a tile starts clean", tile.pee_amount, 0.0)
	check_false("and has no pee", tile.has_pee())

	check_true("add_pee reports success", f.add_pee(Vector2i(2, 2), 1.0))
	check("the tile holds it", tile.pee_amount, 1.0)
	check_true("has_pee", tile.has_pee())
	check("neighbours stay clean", f.get_tile(Vector2i(3, 2)).pee_amount, 0.0)
	check_false("no tile there, nothing to wet", f.add_pee(Vector2i(99, 99), 1.0))
	check("never goes negative", _negative_pee(f), 0.0)
	check("the floor lists wet tiles", f.get_peed_positions(), [Vector2i(2, 2)])


func _negative_pee(f: DungeonFloor) -> float:
	f.add_pee(Vector2i(2, 2), -100.0)
	var amount: float = f.get_tile(Vector2i(2, 2)).pee_amount
	f.add_pee(Vector2i(2, 2), 1.0)
	return amount


func _test_interval() -> void:
	section("1 the cadence comes from the water model, not a clock")
	check("rodent hydration rate", RODENT.hydration_rate, 0.1)
	check("rodent bladder capacity", RODENT.bladder_capacity, 4.0)
	check("rodent urination amount", RODENT.urination_amount, 1.0)
	check_approx("so a watered rodent goes every 40 s",
		RODENT.bladder_capacity / RODENT.hydration_rate, 40.0, 1e-6)
	var custom := _species(7.5, 3.0)
	check("configurable capacity", custom.bladder_capacity, 7.5)
	check("configurable amount", custom.urination_amount, 3.0)


func _test_urinates_on_its_tile() -> void:
	section("2-3 driven by simulation time")
	var f := _floored()
	var system := CreatureSystem.new(1, false)
	var rat := _place(system, _species(10.0, 1.0), f, Vector2i(4, 2))
	var tile := f.get_tile(Vector2i(4, 2))

	_run_ticks(system, 199)
	check("dry at 9.95 s", tile.pee_amount, 0.0)
	_run_ticks(system, 1)
	check("urinates at exactly 10 s", tile.pee_amount, 1.0)
	_run_ticks(system, 199)
	check("and not again until the interval is up", tile.pee_amount, 1.0)
	_run_ticks(system, 1)
	check("second go at 20 s", tile.pee_amount, 2.0)

	section("it goes on the tile it stands on")
	var walker_floor := _floored()
	var walker_system := CreatureSystem.new(2, false)
	var mover := _species(10.0, 1.0)
	mover.idle_time_min = 0.1
	mover.idle_time_max = 0.1
	mover.trip_steps_min = 8
	mover.trip_steps_max = 8
	var wanderer := _place(walker_system, mover, walker_floor, Vector2i(0, 0))
	var wet_where: Array[Vector2i] = []
	for i in 600:
		var before := walker_floor.get_peed_positions().size()
		walker_system.tick(TICK, DAY_HOUR)
		if walker_floor.get_peed_positions().size() == before:
			continue
		for position in walker_floor.get_peed_positions():
			if not wet_where.has(position):
				wet_where.append(position)
				# The tile it occupies once the tick is done, which is where it
				# was standing at the moment it went.
				check("wet tile %s is where it stands" % position,
					position, wanderer.grid_position)
	check_true("a wandering rodent wets more than one tile", wet_where.size() > 1)


func _test_accumulates() -> void:
	section("5 repeated visits accumulate on one tile")
	var f := _floored()
	var system := CreatureSystem.new(3, false)
	_place(system, _species(10.0, 2.5), f, Vector2i(1, 1))
	_run_ticks(system, 200 * 4)
	var tile := f.get_tile(Vector2i(1, 1))
	check("4 goes of 2.5", tile.pee_amount, 10.0)
	check("still a single tile", f.get_peed_positions().size(), 1)


func _test_independent_creatures() -> void:
	section("6 several rodents leave their own traces")
	var f := _floored()
	var system := CreatureSystem.new(4, false)
	_place(system, _species(10.0, 1.0), f, Vector2i(0, 0), 1)
	_place(system, _species(10.0, 1.0), f, Vector2i(7, 4), 2)
	_run_ticks(system, 200)
	check("both tiles wet", f.get_peed_positions().size(), 2)
	check("corner one", f.get_tile(Vector2i(0, 0)).pee_amount, 1.0)
	check("far corner", f.get_tile(Vector2i(7, 4)).pee_amount, 1.0)
	check("nothing in between", f.get_tile(Vector2i(4, 2)).pee_amount, 0.0)

	section("two rodents on one tile would stack on the same tile")
	var shared := _floored()
	var shared_system := CreatureSystem.new(5, false)
	# Placed directly, so this is the one case where they share a tile.
	_place(shared_system, _species(10.0, 1.0), shared, Vector2i(2, 2), 1)
	_place(shared_system, _species(10.0, 1.0), shared, Vector2i(2, 2), 2)
	_run_ticks(shared_system, 200)
	check("both contributions on one tile", shared.get_tile(Vector2i(2, 2)).pee_amount, 2.0)
	check("one wet tile", shared.get_peed_positions().size(), 1)


func _test_does_not_interrupt() -> void:
	section("urinating interrupts nothing")
	var f := _floored()
	var system := CreatureSystem.new(6, false)
	var busy := _species(1.0, 1.0)
	busy.idle_time_min = 0.1
	busy.idle_time_max = 0.1
	busy.move_duration = 0.5
	busy.trip_steps_min = 20
	busy.trip_steps_max = 20
	var rat := _place(system, busy, f, Vector2i(0, 2))
	var moving_ticks := 0
	for i in 400:
		system.tick(TICK, DAY_HOUR)
		if rat.is_moving():
			moving_ticks += 1
	check_true("it kept walking while wetting the floor", moving_ticks > 300)
	check_true("and left several puddles", f.get_peed_positions().size() > 2)

	section("a sleeping rodent does not go at all")
	var sleep_floor := _floored()
	var sleep_system := CreatureSystem.new(7, false)
	var sleeper_species := _species(5.0, 1.0)
	sleeper_species.sleep_start_hour = 22
	sleeper_species.wake_hour = 6
	var sleeper := _place(sleep_system, sleeper_species, sleep_floor, Vector2i(3, 3))
	var sleep_tile := sleep_floor.get_tile(Vector2i(3, 3))

	# Awake for 3 of its 5 seconds.
	for i in 60:
		sleep_system.tick(TICK, DAY_HOUR)
	check("dry so far", sleep_tile.pee_amount, 0.0)

	# A long night, far longer than the interval.
	for i in 600:
		sleep_system.tick(TICK, 23)
	check_true("still asleep", sleeper.asleep)
	check("never moved", sleeper.grid_position, Vector2i(3, 3))
	check("a sleeping rodent leaves nothing", sleep_tile.pee_amount, 0.0)
	check_false("and is never due while asleep", sleeper.is_urination_due())

	# The body kept working through the night, so it wakes needing to go, but
	# the bladder is capped: one puddle owed, not one per hour of sleep.
	check_approx("bladder filled to capacity, no further", sleeper.bladder,
		sleeper_species.bladder_capacity, 1e-6)
	sleep_system.tick(TICK, DAY_HOUR)
	check("goes on its first waking tick", sleep_tile.pee_amount, 1.0)
	# Two seconds, well inside its five second bladder: a burst would show here.
	for i in 40:
		sleep_system.tick(TICK, DAY_HOUR)
	check("and only once: no burst of held-up puddles", sleep_tile.pee_amount, 1.0)

	section("the model refuses even with a full bladder")
	sleeper.bladder = sleeper_species.bladder_capacity
	sleep_system.tick(TICK, 23)
	check_true("asleep again", sleeper.asleep)
	check_false("still not due", sleeper.is_urination_due())
	check("and nothing was added", sleep_tile.pee_amount, 1.0)

	section("the dead stop going")
	var dead_floor := _floored()
	var dead_system := CreatureSystem.new(8, false)
	var doomed := _place(dead_system, _species(5.0, 1.0), dead_floor, Vector2i(1, 1))
	doomed.hunger = Creature.MAX_HUNGER
	_run_ticks(dead_system, 400)
	check_false("it starved", doomed.alive)
	check("no puddle from a corpse", dead_floor.get_tile(Vector2i(1, 1)).pee_amount, 0.0)
	# The system already skips the dead, so that check alone passes even if the
	# model forgets. Ask the model directly, the way movement is asked.
	doomed.reset_urination(0.0)
	check_false("and the model itself says it is never due", doomed.is_urination_due())


func _test_visual() -> void:
	section("7-8 one sprite per tile, however many visits")
	var f := _floored()
	var layer := PeeLayer.new()
	tree.root.add_child(layer)
	layer.current_floor = f
	check("nothing drawn on a clean floor", layer.get_sprite_count(), 0)

	f.add_pee(Vector2i(2, 2), 1.0)
	check("a puddle appears", layer.get_sprite_count(), 1)
	var sprite := layer.get_sprite(Vector2i(2, 2))
	check_true("with the pee texture", sprite != null and sprite.texture != null)
	check("centred on its tile", sprite.position,
		Vector2(2 * 32 + 16, 2 * 32 + 16))
	var faint := sprite.modulate.a

	for i in 20:
		f.add_pee(Vector2i(2, 2), 1.0)
	check("20 more goes, still ONE sprite", layer.get_sprite_count(), 1)
	check("the same node, reused", layer.get_sprite(Vector2i(2, 2)), sprite)
	check_true("it just got stronger", sprite.modulate.a > faint)
	check("children match sprites", layer.get_child_count(), 1)

	f.add_pee(Vector2i(5, 1), 1.0)
	check("a different tile gets its own", layer.get_sprite_count(), 2)

	section("switching floor redraws from that floor's tiles")
	var other := _floored()
	other.add_pee(Vector2i(0, 0), 1.0)
	other.add_pee(Vector2i(1, 0), 1.0)
	other.add_pee(Vector2i(2, 0), 1.0)
	layer.current_floor = other
	await frames(2)
	check("shows the other floor's 3 puddles", layer.get_sprite_count(), 3)
	check("and none of the first floor's", layer.get_sprite(Vector2i(2, 2)) == null, true)
	layer.current_floor = f
	await frames(2)
	check("back to the first floor's 2", layer.get_sprite_count(), 2)
	f.add_pee(Vector2i(6, 4), 1.0)
	check("still listening after the switch", layer.get_sprite_count(), 3)
	layer.queue_free()
	await frames(1)


func _test_pause_and_speed() -> void:
	section("9-10 pause and speed")
	var f := _floored()
	var system := CreatureSystem.new(9, true)
	var tile := f.get_tile(Vector2i(4, 2))
	_place(system, _species(0.2, 1.0), f, Vector2i(4, 2))

	SimulationManager.set_speed(1.0)
	SimulationManager.resume()
	await real_seconds(0.8)
	SimulationManager.pause()
	var frozen := tile.pee_amount
	check_true("it had been going", frozen > 0.0)
	await real_seconds(0.6)
	check("paused: not a drop more", tile.pee_amount, frozen)

	var rate_1x := await _pee_per_real_second(tile, 1.0, 0.8)
	var rate_10x := await _pee_per_real_second(tile, 10.0, 0.8)
	check_true("it goes at 1x (%.1f/s)" % rate_1x, rate_1x > 0.0)
	check_between("10x is about ten times as fast (%.1f vs %.1f)" % [rate_10x, rate_1x],
		rate_10x / rate_1x, 7.0, 13.0)
	SimulationManager.set_speed(1.0)


func _pee_per_real_second(tile: DungeonTile, speed: float, seconds: float) -> float:
	SimulationManager.set_speed(speed)
	SimulationManager.resume()
	await frames(2)
	var before := tile.pee_amount
	var start := Time.get_ticks_usec()
	await real_seconds(seconds)
	SimulationManager.pause()
	return (tile.pee_amount - before) / elapsed_since(start)


func _test_main_scene() -> void:
	section("the real scene wires the pee layer in")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	_advance_to_daytime()
	check_between("clock is daytime", float(GameTime.get_hour()), 9.0, 18.0)
	var dungeon: Dungeon = main._dungeon
	var layer: PeeLayer = main.get_node("PeeLayer")
	check("layer watches the starting floor", layer.current_floor, dungeon.get_current_floor())
	check("nothing wet yet", layer.get_sprite_count(), 0)

	for position in dungeon.get_positions():
		dungeon.place_floor(position)
	main._spawn_rodent_here()
	var rat: Creature = main._creatures.get_creatures()[0]
	var interval: float = rat.species.bladder_capacity / rat.species.hydration_rate
	# Enough simulated time for two goes whatever the staggered start was.
	SimulationManager.step(int(interval * 2.0 / SimulationManager.TICK_DELTA) + 20)
	var wet := dungeon.get_current_floor().get_peed_positions()
	check_true("the rodent left a trace", wet.size() > 0)
	check("a sprite for each wet tile", layer.get_sprite_count(), wet.size())
	var total := 0.0
	for position in wet:
		total += dungeon.get_tile(position).pee_amount
	check_true("of at least two goes", total >= 2.0 * rat.species.urination_amount)
	main.queue_free()
	await frames(2)
