class_name Creature
extends RefCounted

## One living creature: pure simulation data.
##
## Never draws itself, never reads the clock, never decides where to go. It is
## advanced by [CreatureSystem] once per simulation tick and told where to move;
## everything here is a function of the delta it is handed, so pause and speed
## are inherited from the simulation rather than implemented.

## The creature's observable state.
##
## IDLE and WANDER describe what it is doing. HUNGRY describes what it needs and
## takes priority when true. With no food system yet, a hungry creature still
## wanders — HUNGRY is reported, not acted on. It becomes a behaviour state once
## there is something to go and eat.
enum State {
	IDLE,
	WANDER,
	HUNGRY,
}

const MAX_HUNGER: float = 100.0
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

var health: float
## 0 = sated, [constant MAX_HUNGER] = starving.
var hunger: float = 0.0
## Simulation seconds alive.
var age: float = 0.0
var state: State = State.IDLE

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


## True once the rest period is over and the creature is standing still.
func is_ready_to_move() -> bool:
	return not is_moving() and _idle_remaining <= _TIME_EPSILON


## Rest on the current tile for [param duration] simulation seconds.
func rest(duration: float) -> void:
	_idle_remaining = maxf(duration, 0.0)
	_refresh_state()


## Begins a one-tile step. Refuses anything that is not exactly one orthogonal
## tile away, or a new step while one is in progress — the model itself will not
## teleport or move diagonally, whoever asks. Whether the tile is walkable is
## checked by the caller, which knows about the world.
func start_move(target: Vector2i) -> bool:
	if is_moving():
		return false
	if not STEP_DIRECTIONS.has(target - grid_position):
		return false
	facing = target - grid_position
	move_target = target
	move_progress = 0.0
	_refresh_state()
	return true


## Advances the creature by [param delta] simulation seconds. Returns true on
## the tick it finishes stepping onto a new tile.
func advance(delta: float) -> bool:
	age += delta
	hunger = minf(hunger + species.hunger_rate * delta, MAX_HUNGER)

	var arrived := false
	if is_moving():
		move_progress += delta / species.move_duration
		if move_progress >= 1.0 - _TIME_EPSILON:
			grid_position = move_target
			move_progress = 0.0
			arrived = true
	else:
		_idle_remaining -= delta

	_refresh_state()
	return arrived


func _refresh_state() -> void:
	if is_hungry():
		state = State.HUNGRY
	elif is_moving():
		state = State.WANDER
	else:
		state = State.IDLE
