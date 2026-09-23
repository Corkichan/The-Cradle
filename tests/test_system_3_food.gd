extends "res://tests/test_suite.gd"

const RODENT: CreatureSpecies = preload("res://assets/creatures/rodent/maniac_sewer_rat.tres")
const TICK: float = 0.05
const DAY_HOUR: int = 12


func _init() -> void:
	title = "System 3 - Food"


func run() -> void:
	_test_food_source()
	_test_placement()
	_test_perception()
	_test_intent()
	_test_walks_to_food()
	_test_eating()
	_test_depletion()
	_test_multiple_rodents()
	await _test_pause_and_speed()
	_test_main_scene_wiring()


# --------------------------------------------------------------------------

## Hunger held still (rate 0) unless a test wants it moving, so eating maths is
## exact. Never sleeps.
func _species(rate := 0.0, threshold := 70.0, sated := 30.0, eat := 1.0,
		radius := 5, move := 0.5) -> CreatureSpecies:
	var s := CreatureSpecies.new()
	s.species_name = "Rodent"
	s.variant_name = "Test Rat"
	s.idle_time_min = 1.0
	s.idle_time_max = 1.0
	s.move_duration = move
	s.hunger_rate = rate
	s.hungry_threshold = threshold
	s.sated_threshold = sated
	s.eat_duration = eat
	s.food_detection_radius = radius
	s.initial_hunger_max = 0.0
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


## A world with food attached, driven by hand.
func _world(seed_value := 1) -> Array:
	var creatures := CreatureSystem.new(seed_value, false)
	var food := FoodSystem.new(seed_value)
	creatures.food_system = food
	return [creatures, food]


func _run_ticks(system: CreatureSystem, count: int) -> void:
	for i in count:
		system.tick(TICK, DAY_HOUR)


func _place_creature(system: CreatureSystem, species: CreatureSpecies,
		f: DungeonFloor, position: Vector2i, hunger: float, id := 1) -> Creature:
	var creature := Creature.new(id, species, f, position, hunger)
	system.get_creatures().append(creature)
	return creature


# --------------------------------------------------------------------------

func _test_food_source() -> void:
	section("4-5 a food source has an amount and a nutrition")
	var f := _floored()
	var food := FoodSource.new(1, f, Vector2i(2, 2))
	check("default amount", food.amount, 100.0)
	check("default nutrition", food.nutrition, 25.0)
	check("knows its tile", food.grid_position, Vector2i(2, 2))
	check("knows its floor", food.dungeon_floor, f)
	check_false("not depleted", food.is_depleted())

	section("bites are deterministic and never go negative")
	check("a bite is worth its nutrition", food.take_bite(), 25.0)
	check("amount drops by the same", food.amount, 75.0)
	food.take_bite()
	food.take_bite()
	check("three bites eaten", food.amount, 25.0)
	check("last bite finishes it", food.take_bite(), 25.0)
	check("amount lands on zero", food.amount, 0.0)
	check_true("now depleted", food.is_depleted())
	check("biting an empty pile yields nothing", food.take_bite(), 0.0)
	check("and cannot go negative", food.amount, 0.0)

	section("values are configurable")
	var custom := FoodSource.new(2, f, Vector2i(0, 0), 30.0, 12.0)
	check("custom amount", custom.amount, 30.0)
	check("custom nutrition", custom.nutrition, 12.0)
	custom.take_bite()
	custom.take_bite()
	check("2 bites of 12 from 30", custom.amount, 6.0)
	check("the last bite is only what is left", custom.take_bite(), 6.0)
	check_true("depleted", custom.is_depleted())


