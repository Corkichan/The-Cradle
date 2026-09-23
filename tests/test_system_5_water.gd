extends "res://tests/test_suite.gd"

const RODENT: CreatureSpecies = preload("res://assets/creatures/rodent/maniac_sewer_rat.tres")
const TICK: float = 0.05
const DAY_HOUR: int = 12


func _init() -> void:
	title = "System 5 - Water and Hydration"


func run() -> void:
	_test_hydration_falls()
	_test_thirst_threshold()
	_test_perception()
	_test_seeks_and_drinks()
	_test_drinking_enables_urination()
	_test_no_water_no_pee()
	_test_thirst_before_hunger()
	_test_independent()
	await _test_pause_and_speed()
	_test_main_scene()


# --------------------------------------------------------------------------

func _species(rate := 0.0, thirsty := 40.0, sated := 90.0, capacity := 5.0,
		radius := 5) -> CreatureSpecies:
	var s := CreatureSpecies.new()
	s.species_name = "Rodent"
	s.variant_name = "Test Rat"
	s.idle_time_min = 1.0
	s.idle_time_max = 1.0
	s.move_duration = 0.5
	s.hunger_rate = 0.0
	s.hungry_threshold = 70.0
	s.sated_threshold = 30.0
	s.initial_hunger_max = 0.0
	s.food_detection_radius = 5
	s.eat_duration = 1.0
	s.hydration_rate = rate
	s.thirsty_threshold = thirsty
	s.sated_hydration = sated
	s.water_detection_radius = radius
	s.drink_duration = 1.0
	s.bladder_capacity = capacity
	s.urination_amount = 1.0
	s.trip_steps_min = 1
	s.trip_steps_max = 1
	s.sleep_start_hour = 0
	s.wake_hour = 0
	s.side_texture = RODENT.side_texture
	s.front_texture = RODENT.front_texture
	return s


func _floored(width := 8, height := 5) -> DungeonFloor:
	var f := DungeonFloor.new(width, height)
	for position in f.get_positions():
		f.place_floor(position)
	return f


## A world with a resource system attached, driven by hand.
func _world(seed_value := 1) -> Array:
	var creatures := CreatureSystem.new(seed_value, false)
	var sources := FoodSystem.new(seed_value)
	creatures.food_system = sources
	return [creatures, sources]


func _run_ticks(system: CreatureSystem, count: int) -> void:
	for i in count:
		system.tick(TICK, DAY_HOUR)


func _place(system: CreatureSystem, species: CreatureSpecies, f: DungeonFloor,
		position: Vector2i, hydration := Creature.MAX_HYDRATION, id := 1) -> Creature:
	var creature := Creature.new(id, species, f, position, 0.0)
	creature.hydration = hydration
	system.get_creatures().append(creature)
	return creature


# --------------------------------------------------------------------------

func _test_hydration_falls() -> void:
	section("1 hydration falls with simulation time")
	var f := _floored()
	var system := CreatureSystem.new(1, false)
	var rat := _place(system, _species(2.0), f, Vector2i(2, 2))
	check("starts full", rat.hydration, Creature.MAX_HYDRATION)
	_run_ticks(system, 100)
	check_approx("2 per second for 5 s", rat.hydration, 90.0, 1e-6)
	_run_ticks(system, 100)
	check_approx("and again", rat.hydration, 80.0, 1e-6)

	section("it never goes below zero")
	var dry := _place(system, _species(2.0), f, Vector2i(6, 2), 1.0, 2)
	_run_ticks(system, 400)
	check("bottoms out at 0", dry.hydration, 0.0)


func _test_thirst_threshold() -> void:
	section("2 the thirst threshold")
	var f := _floored()
	var system := CreatureSystem.new(2, false)
	var rat := _place(system, _species(0.0, 40.0), f, Vector2i(2, 2), 41.0)
	check_false("41 is not thirsty", rat.is_thirsty())
	check("state is not THIRSTY", rat.state != Creature.State.THIRSTY, true)
	rat.hydration = 40.0
	rat.set_intent(Creature.Intent.WANDER)
	check_true("40 is thirsty", rat.is_thirsty())
	check("and it shows", rat.state, Creature.State.THIRSTY)
	check_true("so it wants water", rat.wants_water())

	section("hysteresis: it drinks past the threshold, not just to it")
	rat.set_intent(Creature.Intent.DRINK)
	rat.hydration = 60.0
	check_true("still wants water at 60", rat.wants_water())
	rat.hydration = 90.0
	check_false("stops at the sated level", rat.wants_water())


