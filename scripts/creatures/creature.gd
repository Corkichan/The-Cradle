class_name Creature
extends RefCounted

## One living creature: pure simulation data.
##
## Never draws itself, never reads the clock, never decides where to go. It is
## advanced by [CreatureSystem] once per simulation tick and told where to move;
## everything here is a function of the delta it is handed, so pause and speed
## are inherited from the simulation rather than implemented.

## The creature's observable state, most important first.
##
## DEAD and SLEEP describe whether it can act at all. EAT and SEEK_FOOD follow
## from [member intent]. HUNGRY means it wants food but knows of none within
## range, so it carries on wandering. IDLE and WANDER describe what it is doing.
enum State {
	IDLE,
	WANDER,
	HUNGRY,
	SEEK_FOOD,
	EAT,
	THIRSTY,
	SEEK_WATER,
	DRINK,
	SLEEP,
	DEAD,
}

## What the creature is trying to do. Chosen by [CreatureBehaviour], where
## [member state] is derived from it and from conditions like sleep and death —
## intent is the decision, state is what you see.
enum Intent {
	WANDER,
	SEEK_FOOD,
	EAT,
	SEEK_WATER,
	DRINK,
}

## Hunger at which a creature starves to death.
const MAX_HUNGER: float = 100.0
## Full hydration. There is no death from thirst yet.
const MAX_HYDRATION: float = 100.0
## Slack for comparing accumulated time. 0.05 is not exact in binary, so ten
## ticks of a 0.5 s step sum to 0.9999999999999999, not 1.0 — without this every
## step and every rest would overrun by a whole tick.
const _TIME_EPSILON: float = 1e-6

## The four ways a creature may step. No diagonals.
const STEP_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
]

var id: int
var species: CreatureSpecies
## The floor this creature lives on. Held directly, NOT reached through
## [Dungeon], because Dungeon's queries answer for whichever floor is being
## viewed — a creature must keep obeying its own floor when the player looks
## elsewhere.
var dungeon_floor: DungeonFloor

## Tile the creature occupies. While stepping, this is the tile it is leaving.
var grid_position: Vector2i
## Tile being stepped onto. Equal to [member grid_position] when not moving.
var move_target: Vector2i
## 0..1 across the current step; 0 when not moving.
var move_progress: float = 0.0
## Direction of the most recent step.
var facing: Vector2i = Vector2i.LEFT
## Tiles still to walk before resting. A creature crosses several tiles in one
## trip rather than stopping after every single one.
var trip_steps_left: int = 0

var health: float
## 0 = sated, [constant MAX_HUNGER] = starved to death.
var hunger: float = 0.0
## Simulation seconds alive.
var age: float = 0.0
var state: State = State.IDLE
var intent: Intent = Intent.WANDER
## The food this creature is heading for, or null. A REFERENCE to a source that
## lives in the world; the creature never owns or carries food.
var food_target: FoodSource = null
## The water this creature is heading for, or null. Also a reference to a source
## that lives in the world.
var water_target: FoodSource = null
## [constant MAX_HYDRATION] when fully watered, 0 when dry.
var hydration: float = MAX_HYDRATION
## Water the body has used and not yet passed. Filled ONLY by hydration actually
## spent, so a creature that has never drunk cannot urinate. Capped at the
## species' capacity, so a long sleep leaves one puddle owed, not a burst.
var bladder: float = 0.0
## False once starved. A dead creature is removed by [CreatureSystem].
var alive: bool = true
## True during its species' sleeping hours. It finishes any step in progress and
## then stays put until it wakes.
var asleep: bool = false

var _idle_remaining: float = 0.0


func _init(p_id: int, p_species: CreatureSpecies, p_floor: DungeonFloor,
		p_position: Vector2i, p_hunger: float = 0.0) -> void:
	id = p_id
	species = p_species
	dungeon_floor = p_floor
	grid_position = p_position
	move_target = p_position
	health = species.max_health
	hunger = clampf(p_hunger, 0.0, MAX_HUNGER)
	_refresh_state()


func get_species_name() -> String:
	return species.species_name


func get_variant_name() -> String:
	return species.variant_name


func is_moving() -> bool:
	return move_target != grid_position


func is_hungry() -> bool:
	return hunger >= species.hungry_threshold


## True while the creature would go out of its way for food.
##
## Hysteresis on purpose: it starts caring at [member CreatureSpecies.hungry_threshold]
## and does not stop until hunger falls to [member CreatureSpecies.sated_threshold],
## so one mouthful does not make it abandon a meal.
func wants_food() -> bool:
	if intent == Intent.WANDER:
		return is_hungry()
	return hunger > species.sated_threshold


## Sets what the creature is trying to do, and refreshes what it shows.
func set_intent(value: Intent) -> void:
	intent = value
	_refresh_state()


func forget_food_target() -> void:
	food_target = null


