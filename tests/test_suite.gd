extends RefCounted

## Base for a test suite. Deliberately tiny: checks, a tally, and ways to wait.
##
## A suite overrides [member title] and [method run]. [method run] may await, so
## suites that need real frames (pause, speed) work the same as the rest.

var title: String = "unnamed suite"
var tree: SceneTree
var verbose: bool = false
var passed: int = 0
var failed: int = 0


## Override. May await.
func run() -> void:
	pass


func section(heading: String) -> void:
	if verbose:
		print("  -- %s" % heading)


## Equality, comparing by value when the types match and by printed form
## otherwise (so an int 5 and a float 5.0 compare equal).
func check(label: String, got, want) -> void:
	var ok: bool
	if typeof(got) == typeof(want):
		ok = got == want
	else:
		ok = str(got) == str(want)
	_record(label, ok, "got=%s want=%s" % [got, want])


func check_true(label: String, value: bool) -> void:
	_record(label, value, "expected true")


func check_false(label: String, value: bool) -> void:
	_record(label, not value, "expected false")


func check_approx(label: String, got: float, want: float, tolerance: float) -> void:
	_record(label, absf(got - want) <= tolerance,
		"got=%.4f want=%.4f +/-%.4f" % [got, want, tolerance])


func check_between(label: String, got: float, low: float, high: float) -> void:
	_record(label, got >= low and got <= high,
		"got=%.4f want [%.4f, %.4f]" % [got, low, high])


func frames(count: int) -> void:
	for i in count:
		await tree.process_frame


## Waits real wall-clock time, letting frames (and so simulation ticks) run.
func real_seconds(seconds: float) -> void:
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < int(seconds * 1_000_000.0):
		await tree.process_frame


## Real seconds elapsed since [param start_usec], for rate measurements.
func elapsed_since(start_usec: int) -> float:
	return (Time.get_ticks_usec() - start_usec) / 1_000_000.0


func _record(label: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
		if verbose:
			print("    PASS %s" % label)
	else:
		failed += 1
		print("    FAIL %s  (%s)" % [label, detail])
