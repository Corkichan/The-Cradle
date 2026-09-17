extends "res://tests/test_suite.gd"


func _init() -> void:
	title = "System 0 / 0.2 - Simulation Core and Game Time"


func run() -> void:
	section("constants")
	check("TICKS_PER_SECOND", SimulationManager.TICKS_PER_SECOND, 20)
	check_approx("TICK_DELTA", SimulationManager.TICK_DELTA, 0.05, 1e-9)
	check("speeds", SimulationManager.SPEEDS, [1.0, 2.0, 5.0, 10.0])
	check("GameTime TICKS_PER_DAY", GameTime.TICKS_PER_DAY, 36000)
	check("GameTime TICKS_PER_GAME_MINUTE", GameTime.TICKS_PER_GAME_MINUTE, 25)

	section("starting state")
	check("tick_count starts at 0", SimulationManager.tick_count, 0)
	check("game time starts Y1 D1 00:00", _clock(), "Y1 D1 00:00")
	check("total days 0", GameTime.get_total_days(), 0)

	section("manual stepping and time of day mapping")
	for pair in [[75, "01:00"], [375, "05:00"], [450, "06:00"],
			[900, "12:00"], [1350, "18:00"], [1725, "23:00"], [1799, "23:59"]]:
		_goto(pair[0])
		check("%d sim s -> %s" % [pair[0], pair[1]], GameTime.get_time_string(), pair[1])
		if pair[0] == 75:
			check("step() advanced exactly 1500 ticks", SimulationManager.tick_count, 1500)
			check_approx("= 75 sim seconds", SimulationManager.get_simulation_time(), 75.0, 1e-9)

	section("day rollover")
	_goto(1799.95)
	check("last tick of day 1", _clock(), "Y1 D1 23:59")
	_goto(1800)
	check("first tick of day 2", _clock(), "Y1 D2 00:00")
	check("total days 1", GameTime.get_total_days(), 1)

	section("year rollover")
	_goto(359 * 1800 + 1799.95)
	check("last tick of year 1", _clock(), "Y1 D360 23:59")
	_goto(360 * 1800)
	check("first tick of year 2", _clock(), "Y2 D1 00:00")
	check("total days 360", GameTime.get_total_days(), 360)

	section("pause")
	SimulationManager.resume()
	SimulationManager.pause()
	var before := SimulationManager.tick_count
	await real_seconds(0.4)
	check("no ticks while paused", SimulationManager.tick_count - before, 0)

	section("frame-rate independent live rate")
	SimulationManager.set_speed(1.0)
	var rate_1x := await _measure_tick_rate(1.0)
	check_between("~20 ticks/s at 1x", rate_1x, 18.0, 22.0)
	SimulationManager.set_speed(10.0)
	var rate_10x := await _measure_tick_rate(1.0)
	check_between("~200 ticks/s at 10x", rate_10x, 185.0, 215.0)
	SimulationManager.set_speed(1.0)


func _measure_tick_rate(seconds: float) -> float:
	SimulationManager.resume()
	await frames(2)
	var start_ticks := SimulationManager.tick_count
	var start := Time.get_ticks_usec()
	await real_seconds(seconds)
	var rate := (SimulationManager.tick_count - start_ticks) / elapsed_since(start)
	SimulationManager.pause()
	return rate


## Steps forward to an absolute simulation time. Time cannot run backwards, so
## asking for the past is a bug in the test and is reported as one.
func _goto(sim_seconds: float) -> void:
	var target := int(round(sim_seconds * SimulationManager.TICKS_PER_SECOND))
	if target < SimulationManager.tick_count:
		check("test tried to step backwards to %.2f s" % sim_seconds, false, true)
		return
	SimulationManager.step(target - SimulationManager.tick_count)


func _clock() -> String:
	return "Y%d D%d %s" % [GameTime.get_year(), GameTime.get_day(), GameTime.get_time_string()]