## Eats [param nutrition] worth of food. Hunger never goes below zero.
func feed(nutrition: float) -> void:
	hunger = maxf(hunger - maxf(nutrition, 0.0), 0.0)
	_refresh_state()


## True when the bladder is full enough to need emptying. Never while asleep or
## dead, whoever asks — a sleeping creature holds it until morning.
func is_urination_due() -> bool:
	return alive and not asleep and bladder >= species.bladder_capacity - _TIME_EPSILON


## Called after urinating.
func empty_bladder() -> void:
	bladder = maxf(bladder - species.bladder_capacity, 0.0)


func is_thirsty() -> bool:
	return hydration <= species.thirsty_threshold


## True while the creature would go out of its way for water. Same hysteresis as
## hunger: it starts caring when thirsty and stops only when nearly full.
func wants_water() -> bool:
	if intent == Intent.SEEK_WATER or intent == Intent.DRINK:
		return hydration < species.sated_hydration
	return is_thirsty()


func forget_water_target() -> void:
	water_target = null


## Drinks one serving. Hydration never goes past full. Note this does NOT fill
## the bladder: that happens later, as the body spends the water.
func drink(amount: float) -> void:
	hydration = minf(hydration + maxf(amount, 0.0), MAX_HYDRATION)
	_refresh_state()


## True once the rest period is over and the creature is awake, alive and still.
func is_ready_to_move() -> bool:
	return alive and not asleep and not is_moving() and _idle_remaining <= _TIME_EPSILON


## Rest on the current tile for [param duration] simulation seconds, ending any
## trip in progress.
func rest(duration: float) -> void:
	trip_steps_left = 0
	_idle_remaining = maxf(duration, 0.0)
	_refresh_state()


## Sets out on a walk of [param steps] tiles.
func begin_trip(steps: int) -> void:
	trip_steps_left = maxi(steps, 0)


func has_steps_left() -> bool:
	return trip_steps_left > 0


## Begins a one-tile step and counts it against the current trip. Refuses
## anything that is not exactly one orthogonal tile away, a new step while one is
## in progress, or any movement at all while asleep or dead — the model itself
## will not teleport or move diagonally, whoever asks. Whether the tile is
## walkable is checked by the caller, which knows about the world.
func start_move(target: Vector2i) -> bool:
	if not alive or asleep or is_moving():
		return false
	if not STEP_DIRECTIONS.has(target - grid_position):
		return false
	facing = target - grid_position
	move_target = target
	move_progress = 0.0
	trip_steps_left = maxi(trip_steps_left - 1, 0)
	_refresh_state()
	return true


## Advances the creature by [param delta] simulation seconds, with the game's
## current hour so it knows whether it should be asleep. Returns true on the tick
## it finishes stepping onto a new tile.
func advance(delta: float, hour_of_day: int) -> bool:
	if not alive:
		return false

	age += delta
	hunger = minf(hunger + species.hunger_rate * delta, MAX_HUNGER)
	if hunger >= MAX_HUNGER:
		_starve()
		return false

	asleep = species.is_sleep_hour(hour_of_day)

	# Water leaves the body at a steady rate and becomes urine. Run dry and
	# nothing leaves, so nothing collects: without drinking there is no pee.
	# The body keeps working while asleep; only the act is blocked, and the cap
	# means a long night leaves one puddle owed rather than a dozen.
	var spent := minf(species.hydration_rate * delta, hydration)
	hydration -= spent
	bladder = minf(bladder + spent, species.bladder_capacity)

	var arrived := false
	if is_moving():
		# A step already under way finishes even if sleep just began, so the
		# creature always comes to rest on a tile rather than between two.
		move_progress += delta / species.move_duration
		if move_progress >= 1.0 - _TIME_EPSILON:
			grid_position = move_target
			move_progress = 0.0
			arrived = true
	elif not asleep:
		_idle_remaining -= delta

	_refresh_state()
	return arrived


func _starve() -> void:
	alive = false
	asleep = false
	intent = Intent.WANDER
	food_target = null
	water_target = null
	bladder = 0.0
	health = 0.0
	hunger = MAX_HUNGER
	trip_steps_left = 0
	move_target = grid_position
	move_progress = 0.0
	state = State.DEAD


func _refresh_state() -> void:
	if not alive:
		state = State.DEAD
	elif asleep:
		state = State.SLEEP
	elif intent == Intent.DRINK:
		state = State.DRINK
	elif intent == Intent.SEEK_WATER:
		state = State.SEEK_WATER
	elif intent == Intent.EAT:
		state = State.EAT
	elif intent == Intent.SEEK_FOOD:
		state = State.SEEK_FOOD
	elif is_thirsty():
		state = State.THIRSTY
	elif is_hungry():
		state = State.HUNGRY
	elif is_moving():
		state = State.WANDER
	else:
		state = State.IDLE
