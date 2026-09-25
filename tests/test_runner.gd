extends Node

## Runs every suite in order and exits non-zero if anything failed.
##
##   godot --headless --path . res://tests/test_runner.tscn
##   godot --headless --path . res://tests/test_runner.tscn -- --verbose
##   godot --headless --path . res://tests/test_runner.tscn -- --only=system_2
##
## Order matters: the suites share the SimulationManager and GameTime autoloads,
## and System 0 checks their starting values, so it runs first. The simulation
## is held paused between suites so real frames cannot advance it behind a
## test's back; suites that need live time resume it themselves.

const SUITES: Array[String] = [
	"res://tests/test_system_0_simulation.gd",
	"res://tests/test_system_1_grid.gd",
	"res://tests/test_system_1_1_tile_expansion.gd",
	"res://tests/test_system_1_2_floor_expansion.gd",
	"res://tests/test_system_2_creatures.gd",
	"res://tests/test_system_3_food.gd",
	"res://tests/test_system_4_pee.gd",
	"res://tests/test_system_5_water.gd",
	"res://tests/test_system_6_camera.gd",
]


func _ready() -> void:
	SimulationManager.pause()
	var args := OS.get_cmdline_user_args()
	var verbose := args.has("--verbose")
	var only := ""
	for arg in args:
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var total_passed := 0
	var total_failed := 0
	var started := Time.get_ticks_msec()

	var ran := 0
	for path in SUITES:
		if only != "" and not path.contains(only):
			continue
		ran += 1
		var script: GDScript = load(path)
		# A script with a parse error still loads, it just cannot be instantiated.
		if script == null or not script.can_instantiate():
			print("
%s
    FAIL suite failed to load (see parse errors above)" % path)
			total_failed += 1
			continue
		var suite = script.new()
		suite.tree = get_tree()
		suite.verbose = verbose
		print("\n%s" % suite.title)
		await suite.run()
		SimulationManager.set_speed(1.0)
		SimulationManager.pause()
		print("  %d passed, %d failed" % [suite.passed, suite.failed])
		total_passed += suite.passed
		total_failed += suite.failed

	print("\n==== %s: %d passed, %d failed, %d suites, %.1fs ====\n" % [
		"ALL PASS" if total_failed == 0 else "FAILURES",
		total_passed, total_failed, ran,
		(Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(0 if total_failed == 0 else 1)
