extends Node

## Calendar time for the dungeon world, derived from [SimulationManager].
##
## GameTime owns no clock of its own. It counts [signal SimulationManager.simulation_tick]
## emissions, so pause and speed are inherited for free: a paused simulation emits
## no ticks, and a 10x simulation emits ticks ten times as often.
##
## All state is a single integer tick counter and every accessor is integer
## arithmetic over it. Accumulating the float tick delta instead would let game
## time drift away from simulation time over a long run; counting ticks cannot.

## Script reference used only to read SimulationManager's constants at parse time.
## The running clock is the autoload singleton, not this.
const SimulationClock := preload("res://scripts/core/simulation_manager.gd")

## Simulation seconds in one game day. 1800 sim seconds = 30 real minutes at 1x.
const SIM_SECONDS_PER_DAY: int = 1800
## Days in a game year. No months or seasons yet.
const DAYS_PER_YEAR: int = 360
const GAME_HOURS_PER_DAY: int = 24
const GAME_MINUTES_PER_HOUR: int = 60
const GAME_MINUTES_PER_DAY: int = GAME_HOURS_PER_DAY * GAME_MINUTES_PER_HOUR

## 1800 * 20 = 36000 ticks per game day.
const TICKS_PER_DAY: int = SIM_SECONDS_PER_DAY * SimulationClock.TICKS_PER_SECOND
## 36000 / 1440 = 25 ticks per game minute. Exact, so HH:MM never rounds.
const TICKS_PER_GAME_MINUTE: int = TICKS_PER_DAY / GAME_MINUTES_PER_DAY

## Ticks of game time elapsed since Year 1, Day 1, 00:00.
var _ticks: int = 0


func _ready() -> void:
	SimulationManager.simulation_tick.connect(_on_simulation_tick)


## Current year, starting at 1.
func get_year() -> int:
	return get_total_days() / DAYS_PER_YEAR + 1


## Day within the current year, 1 to [constant DAYS_PER_YEAR].
func get_day() -> int:
	return get_total_days() % DAYS_PER_YEAR + 1


## Alias of [method get_day]. Without months, the day of the year is the day.
func get_day_of_year() -> int:
	return get_day()


## Whole game days completed since the start. 0 during Year 1, Day 1.
func get_total_days() -> int:
	return _ticks / TICKS_PER_DAY


## Simulation seconds elapsed within the current day, 0.0 up to (not including)
## [constant SIM_SECONDS_PER_DAY].
func get_time_of_day_seconds() -> float:
	return (_ticks % TICKS_PER_DAY) * SimulationClock.TICK_DELTA


## Hour of the current day, 0 to 23.
func get_hour() -> int:
	return _get_minute_of_day() / GAME_MINUTES_PER_HOUR


## Minute of the current hour, 0 to 59.
func get_minute() -> int:
	return _get_minute_of_day() % GAME_MINUTES_PER_HOUR


## Wall-clock time of day as "HH:MM" on a 24-hour clock.
func get_time_string() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


func _get_minute_of_day() -> int:
	return (_ticks % TICKS_PER_DAY) / TICKS_PER_GAME_MINUTE


func _on_simulation_tick(_delta: float) -> void:
	_ticks += 1
