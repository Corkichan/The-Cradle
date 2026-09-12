extends Node2D

## Temporary harness for verifying System 0 (SimulationManager) and
## System 0.2 (GameTime).
## Delete this script and its node assignment once real gameplay exists.

var _label: Label
var _ticks_last_second: int = 0
var _tick_mark: int = 0
var _real_second: float = 0.0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 20)
	add_child(_label)

	SimulationManager.simulation_tick.connect(_on_simulation_tick)
	SimulationManager.paused_changed.connect(func(p): print("paused -> ", p))
	SimulationManager.speed_changed.connect(func(s): print("speed -> ", s, "x"))


func _on_simulation_tick(_delta: float) -> void:
	pass # Real systems do work here. The harness only counts ticks.


func _process(delta: float) -> void:
	# Measure ticks per REAL second. This is the number that proves
	# the simulation is independent from the render frame rate.
	_real_second += delta
	if _real_second >= 1.0:
		_real_second -= 1.0
		_ticks_last_second = SimulationManager.tick_count - _tick_mark
		_tick_mark = SimulationManager.tick_count

	var expected := SimulationManager.TICKS_PER_SECOND * SimulationManager.get_speed()
	_label.text = "\n".join([
		"Year %d   Day %d   %s" % [
			GameTime.get_year(), GameTime.get_day(), GameTime.get_time_string()],
		"total days %8d" % GameTime.get_total_days(),
		"",
		"sim time   %8.2f s" % SimulationManager.get_simulation_time(),
		"ticks      %8d" % SimulationManager.tick_count,
		"ticks/sec  %8d   (expected %d)" % [_ticks_last_second, expected],
		"",
		"render fps %8d   (cap %s)" % [
			Engine.get_frames_per_second(),
			"none" if Engine.max_fps == 0 else str(Engine.max_fps),
		],
		"speed      %8sx" % SimulationManager.get_speed(),
		"paused     %8s" % SimulationManager.is_paused(),
		"",
		"[space] pause/resume   [1..4] speed 1/2/5/10x",
		"[F1] cap 10 fps  [F2] cap 30  [F3] uncapped",
		"[right] single step while paused",
	])


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match event.keycode:
		KEY_SPACE:
			SimulationManager.set_paused(not SimulationManager.is_paused())
		KEY_1:
			SimulationManager.set_speed_index(0)
		KEY_2:
			SimulationManager.set_speed_index(1)
		KEY_3:
			SimulationManager.set_speed_index(2)
		KEY_4:
			SimulationManager.set_speed_index(3)
		KEY_F1:
			Engine.max_fps = 10
		KEY_F2:
			Engine.max_fps = 30
		KEY_F3:
			Engine.max_fps = 0
		KEY_RIGHT:
			SimulationManager.step()