func _test_placement() -> void:
	section("1-3 where food may be placed")
	var f := _floored()
	var pair := _world()
	var creatures: CreatureSystem = pair[0]
	var food: FoodSystem = pair[1]

	check_true("on a floored tile", food.place(f, Vector2i(3, 2)) != null)
	check("one source in the world", food.get_count(), 1)
	check("and it is on that tile", food.at(f, Vector2i(3, 2)).grid_position, Vector2i(3, 2))

	check("outside the dungeon is refused", food.place(f, Vector2i(9, 9)) == null, true)
	check("negative coordinates refused", food.place(f, Vector2i(-1, 0)) == null, true)
	check("still one source", food.get_count(), 1)

	var bare := DungeonFloor.new(4, 4)
	check("a tile with no floor built is refused", food.place(bare, Vector2i(1, 1)) == null, true)
	bare.place_floor(Vector2i(1, 1))
	check_true("once floor is placed it works", food.place(bare, Vector2i(1, 1)) != null)

	check("two piles on one tile refused", food.place(f, Vector2i(3, 2)) == null, true)

	section("not under a creature")
	_place_creature(creatures, _species(), f, Vector2i(5, 1), 0.0)
	check_false("can_place_at says no", food.can_place_at(f, Vector2i(5, 1), creatures))
	check("place refuses", food.place(f, Vector2i(5, 1), 100.0, 25.0, creatures) == null, true)
	check_true("without the occupancy check it would allow it",
		food.can_place_at(f, Vector2i(5, 1)))

	section("scattering several")
	var scatter_floor := _floored(4, 4)
	var scatter := FoodSystem.new(3)
	var placed := scatter.place_random(scatter_floor, 5)
	check("5 placed on a 16 tile floor", placed.size(), 5)
	var tiles := {}
	for source in placed:
		tiles[source.grid_position] = true
		check_true("on a floored tile", scatter_floor.is_walkable(source.grid_position))
	check("no two share a tile", tiles.size(), 5)
	check("capped by the space available", scatter.place_random(scatter_floor, 100).size(), 11)
	check("a bare dungeon takes none",
		FoodSystem.new(3).place_random(DungeonFloor.new(8, 5), 4).size(), 0)


func _test_perception() -> void:
	section("6 noticing nearby food")
	var f := _floored()
	var food := FoodSystem.new(1)
	var near := food.place(f, Vector2i(4, 2))
	check("finds it 2 steps away", food.find_nearest(f, Vector2i(2, 2), 5), near)
	check("finds it at exactly the radius", food.find_nearest(f, Vector2i(0, 0), 6), near)
	check("beyond the radius it is invisible",
		food.find_nearest(f, Vector2i(0, 0), 5) == null, true)
	# (4,2) is 4 steps from (2,0) but only 2 tiles away diagonally. A radius of 3
	# must miss it, which is what proves distance is counted in steps.
	check("radius 3 misses food 4 steps away",
		food.find_nearest(f, Vector2i(2, 0), 3) == null, true)
	check("radius 4 reaches it", food.find_nearest(f, Vector2i(2, 0), 4), near)

	var nearer := food.place(f, Vector2i(3, 2))
	check("prefers the closer pile", food.find_nearest(f, Vector2i(1, 2), 5), nearer)
	while not nearer.is_depleted():
		nearer.take_bite()
	check("ignores an emptied pile", food.find_nearest(f, Vector2i(1, 2), 5), near)

	var other_floor := _floored()
	food.place(other_floor, Vector2i(1, 2))
	check("never sees food on another floor",
		food.find_nearest(f, Vector2i(1, 2), 5), near)


