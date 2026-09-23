class_name CreatureBehaviour
extends RefCounted

## Decides what a creature does next.
##
## Split out from [CreatureSystem] the moment a second behaviour appeared, so
## that class keeps owning mechanics — what is legal, how a step is taken, the
## random numbers — while this one owns the choice between wandering, going to
## find food or water, and consuming it. It is a handful of functions, not a
## framework.
##
## Thirst is checked before hunger: a creature that needs both goes for water
## first.
##
## Everything is static: the decision depends only on the creature and the world
## it is handed, so there is no state to keep.

## Called once per simulation tick for every living creature.
## [param arrived] is true on the tick it finished stepping onto a new tile.
static func decide(creature: Creature, system: CreatureSystem, arrived: bool) -> void:
	if creature.asleep:
		# Whatever it was doing, it stops on the tile it reached.
		if arrived:
			creature.rest(system.random_idle_duration(creature.species))
		return

	_review_targets(creature, system)

	if creature.water_target != null:
		_pursue(creature, system, creature.water_target, true)
	elif creature.food_target != null:
		_pursue(creature, system, creature.food_target, false)
	else:
		_wander(creature, system, arrived)


## Keeps both targets honest: drops one when the creature stops caring or the
## source is gone, and looks for one when it starts caring.
##
## Re-checked every tick, which is what lets a creature notice that another one
## finished the source it was walking towards.
static func _review_targets(creature: Creature, system: CreatureSystem) -> void:
	var sources := system.food_system
	if sources == null:
		creature.forget_food_target()
		creature.forget_water_target()
		return

	# Water first: a creature that is both thirsty and hungry drinks first.
	if creature.wants_water():
		if not _target_still_there(creature.water_target, sources):
			creature.forget_water_target()
		if creature.water_target == null:
			creature.water_target = sources.find_nearest(
				creature.dungeon_floor, creature.grid_position,
				creature.species.water_detection_radius, FoodSource.Kind.WATER)
	else:
		creature.forget_water_target()

	if creature.water_target != null or not creature.wants_food():
		creature.forget_food_target()
		return

	if not _target_still_there(creature.food_target, sources):
		creature.forget_food_target()
	if creature.food_target == null:
		creature.food_target = sources.find_nearest(
			creature.dungeon_floor, creature.grid_position,
			creature.species.food_detection_radius, FoodSource.Kind.FOOD)


static func _target_still_there(target: FoodSource, sources: FoodSystem) -> bool:
	return target != null and not target.is_depleted() and sources.has(target)


## Walks to a source and consumes it. One routine for food and water: the only
## difference is which need a serving restores.
static func _pursue(creature: Creature, system: CreatureSystem,
		target: FoodSource, for_water: bool) -> void:
	var standing_on_it := creature.grid_position == target.grid_position
	if for_water:
		creature.set_intent(
			Creature.Intent.DRINK if standing_on_it else Creature.Intent.SEEK_WATER)
	else:
		creature.set_intent(
			Creature.Intent.EAT if standing_on_it else Creature.Intent.SEEK_FOOD)
	# A trip is a wandering idea; drop any leftover steps so the creature does not
	# resume one after it has finished eating.
	creature.begin_trip(0)

	if not creature.is_ready_to_move():
		return

	if standing_on_it:
		_take_serving(creature, system, target, for_water)
		return

	if not _step_toward(creature, system, target.grid_position):
		# Blocked for the moment — another creature in the doorway, most likely.
		# Wait a little and look again rather than giving up on the meal.
		creature.rest(system.random_idle_duration(creature.species))


## One serving: the source loses it and the matching need is restored by the
## same amount. Deterministic, and the source is removed once it is gone.
static func _take_serving(creature: Creature, system: CreatureSystem,
		target: FoodSource, for_water: bool) -> void:
	var taken := target.take_bite()
	if for_water:
		creature.drink(taken)
		creature.rest(creature.species.drink_duration)
	else:
		creature.feed(taken)
		creature.rest(creature.species.eat_duration)
	if target.is_depleted():
		system.food_system.remove(target)
		if for_water:
			creature.forget_water_target()
		else:
			creature.forget_food_target()


## Greedy step toward [param goal]: the legal neighbour that gets closest.
##
## This is deliberately not pathfinding. On an open floor it walks straight
## there; a wall between creature and food can stall it, which is why food is
## expected to be reachable across neighbouring tiles for now.
static func _step_toward(creature: Creature, system: CreatureSystem,
		goal: Vector2i) -> bool:
	var here := creature.grid_position
	var best_distance := _steps_between(here, goal)
	var closer: Array[Vector2i] = []
	var any_legal: Array[Vector2i] = []

	for direction in Creature.STEP_DIRECTIONS:
		var candidate := here + direction
		if not system.can_move_to(creature, candidate):
			continue
		any_legal.append(candidate)
		var distance := _steps_between(candidate, goal)
		if distance < best_distance:
			best_distance = distance
			closer = [candidate]
		elif distance == best_distance and not closer.is_empty():
			closer.append(candidate)

	if not closer.is_empty():
		return creature.start_move(system.pick_random(closer))
	if any_legal.is_empty():
		return false
	# Nothing gets it closer: shuffle sideways rather than stand still, which
	# frees it from simple obstacles without any path planning.
	return creature.start_move(system.pick_random(any_legal))


## The original behaviour, unchanged: trips of several tiles, then a rest.
static func _wander(creature: Creature, system: CreatureSystem, arrived: bool) -> void:
	creature.set_intent(Creature.Intent.WANDER)
	if arrived:
		system.continue_trip(creature)
	elif creature.is_ready_to_move():
		creature.begin_trip(system.random_trip_length(creature.species))
		system.take_step(creature)


static func _steps_between(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