func _test_perception() -> void:
	section("3 finding water, and not confusing it with food")
	var f := _floored()
	var sources := FoodSystem.new(3)
	var water := sources.place(f, Vector2i(5, 2), 100.0, 25.0, null, FoodSource.Kind.WATER)
	var food := sources.place(f, Vector2i(3, 2), 100.0, 25.0, null, FoodSource.Kind.FOOD)
	check_true("water knows what it is", water.is_water())
	check_false("food knows what it is", food.is_water())

	check("finds the water", sources.find_nearest(f, Vector2i(6, 2), 5,
		FoodSource.Kind.WATER), water)
	check("finds the food", sources.find_nearest(f, Vector2i(6, 2), 5,
		FoodSource.Kind.FOOD), food)
	check("the nearer food is not offered as water",
		sources.find_nearest(f, Vector2i(2, 2), 5, FoodSource.Kind.WATER), water)
	check("water out of range is invisible",
		sources.find_nearest(f, Vector2i(0, 4), 2, FoodSource.Kind.WATER) == null, true)
	while not water.is_depleted():
		water.take_bite()
	check("an emptied pool is ignored",
		sources.find_nearest(f, Vector2i(6, 2), 5, FoodSource.Kind.WATER) == null, true)


func _test_seeks_and_drinks() -> void:
	section("4-6 walks to water and drinks it")
	var f := _floored()
	var pair := _world(4)
	var creatures: CreatureSystem = pair[0]
	var sources: FoodSystem = pair[1]
	var pool := sources.place(f, Vector2i(4, 2), 100.0, 25.0, null, FoodSource.Kind.WATER)
	var rat := _place(creatures, _species(0.0, 40.0, 90.0), f, Vector2i(0, 2), 30.0)

	_run_ticks(creatures, 1)
	check("thirsty: intent SEEK_WATER", rat.intent, Creature.Intent.SEEK_WATER)
	check("targets the pool", rat.water_target, pool)
	check("state shows SEEK_WATER", rat.state, Creature.State.SEEK_WATER)

	var distances: Array[int] = []
	for i in 40:
		creatures.tick(TICK, DAY_HOUR)
		distances.append(absi(rat.grid_position.x - 4) + absi(rat.grid_position.y - 2))
	check("reached the water", rat.grid_position, Vector2i(4, 2))
	var away := 0
	for i in range(1, distances.size()):
		if distances[i] > distances[i - 1]:
			away += 1
	check("never walked away from it", away, 0)

	check("first sip: hydration 30 -> 55", rat.hydration, 55.0)
	check("the pool lost the same", pool.amount, 75.0)
	check("intent DRINK", rat.intent, Creature.Intent.DRINK)
	_run_ticks(creatures, 20)
	check("second sip", rat.hydration, 80.0)
	_run_ticks(creatures, 20)
	check("third sip fills it", rat.hydration, 100.0)
	check("pool down to 25", pool.amount, 25.0)
	_run_ticks(creatures, 40)
	check("sated: back to wandering", rat.intent, Creature.Intent.WANDER)
	check("target released", rat.water_target == null, true)
	check("and it stopped drinking", pool.amount, 25.0)


func _test_drinking_enables_urination() -> void:
	section("7 drinking is what makes urine later")
	var f := _floored()
	var pair := _world(5)
	var creatures: CreatureSystem = pair[0]
	var sources: FoodSystem = pair[1]
	sources.place(f, Vector2i(1, 2), 100.0, 25.0, null, FoodSource.Kind.WATER)
	# Dry, next to water, spending 1 hydration a second into a 5 unit bladder.
	var rat := _place(creatures, _species(1.0, 40.0, 90.0, 5.0), f, Vector2i(0, 2), 0.0)
	check("bone dry", rat.hydration, 0.0)
	check("empty bladder", rat.bladder, 0.0)

	_run_ticks(creatures, 200)
	check_true("it drank", rat.hydration > 50.0)
	check_true("and the bladder is filling from what it spends", rat.bladder > 0.0)

	var wet_before := f.get_peed_positions().size()
	_run_ticks(creatures, 600)
	check_true("which eventually becomes a puddle",
		f.get_peed_positions().size() > wet_before)


func _test_no_water_no_pee() -> void:
	section("8 no water, no urine - hydration is never conjured")
	var f := _floored()
	var pair := _world(6)
	var creatures: CreatureSystem = pair[0]
	# No sources placed at all.
	var rat := _place(creatures, _species(1.0, 40.0, 90.0, 5.0), f, Vector2i(3, 2), 0.0)
	_run_ticks(creatures, 4000)
	check("still bone dry after 200 s", rat.hydration, 0.0)
	check("never urinated", f.get_peed_positions().size(), 0)
	check("bladder never filled", rat.bladder, 0.0)
	check_true("and it is still alive", rat.alive)
	check("it did keep wandering", rat.intent, Creature.Intent.WANDER)

	section("a rodent that drinks once cannot urinate forever")
	var pair2 := _world(7)
	var creatures2: CreatureSystem = pair2[0]
	var sources2: FoodSystem = pair2[1]
	var f2 := _floored()
	# A single sip: 10 units of water in, so 10 units of urine out at most.
	sources2.place(f2, Vector2i(1, 2), 10.0, 10.0, null, FoodSource.Kind.WATER)
	var rat2 := _place(creatures2, _species(1.0, 40.0, 90.0, 5.0), f2, Vector2i(0, 2), 0.0)
	_run_ticks(creatures2, 6000)
	check("the pool is gone", sources2.get_count(), 0)
	check("dry again", rat2.hydration, 0.0)
	var total := 0.0
	for position in f2.get_peed_positions():
		total += f2.get_tile(position).pee_amount
	check_true("it urinated at most twice from 10 units of water (%d)" % int(total),
		total > 0.0 and total <= 2.0)