func _test_intent() -> void:
	section("7 intent follows hunger")
	var f := _floored()
	var pair := _world()
	var creatures: CreatureSystem = pair[0]
	var food: FoodSystem = pair[1]
	var meal := food.place(f, Vector2i(4, 2))

	var full := _place_creature(creatures, _species(), f, Vector2i(2, 2), 10.0)
	_run_ticks(creatures, 2)
	check("not hungry: keeps wandering", full.intent, Creature.Intent.WANDER)
	check("no target", full.food_target == null, true)

	var hungry := _place_creature(creatures, _species(), f, Vector2i(2, 4), 80.0, 2)
	_run_ticks(creatures, 1)
	check("hungry: intent SEEK_FOOD", hungry.intent, Creature.Intent.SEEK_FOOD)
	check("targets the food", hungry.food_target, meal)
	check("state shows SEEK_FOOD", hungry.state, Creature.State.SEEK_FOOD)

	section("hungry but nothing in range")
	var lonely_floor := _floored()
	var lonely_pair := _world(2)
	var lonely_creatures: CreatureSystem = lonely_pair[0]
	var far := _place_creature(lonely_creatures, _species(0.0, 70.0, 30.0, 1.0, 1),
		lonely_floor, Vector2i(0, 0), 80.0)
	lonely_pair[1].place(lonely_floor, Vector2i(7, 4))
	_run_ticks(lonely_creatures, 4)
	check("out of range: no target", far.food_target == null, true)
	check("intent stays WANDER", far.intent, Creature.Intent.WANDER)
	check("but it still reports HUNGRY", far.state, Creature.State.HUNGRY)


func _test_walks_to_food() -> void:
	section("8 walks toward the food")
	var f := _floored()
	var pair := _world()
	var creatures: CreatureSystem = pair[0]
	var food: FoodSystem = pair[1]
	food.place(f, Vector2i(4, 2))
	var rat := _place_creature(creatures, _species(), f, Vector2i(0, 2), 80.0)

	var distances: Array[int] = []
	for i in 45:
		creatures.tick(TICK, DAY_HOUR)
		distances.append(absi(rat.grid_position.x - 4) + absi(rat.grid_position.y - 2))
	check("ends up on the food tile", rat.grid_position, Vector2i(4, 2))
	var got_further := 0
	for i in range(1, distances.size()):
		if distances[i] > distances[i - 1]:
			got_further += 1
	check("never walked away from it", got_further, 0)
	check("4 tiles away, 4 steps taken, 10 ticks each", distances[40], 0)

	section("goes around a gap in the floor")
	var blocked := _floored()
	blocked.remove_floor(Vector2i(2, 2))
	var detour_pair := _world(4)
	var detour_creatures: CreatureSystem = detour_pair[0]
	detour_pair[1].place(blocked, Vector2i(4, 2))
	var walker := _place_creature(detour_creatures, _species(), blocked, Vector2i(0, 2), 80.0)
	var reached := false
	for i in 400:
		detour_creatures.tick(TICK, DAY_HOUR)
		if walker.grid_position == Vector2i(4, 2):
			reached = true
			break
	check_true("still reaches food with a hole in the way", reached)
	check_false("never stepped on the floorless tile",
		walker.grid_position == Vector2i(2, 2))


func _test_eating() -> void:
	section("9-11 eating")
	var f := _floored()
	var pair := _world()
	var creatures: CreatureSystem = pair[0]
	var food: FoodSystem = pair[1]
	var meal := food.place(f, Vector2i(4, 2))
	var rat := _place_creature(creatures, _species(), f, Vector2i(0, 2), 80.0)

	_run_ticks(creatures, 41)
	check("arrived on the food", rat.grid_position, Vector2i(4, 2))
	check("intent EAT", rat.intent, Creature.Intent.EAT)
	check("state EAT", rat.state, Creature.State.EAT)
	check("hunger 80 -> 55", rat.hunger, 55.0)
	check("food 100 -> 75", meal.amount, 75.0)

	_run_ticks(creatures, 19)
	check("still chewing one mouthful later", rat.hunger, 55.0)
	_run_ticks(creatures, 1)
	check("second mouthful after eat_duration", rat.hunger, 30.0)
	check("food 75 -> 50", meal.amount, 50.0)

	section("13 stops once it has had enough")
	_run_ticks(creatures, 40)
	check("sated at the threshold: back to wandering", rat.intent, Creature.Intent.WANDER)
	check("target released", rat.food_target == null, true)
	check("hunger left where eating stopped", rat.hunger, 30.0)
	check("and it stopped taking food", meal.amount, 50.0)

	section("a creature that is not hungry ignores food it stands on")
	var calm_pair := _world(5)
	var calm_creatures: CreatureSystem = calm_pair[0]
	var calm_food: FoodSystem = calm_pair[1]
	var untouched := calm_food.place(f, Vector2i(1, 1))
	_place_creature(calm_creatures, _species(), f, Vector2i(1, 1), 10.0)
	_run_ticks(calm_creatures, 200)
	check("food untouched", untouched.amount, 100.0)


