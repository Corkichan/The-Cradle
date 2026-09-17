class_name CreatureSystem
extends RefCounted

## Owns every living creature and drives them from simulation ticks.
##
## Responsibilities, deliberately few:
##   - hold the collection,
##   - advance each creature once per [signal SimulationManager.simulation_tick],
##   - spawn creatures onto a floor,
##   - decide whether a step is legal, and pick wander steps.
##
## Creatures on every floor keep living, whichever floor is being viewed. Which
## ones get DRAWN is the renderer's business, not this class's.
##
## The wander choice lives here for now because it is the only behaviour. When a
## second one arrives (seeking food), pull behaviours out rather than letting
## this class grow into the place all creature logic lives.

signal creature_spawned(creature: Creature)

var _creatures: Array[Creature] = []
var _next_id: int = 1
var _rng: RandomNumberGenerator


## [param rng_seed] makes spawning and wandering reproducible, for tests.
## [param connect_to_simulation] is false only when a caller wants to drive
## [method tick] by hand.
func _init(rng_seed: int = -1, connect_to_simulation: bool = true) -> void:
	_rng = RandomNumberGenerator.new()
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	if connect_to_simulation:
		SimulationManager.simulation_tick.connect(tick)


func get_creatures() -> Array[Creature]:
	return _creatures


func get_creature_count() -> int:
	return _creatures.size()


## Creatures living on [param dungeon_floor].
func get_creatures_on(dungeon_floor: DungeonFloor) -> Array[Creature]:
	var result: Array[Creature] = []
	for creature in _creatures:
		if creature.dungeon_floor == dungeon_floor:
			result.append(creature)
	return result


## Adds up to [param count] creatures on random free tiles of
## [param dungeon_floor], never two on one tile. Returns those created, which is
## fewer than asked if the floor runs out of room.
##
## Tiles with floor are used first. Only once those run out do creatures go onto
## bare EMPTY ground — where they wait, unable to move, until the player places
## floor next to them.
func spawn(species: CreatureSpecies, dungeon_floor: DungeonFloor,
		count: int = 1) -> Array[Creature]:
	var on_floor: Array[Vector2i] = []
	var on_ground: Array[Vector2i] = []
	for position in dungeon_floor.get_positions():
		if not is_tile_free(dungeon_floor, position):
			continue
		if dungeon_floor.is_walkable(position):
			on_floor.append(position)
		else:
			on_ground.append(position)
	_shuffle(on_floor)
	_shuffle(on_ground)
	var free_tiles: Array[Vector2i] = on_floor + on_ground

	var spawned: Array[Creature] = []
	for i in mini(count, free_tiles.size()):
		var creature := Creature.new(_next_id, species, dungeon_floor, free_tiles[i],
			_rng.randf_range(0.0, species.initial_hunger_max))
		_next_id += 1
		creature.rest(_idle_duration(species))
		_creatures.append(creature)
		spawned.append(creature)
		creature_spawned.emit(creature)
	return spawned


## True if no creature on that floor stands on, or is stepping onto, the tile.
## [param ignore] excludes the creature asking.
func is_tile_free(dungeon_floor: DungeonFloor, position: Vector2i,
		ignore: Creature = null) -> bool:
	for other in _creatures:
		if other == ignore or other.dungeon_floor != dungeon_floor:
			continue
		if other.grid_position == position or other.move_target == position:
			return false
	return true


## True if [param creature] may step onto [param target] now: one orthogonal
## tile away, a walkable tile (one with floor placed) of ITS OWN floor, and
## unoccupied. Where the creature is standing does not matter, so a creature
## on bare ground can step onto floor placed beside it.
##
## Walkability is asked of the creature's floor, never of [Dungeon] — see
## [member Creature.dungeon_floor].
func can_move_to(creature: Creature, target: Vector2i) -> bool:
	if creature.is_moving():
		return false
	if not Creature.STEP_DIRECTIONS.has(target - creature.grid_position):
		return false
	if not creature.dungeon_floor.is_walkable(target):
		return false
	return is_tile_free(creature.dungeon_floor, target, creature)


## Starts a step if [method can_move_to] allows it.
func try_move(creature: Creature, target: Vector2i) -> bool:
	if not can_move_to(creature, target):
		return false
	return creature.start_move(target)


## Advances every creature by one simulation tick. Connected to
## [signal SimulationManager.simulation_tick], so it never runs while paused and
## runs proportionally more often at higher speeds.
func tick(delta: float) -> void:
	for creature in _creatures:
		if creature.advance(delta):
			creature.rest(_idle_duration(creature.species))
		elif creature.is_ready_to_move():
			_wander(creature)


## Steps to a random legal neighbour, or rests again if there is none.
func _wander(creature: Creature) -> void:
	var options: Array[Vector2i] = []
	for direction in Creature.STEP_DIRECTIONS:
		var target := creature.grid_position + direction
		if can_move_to(creature, target):
			options.append(target)
	if options.is_empty():
		creature.rest(_idle_duration(creature.species))
		return
	creature.start_move(options[_rng.randi_range(0, options.size() - 1)])


func _idle_duration(species: CreatureSpecies) -> float:
	return _rng.randf_range(species.idle_time_min, species.idle_time_max)


## Fisher-Yates with the seeded generator, so spawn positions are reproducible.
func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var held = items[i]
		items[i] = items[j]
		items[j] = held
