extends Node

## Fixed-step simulation clock for The Cradle.
##
## Gameplay systems must never run off render frames. They connect to
## [signal simulation_tick] and receive a constant [constant TICK_DELTA]
## regardless of how fast (or slow) the game is rendering.

## Emitted once per simulation tick. [param delta] is always [constant TICK_DELTA].
signal simulation_tick(delta: float)
## Emitted when the simulation is paused or resumed.
signal paused_changed(paused: bool)
## Emitted when the simulation speed multiplier changes.
signal speed_changed(speed: float)

## Simulation ticks per second of real time at 1x speed.
const TICKS_PER_SECOND: int = 20
## Simulation seconds that elapse per tick.
const TICK_DELTA: float = 1.0 / TICKS_PER_SECOND
## Selectable speed multipliers.
const SPEEDS: Array[float] = [1.0, 2.0, 5.0, 10.0]
## Safety cap so a long frame hitch cannot trigger a death spiral of catch-up ticks.
const MAX_TICKS_PER_FRAME: int = 100

## Number of ticks simulated since startup.
var tick_count: int = 0

var _paused: bool = false
var _speed: float = SPEEDS[0]
var _accumulator: float = 0.0


func _ready() -> void:
	# Keep ticking even if the SceneTree itself is paused; pausing the
	# simulation is this node's own concern.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _paused:
		return

	_accumulator += delta * _speed

	var ticks: int = int(_accumulator / TICK_DELTA)
	if ticks > MAX_TICKS_PER_FRAME:
		# Drop the backlog we cannot afford to simulate this frame.
		ticks = MAX_TICKS_PER_FRAME
		_accumulator = 0.0
	else:
		_accumulator -= ticks * TICK_DELTA

	for _i in ticks:
		_tick()


## Simulation time in seconds since startup. Derived from [member tick_count],
## so it never drifts.
func get_simulation_time() -> float:
	return tick_count * TICK_DELTA


func is_paused() -> bool:
	return _paused


func pause() -> void:
	if _paused:
		return
	_paused = true
	paused_changed.emit(true)


func resume() -> void:
	if not _paused:
		return
	_paused = false
	# Discard time that accrued while paused.
	_accumulator = 0.0
	paused_changed.emit(false)


func set_paused(paused: bool) -> void:
	if paused:
		pause()
	else:
		resume()


func get_speed() -> float:
	return _speed


## Sets the speed multiplier. [param speed] should be one of [constant SPEEDS].
func set_speed(speed: float) -> void:
	if is_equal_approx(speed, _speed):
		return
	_speed = speed
	speed_changed.emit(_speed)


## Sets the speed by its index in [constant SPEEDS].
func set_speed_index(index: int) -> void:
	set_speed(SPEEDS[clampi(index, 0, SPEEDS.size() - 1)])


## Advances the simulation manually, ignoring pause state. Intended for
## step-debugging and tests.
func step(ticks: int = 1) -> void:
	for _i in ticks:
		_tick()


func _tick() -> void:
	tick_count += 1
	simulation_tick.emit(TICK_DELTA)