func _test_depletion() -> void:
	section("12 food disappears when it is finished")
	var f := _floored()
	var pair := _world()
	var creatures: CreatureSystem = pair[0]
	var food: FoodSystem = pair[1]
	var small := food.place(f, Vector2i(1, 2), 50.0, 25.0)
	var removed: Array[FoodSource] = []
	food.food_depleted.connect(func(x: FoodSource) -> void: removed.append(x))
	var rat := _place_creature(creatures, _species(0.0, 70.0, 0.0), f, Vector2i(0, 2), 90.0)

	_run_ticks(creatures, 11)
	check("reached it", rat.grid_position, Vector2i(1, 2))
	check("one bite taken", small.amount, 25.0)
	check("still in the world", food.get_count(), 1)
	_run_ticks(creatures, 20)
	check("second bite empties it", small.amount, 0.0)
	check("removed from the world", food.get_count(), 0)
	check_false("system no longer has it", food.has(small))
	check("food_depleted fired once", removed.size(), 1)
	check("for that pile", removed[0], small)
	check("the creature let go of it", rat.food_target == null, true)
	check("it ate 50 worth", rat.hunger, 40.0)


func _test_multiple_rodents() -> void:
	section("14 several rodents, one pile")
	var f := _floored()
	var pair := _world(7)
	var creatures: CreatureSystem = pair[0]
	var food: FoodSystem = pair[1]
	var meal := food.place(f, Vector2i(3, 2), 25.0, 25.0)
	var near := _place_creature(creatures, _species(), f, Vector2i(2, 2), 80.0, 1)
	var far := _place_creature(creatures, _species(), f, Vector2i(6, 2), 80.0, 2)

	_run_ticks(creatures, 1)
	check("both target the same pile", [near.food_target, far.food_target], [meal, meal])
	_run_ticks(creatures, 12)
	check("the nearer one got there", near.grid_position, Vector2i(3, 2))
	check("and emptied it", food.get_count(), 0)
	check("its hunger dropped", near.hunger, 55.0)

	_run_ticks(creatures, 2)
	check("the other let go of the vanished pile", far.food_target == null, true)
	check("and went back to wandering", far.intent, Creature.Intent.WANDER)
	check("still hungry though", far.state, Creature.State.HUNGRY)
	check("it never ate", far.hunger, 80.0)

	section("they eat independently")
	var two_pair := _world(8)
	var two_creatures: CreatureSystem = two_pair[0]
	var two_food: FoodSystem = two_pair[1]
	var meal_a := two_food.place(f, Vector2i(1, 1), 100.0, 25.0)
	var meal_b := two_food.place(f, Vector2i(6, 3), 100.0, 25.0)
	var rat_a := _place_creature(two_creatures, _species(), f, Vector2i(1, 2), 80.0, 1)
	var rat_b := _place_creature(two_creatures, _species(), f, Vector2i(6, 4), 80.0, 2)
	var visited_a := false
	var visited_b := false
	for i in 80:
		two_creatures.tick(TICK, DAY_HOUR)
		visited_a = visited_a or rat_a.grid_position == Vector2i(1, 1)
		visited_b = visited_b or rat_b.grid_position == Vector2i(6, 3)
	# They wander off again once sated, so look at where they went, not where
	# they happen to be standing at the end.
	check("each visited its own pile", [visited_a, visited_b], [true, true])
	check("both ate down to the threshold", [rat_a.hunger, rat_b.hunger], [30.0, 30.0])
	check("each pile lost 50", [meal_a.amount, meal_b.amount], [50.0, 50.0])


