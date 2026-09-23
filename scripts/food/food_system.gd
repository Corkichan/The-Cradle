class_name FoodSystem
extends RefCounted

## Owns every food source in the world and answers "what food is near here".
##
## Food has no behaviour of its own — it does not tick, decay or grow. This class
## exists so food lives in the WORLD rather than inside any creature, and so any
## future eater can ask the same questions.

signal food_placed(food: FoodSource)
## Emitted after a source is used up. It has already been removed.
signal food_depleted(food: FoodSource)

var _sources: Array[FoodSource] = []
var _next_id: int = 1
var _rng: RandomNumberGenerator


## [param rng_seed] makes random placement reproducible, for tests.
func _init(rng_seed: int = -1) -> void:
	_rng = RandomNumberGenerator.new()
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


func get_sources() -> Array[FoodSource]:
	return _sources


func get_count() -> int:
	return _sources.size()


func get_sources_on(dungeon_floor: DungeonFloor) -> Array[FoodSource]:
	var result: Array[FoodSource] = []
	for food in _sources:
		if food.dungeon_floor == dungeon_floor:
			result.append(food)
	return result


## The food on that exact tile, or null.
func at(dungeon_floor: DungeonFloor, position: Vector2i) -> FoodSource:
	for food in _sources:
		if food.dungeon_floor == dungeon_floor and food.grid_position == position:
			return food
	return null


func has(food: FoodSource) -> bool:
	return _sources.has(food)


## True if food may be put here: a tile that exists and has floor, with no food
## already on it.
##
## [param occupants] is passed in rather than stored, so food never holds a
## reference back to creatures — the dependency only points one way, and two
## RefCounted systems pointing at each other would never be freed.
func can_place_at(dungeon_floor: DungeonFloor, position: Vector2i,
		occupants: CreatureSystem = null) -> bool:
	if not dungeon_floor.is_walkable(position):
		return false
	if at(dungeon_floor, position) != null:
		return false
	if occupants != null and not occupants.is_tile_free(dungeon_floor, position):
		return false
	return true


## Puts food on a tile, or returns null if [method can_place_at] refuses.
func place(dungeon_floor: DungeonFloor, position: Vector2i,
		amount: float = FoodSource.DEFAULT_AMOUNT,
		nutrition: float = FoodSource.DEFAULT_NUTRITION,
		occupants: CreatureSystem = null,
		kind: FoodSource.Kind = FoodSource.Kind.FOOD) -> FoodSource:
	if not can_place_at(dungeon_floor, position, occupants):
		return null
	var food := FoodSource.new(_next_id, dungeon_floor, position, amount, nutrition, kind)
	_next_id += 1
	_sources.append(food)
	food_placed.emit(food)
	return food


## Scatters up to [param count] sources on random valid tiles. Returns those
## placed, which is fewer than asked when the floor has no room — including none
## at all on a dungeon where no floor has been built yet.
func place_random(dungeon_floor: DungeonFloor, count: int = 1,
		amount: float = FoodSource.DEFAULT_AMOUNT,
		nutrition: float = FoodSource.DEFAULT_NUTRITION,
		occupants: CreatureSystem = null,
		kind: FoodSource.Kind = FoodSource.Kind.FOOD) -> Array[FoodSource]:
	var candidates: Array[Vector2i] = []
	for position in dungeon_floor.get_positions():
		if can_place_at(dungeon_floor, position, occupants):
			candidates.append(position)
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var held := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = held

	var placed: Array[FoodSource] = []
	for i in mini(count, candidates.size()):
		var food := place(dungeon_floor, candidates[i], amount, nutrition, occupants, kind)
		if food != null:
			placed.append(food)
	return placed


## Nearest food within [param radius] tiles of [param from], measured in steps
## (Manhattan), on that floor only. Null when nothing is close enough — a
## creature is not told about food it could not plausibly notice.
##
## Ties go to the lowest id, so the same creature in the same situation always
## picks the same pile.
func find_nearest(dungeon_floor: DungeonFloor, from: Vector2i, radius: int,
		kind: FoodSource.Kind = FoodSource.Kind.FOOD) -> FoodSource:
	var best: FoodSource = null
	var best_distance := 0
	for food in _sources:
		if food.kind != kind or food.dungeon_floor != dungeon_floor or food.is_depleted():
			continue
		var distance: int = absi(food.grid_position.x - from.x) \
			+ absi(food.grid_position.y - from.y)
		# The radius is enforced here and nowhere else. Seeding best_distance with
		# radius + 1 would enforce it a second time, and a rule kept in two places
		# is a rule no test can prove you still have.
		if distance > radius:
			continue
		if best == null or distance < best_distance \
				or (distance == best_distance and food.id < best.id):
			best = food
			best_distance = distance
	return best


## Takes a source out of the world and announces it.
func remove(food: FoodSource) -> void:
	if not _sources.has(food):
		return
	_sources.erase(food)
	food_depleted.emit(food)