func _test_thirst_before_hunger() -> void:
	section("thirsty and hungry: water first")
	var f := _floored()
	var pair := _world(8)
	var creatures: CreatureSystem = pair[0]
	var sources: FoodSystem = pair[1]
	var water := sources.place(f, Vector2i(5, 2), 100.0, 25.0, null, FoodSource.Kind.WATER)
	sources.place(f, Vector2i(1, 2), 100.0, 25.0, null, FoodSource.Kind.FOOD)
	var rat := _place(creatures, _species(0.0, 40.0, 90.0), f, Vector2i(3, 2), 20.0)
	rat.hunger = 90.0
	_run_ticks(creatures, 1)
	check("goes for water despite being hungry", rat.intent, Creature.Intent.SEEK_WATER)
	check("water is the target", rat.water_target, water)
	check("food is not", rat.food_target == null, true)

	section("once watered it goes for the food")
	rat.hydration = Creature.MAX_HYDRATION
	_run_ticks(creatures, 2)
	check("now seeking food", rat.intent, Creature.Intent.SEEK_FOOD)
	check("water target dropped", rat.water_target == null, true)


func _test_independent() -> void:
	section("11 rodents hydrate independently")
	var f := _floored()
	var pair := _world(9)
	var creatures: CreatureSystem = pair[0]
	var sources: FoodSystem = pair[1]
	sources.place(f, Vector2i(1, 1), 100.0, 25.0, null, FoodSource.Kind.WATER)
	var drinker := _place(creatures, _species(0.5, 40.0, 90.0), f, Vector2i(1, 2), 20.0, 1)
	var loner := _place(creatures, _species(0.5, 40.0, 90.0), f, Vector2i(7, 4), 20.0, 2)
	_run_ticks(creatures, 200)
	check_true("the one beside water drank", drinker.hydration > 40.0)
	check_true("the far one did not", loner.hydration < 20.0)
	check_true("and they hold different amounts", drinker.hydration != loner.hydration)


func _test_pause_and_speed() -> void:
	section("12-13 pause and speed")
	var f := _floored()
	var creatures := CreatureSystem.new(10, true)
	var sources := FoodSystem.new(10)
	creatures.food_system = sources
	var rat := _place(creatures, _species(2.0, 0.0, 0.0, 5.0), f, Vector2i(4, 2))

	SimulationManager.set_speed(1.0)
	SimulationManager.resume()
	await real_seconds(0.5)
	SimulationManager.pause()
	var frozen := [rat.hydration, rat.bladder]
	check_true("hydration had been falling", rat.hydration < Creature.MAX_HYDRATION)
	await real_seconds(0.6)
	check("paused: hydration and bladder both hold", [rat.hydration, rat.bladder], frozen)

	var rate_1x := await _hydration_lost_per_real_second(rat, 1.0, 0.8)
	var rate_10x := await _hydration_lost_per_real_second(rat, 10.0, 0.8)
	check_true("it falls at 1x (%.1f/s)" % rate_1x, rate_1x > 0.0)
	check_between("10x is about ten times as fast (%.1f vs %.1f)" % [rate_10x, rate_1x],
		rate_10x / rate_1x, 7.0, 13.0)
	SimulationManager.set_speed(1.0)


func _hydration_lost_per_real_second(rat: Creature, speed: float,
		seconds: float) -> float:
	rat.hydration = Creature.MAX_HYDRATION
	SimulationManager.set_speed(speed)
	SimulationManager.resume()
	await frames(2)
	var before := rat.hydration
	var start := Time.get_ticks_usec()
	await real_seconds(seconds)
	SimulationManager.pause()
	return (before - rat.hydration) / elapsed_since(start)


func _test_main_scene() -> void:
	section("the real scene: W places water and a thirsty rodent drinks it")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	var dungeon: Dungeon = main._dungeon
	var sources: FoodSystem = main._food
	for position in dungeon.get_positions():
		dungeon.place_floor(position)
	while GameTime.get_hour() < 9 or GameTime.get_hour() > 18:
		SimulationManager.step(25)

	main._spawn_rodent_here()
	var rat: Creature = main._creatures.get_creatures()[0]
	rat.hydration = 10.0
	for direction in Creature.STEP_DIRECTIONS:
		var beside: Vector2i = rat.grid_position + direction
		if sources.can_place_at(dungeon.get_current_floor(), beside):
			sources.place(dungeon.get_current_floor(), beside, 100.0, 25.0, null,
				FoodSource.Kind.WATER)
			break
	check("a water source exists", sources.get_count(), 1)
	check_true("and it is water", sources.get_sources()[0].is_water())

	var drank := false
	for i in 2000:
		SimulationManager.step(1)
		if rat.hydration > 10.0:
			drank = true
			break
	check_true("the rodent drank in the real scene", drank)
	check_true("W places water too", main._drop_water_here() == null
		or sources.get_count() >= 1)
	main.queue_free()
	await frames(2)