func _test_pause_and_speed() -> void:
	section("15-16 pause and speed")
	var f := _floored()
	var food := FoodSystem.new(1)
	var creatures := CreatureSystem.new(9, true)
	creatures.food_system = food
	var meal := food.place(f, Vector2i(4, 2))
	var rat := _place_creature(creatures, _species(1.0), f, Vector2i(3, 2), 80.0)

	SimulationManager.set_speed(1.0)
	SimulationManager.resume()
	await real_seconds(0.6)
	SimulationManager.pause()
	var frozen := [rat.grid_position, rat.hunger, rat.intent, meal.amount]
	await real_seconds(0.6)
	check("paused: nothing about the meal changes",
		[rat.grid_position, rat.hunger, rat.intent, meal.amount], frozen)

	section("speed")
	# A creature that is never satisfied, standing on an endless pile: how fast it
	# eats then depends only on how many simulation ticks happen, which is exactly
	# what speed changes. Gate it on hunger instead and the hunger cycle, not the
	# tick rate, sets the pace.
	var greedy_floor := _floored()
	var greedy_food := FoodSystem.new(2)
	var greedy := CreatureSystem.new(11, true)
	greedy.food_system = greedy_food
	var pile := greedy_food.place(greedy_floor, Vector2i(2, 2), 1000000.0, 25.0)
	_place_creature(greedy, _species(0.0, 1.0, -1.0, 0.1), greedy_floor, Vector2i(2, 2), 50.0)

	var rate_1x := await _eaten_per_real_second(pile, 1.0, 0.8)
	var rate_10x := await _eaten_per_real_second(pile, 10.0, 0.8)
	check_true("it does eat at 1x (%.0f/s)" % rate_1x, rate_1x > 0.0)
	check_between("10x eats about ten times faster (%.0f vs %.0f per real second)"
		% [rate_10x, rate_1x], rate_10x / rate_1x, 7.0, 13.0)
	SimulationManager.set_speed(1.0)


## Food eaten per real second at a given simulation speed.
func _eaten_per_real_second(pile: FoodSource, speed: float, seconds: float) -> float:
	SimulationManager.set_speed(speed)
	SimulationManager.resume()
	await frames(2)
	var before := pile.amount
	var start := Time.get_ticks_usec()
	await real_seconds(seconds)
	SimulationManager.pause()
	return (before - pile.amount) / elapsed_since(start)


func _test_main_scene_wiring() -> void:
	section("the main scene wires food into the world")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	var dungeon: Dungeon = main._dungeon
	var food: FoodSystem = main._food
	check("food system exists", food != null, true)
	check("creatures can see it", main._creatures.food_system, food)
	check("bare dungeon starts with no food", food.get_count(), 0)

	for position in dungeon.get_positions():
		dungeon.place_floor(position)
	main._drop_food_here()
	main._drop_food_here()
	check("F drops food", food.get_count(), 2)
	check_true("on a floored tile of this floor",
		dungeon.is_walkable(food.get_sources()[0].grid_position))
	var layer: FoodLayer = main.get_node("FoodLayer")
	check("a view per source", layer.get_child_count(), 2)
	check_true("and it is visible", layer.get_view(food.get_sources()[0]).visible)

	main._spawn_rodent_here()
	var rat: Creature = main._creatures.get_creatures()[0]
	rat.hunger = 95.0
	# Put a pile right beside it rather than trusting the random scatter to land
	# inside its detection radius, which made this check depend on luck.
	for direction in Creature.STEP_DIRECTIONS:
		var beside: Vector2i = rat.grid_position + direction
		if food.can_place_at(dungeon.get_current_floor(), beside):
			food.place(dungeon.get_current_floor(), beside)
			break
	var eaten := false
	for i in 2000:
		SimulationManager.step(1)
		if rat.hunger < 95.0:
			eaten = true
			break
	check_true("a hungry rodent in the real scene finds and eats food", eaten)
	main.queue_free()
