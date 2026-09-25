extends "res://tests/test_suite.gd"

## The camera is presentation, so most of it is judged by eye. What is tested
## here is the part that is NOT a matter of taste: that changing how the world
## is shown never changes where anything is.

## A world that is deliberately not 8x5 and does not start at the origin, so a
## dimension hardcoded anywhere in the rig would show up as a wrong answer.
const ODD_BOUNDS := Rect2(-96.0, 64.0, 416.0, 224.0)


func _init() -> void:
	title = "System 6 - Camera and view modes"


func run() -> void:
	# The runner is still building its own children on the first call, and a
	# camera has to be in a tree to know how big the screen is.
	await frames(1)
	await _test_round_trip_is_view_independent()
	await _test_screen_and_world_are_inverses()
	await _test_bounds_come_from_outside()
	await _test_zoom_limits_and_anchoring()
	await _test_edge_push_ramp()
	await _test_transition_is_a_move_not_a_cut()
	await _test_main_scene_switches_without_resetting()
	await _test_following()
	await _test_building_is_build_view_only()


# --------------------------------------------------------------------------

func _rig(bounds: Rect2 = Rect2(0.0, 0.0, 256.0, 160.0)) -> CameraRig:
	var rig := CameraRig.new()
	tree.root.add_child(rig)
	# Edge scrolling follows the real cursor, which sits at (0, 0) in a headless
	# run — hard against the corner. Left on, every test below would be measuring
	# a camera that is quietly scrolling away. It gets its own test instead.
	rig.edge_scroll_enabled = false
	# Made current so the viewport's own transform can be compared against the
	# rig's arithmetic — otherwise the two could disagree and no test would know.
	rig.make_current()
	rig.world_bounds = bounds
	rig.reset_view(true)
	return rig


func _drop(rig: CameraRig) -> void:
	tree.root.remove_child(rig)
	rig.queue_free()


func _centre_of(grid_position: Vector2i) -> Vector2:
	return Vector2(grid_position) * Dungeon.TILE_SIZE \
		+ Vector2.ONE * (Dungeon.TILE_SIZE / 2.0)


## A real left click, fed to the real handler. Calling the drag helpers direct
## would walk straight past the gate this is here to test.
func _click(main: Node, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	main._unhandled_input(event)


func _grid_at(rig: CameraRig, screen_position: Vector2) -> Vector2i:
	var world := rig.screen_to_world(screen_position)
	return Vector2i(floori(world.x / Dungeon.TILE_SIZE),
		floori(world.y / Dungeon.TILE_SIZE))


# --------------------------------------------------------------------------

## The point of the whole exercise: (4, 2) is the same tile in both views.
func _test_round_trip_is_view_independent() -> void:
	section("6-1 a tile is the same tile in every view")
	var rig := _rig()

	var probes: Array[Vector2i] = [
		Vector2i(4, 2), Vector2i(0, 0), Vector2i(7, 4), Vector2i(3, 0),
	]
	var screens: Dictionary = {}

	rig.set_view(CameraRig.View.GAMEPLAY, true)
	await frames(1)
	check("gameplay view is angled", rig.get_tilt() < 1.0, true)
	for probe in probes:
		var screen := rig.world_to_screen(_centre_of(probe))
		screens[probe] = screen
		check("gameplay: %s survives the round trip" % probe,
			_grid_at(rig, screen), probe)

	rig.set_view(CameraRig.View.BUILD, true)
	await frames(1)
	check("build view is straight down", rig.get_tilt(), 1.0)
	for probe in probes:
		check("build: %s survives the round trip" % probe,
			_grid_at(rig, rig.world_to_screen(_centre_of(probe))), probe)

	section("and the screen pixel it lives on has genuinely moved")
	# If the two views drew identically this whole exercise would be pointless,
	# so prove the presentation really did change while the coordinate did not.
	var moved := false
	for probe in probes:
		if not rig.world_to_screen(_centre_of(probe)).is_equal_approx(screens[probe]):
			moved = true
	check_true("the same tile is drawn somewhere else", moved)

	section("the world coordinate of a tile never depended on the view at all")
	var dungeon := Dungeon.new()
	check("dungeon still answers for (4,2)", dungeon.grid_to_world_center(Vector2i(4, 2)),
		_centre_of(Vector2i(4, 2)))
	check("and converts back", dungeon.world_to_grid(_centre_of(Vector2i(4, 2))),
		Vector2i(4, 2))
	_drop(rig)


func _test_screen_and_world_are_inverses() -> void:
	section("6-2 screen and world conversions undo each other at any angle")
	var rig := _rig()
	for view in [CameraRig.View.GAMEPLAY, CameraRig.View.BUILD]:
		rig.set_view(view, true)
		await frames(1)
		for point in [Vector2(0.0, 0.0), Vector2(128.0, 80.0), Vector2(-40.0, 200.0)]:
			var back := rig.screen_to_world(rig.world_to_screen(point))
			check_approx("view %d: %s -> screen -> world x" % [view, point],
				back.x, point.x, 0.01)
			check_approx("view %d: %s -> screen -> world y" % [view, point],
				back.y, point.y, 0.01)

		section("and the camera itself agrees with the arithmetic")
		# The conversions above are computed from the rig's own state rather than
		# read back off the camera, so without this they could be self-consistent
		# and still describe a camera that is somewhere else entirely.
		await frames(2)
		var canvas := rig.get_viewport().get_canvas_transform()
		for point in [Vector2(0.0, 0.0), Vector2(200.0, 120.0)]:
			# The world node carries the squash in the real scene, so it is
			# applied here before handing the point to the canvas.
			var drawn_at: Vector2 = canvas * Vector2(point.x, point.y * rig.get_tilt())
			var predicted := rig.world_to_screen(point)
			check_approx("view %d: %s is drawn where the rig says (x)" % [view, point],
				drawn_at.x, predicted.x, 1.0)
			check_approx("view %d: %s is drawn where the rig says (y)" % [view, point],
				drawn_at.y, predicted.y, 1.0)
	_drop(rig)


func _test_bounds_come_from_outside() -> void:
	section("6-3 the camera is told the world's shape, it does not assume one")
	var rig := _rig(ODD_BOUNDS)
	await frames(2)
	check("it kept the rectangle it was given", rig.world_bounds, ODD_BOUNDS)

	section("framing centres on those bounds, wherever they are")
	var centre_screen := rig.world_to_screen(ODD_BOUNDS.get_center())
	var anchor := Vector2(rig.view_margins.x, rig.view_margins.y) + Vector2(
		(rig.get_viewport_rect().size.x - rig.view_margins.x - rig.view_margins.z) / 2.0,
		(rig.get_viewport_rect().size.y - rig.view_margins.y - rig.view_margins.w) / 2.0)
	check_approx("centre of the world sits on the view anchor (x)",
		centre_screen.x, anchor.x, 1.0)
	check_approx("centre of the world sits on the view anchor (y)",
		centre_screen.y, anchor.y, 1.0)

	section("panning off the edge is stopped by those bounds, not by a constant")
	# Shove the focus far past the corner; the clamp should haul it back to
	# within the padding of the rectangle it was given.
	rig.zoom_at(Vector2.ZERO, 8.0)
	await frames(40)
	rig._focus = Vector2(9000.0, 9000.0)
	await frames(2)
	var visible := rig._visible_world_rect(rig._focus, rig.get_zoom_level(), rig.get_tilt())
	var allowed := ODD_BOUNDS.grow(rig.bounds_padding)
	check_true("the view did not escape to the right",
		visible.end.x <= allowed.end.x + 1.0)
	check_true("nor off the bottom", visible.end.y <= allowed.end.y + 1.0)
	# Inside the padding ring is a legitimate place to be — the point is that the
	# view is still somewhere near the world rather than nine thousand pixels away.
	check_true("and it is still over the world it was given",
		allowed.encloses(visible))

	section("growing the world lets the view go further")
	var wide := ODD_BOUNDS.grow(500.0)
	rig.world_bounds = wide
	rig._focus = Vector2(9000.0, 9000.0)
	await frames(2)
	var now := rig._visible_world_rect(rig._focus, rig.get_zoom_level(), rig.get_tilt())
	check_true("the clamp moved with the bounds",
		now.end.x > visible.end.x)
	_drop(rig)


func _test_zoom_limits_and_anchoring() -> void:
	section("6-4 zoom is limited and eases rather than jumping")
	var rig := _rig()
	await frames(1)
	var started := rig.get_zoom_level()

	rig.zoom_at(Vector2(200.0, 200.0), 1.5)
	await frames(1)
	check_true("one frame is not the whole notch",
		rig.get_zoom_level() > started and rig.get_zoom_level() < started * 1.5)
	await frames(60)
	check_approx("it arrives", rig.get_zoom_level(), started * 1.5, started * 0.02)

	section("and it stops at the limits")
	for i in 60:
		rig.zoom_at(Vector2(200.0, 200.0), 4.0)
		await frames(2)
	check_approx("never past the maximum", rig.get_zoom_level(), rig.get_max_zoom(),
		rig.get_max_zoom() * 0.02)
	for i in 60:
		rig.zoom_at(Vector2(200.0, 200.0), 0.25)
		await frames(2)
	check_approx("never below the minimum", rig.get_zoom_level(), rig.get_min_zoom(),
		rig.get_min_zoom() * 0.02)

	_drop(rig)

	section("zooming keeps the point under the cursor under the cursor")
	# From a zoomed-in view, in a world with room around it. While the whole
	# world is framed the visible area is wider than the world itself, so the
	# bounds hold it centred and rightly win over the anchoring.
	var roomy := _rig(Rect2(-4000.0, -4000.0, 8000.0, 8000.0))
	roomy.zoom_at(roomy._anchor_screen(), 4.0)
	await frames(90)
	var cursor := Vector2(340.0, 260.0)
	var under_cursor := roomy.screen_to_world(cursor)
	roomy.zoom_at(cursor, 1.5)
	await frames(90)
	var still_there := roomy.world_to_screen(under_cursor)
	check_approx("the same world point is still at the cursor (x)",
		still_there.x, cursor.x, 2.0)
	check_approx("the same world point is still at the cursor (y)",
		still_there.y, cursor.y, 2.0)

	section("but the bounds outrank it: they stop the view leaving the world")
	var edge := _rig()
	await frames(2)
	var framed := edge._visible_world_rect(
		edge._focus, edge.get_zoom_level(), edge.get_tilt())
	edge.zoom_at(Vector2.ZERO, 1.0 / edge.zoom_step)
	await frames(90)
	var pulled := edge._visible_world_rect(
		edge._focus, edge.get_zoom_level(), edge.get_tilt())
	check_true("zooming out at a corner still shows the world",
		pulled.intersects(edge.world_bounds) and framed.intersects(edge.world_bounds))
	_drop(edge)
	_drop(roomy)


func _test_edge_push_ramp() -> void:
	section("6-5 edge scrolling ramps up across the band instead of snapping on")
	var rig := _rig()
	rig.edge_scroll_margin = 0.1
	var width := 1000.0
	check("dead centre does nothing", rig._edge_push(500.0, width), 0.0)
	check("just inside the band does nothing", rig._edge_push(101.0, width), 0.0)
	check_approx("halfway into the band is half speed",
		rig._edge_push(50.0, width), -0.5, 0.01)
	check("hard against the left edge is full speed left",
		rig._edge_push(0.0, width), -1.0)
	check("hard against the right edge is full speed right",
		rig._edge_push(width, width), 1.0)
	check_approx("and it is symmetrical",
		rig._edge_push(950.0, width), 0.5, 0.01)

	section("a zero margin turns it off rather than dividing by nothing")
	rig.edge_scroll_margin = 0.0
	check("no band, no push", rig._edge_push(0.0, width), 0.0)
	_drop(rig)

	section("and it is wired up: the view moves only while the cursor is in a band")
	# Worded against wherever the cursor actually is, so this holds in a headless
	# run (cursor at the corner) and a windowed one (cursor wherever it was left).
	var wide := _rig(Rect2(-4000.0, -4000.0, 8000.0, 8000.0))
	# Zoomed in far enough that there is somewhere to scroll TO. Framed wide,
	# the visible area is larger than the world and the bounds hold the focus
	# still, so nothing could move however hard the cursor pushed.
	wide.zoom_at(wide._anchor_screen(), 4.0)
	await frames(90)
	check_true("there is room to scroll into",
		wide.world_bounds.encloses(wide._visible_world_rect(
			wide._focus, wide.get_zoom_level(), wide.get_tilt())))
	wide.edge_scroll_enabled = true
	await frames(1)
	var screen := wide.get_viewport_rect().size
	var mouse := wide.get_viewport().get_mouse_position()
	var in_band: bool = wide._edge_push(mouse.x, screen.x) != 0.0 		or wide._edge_push(mouse.y, screen.y) != 0.0
	var before := wide._focus
	await frames(15)
	check("moved exactly when the cursor was in a band",
		wide._focus != before, in_band)

	section("and it coasts to a stop rather than halting dead")
	wide.edge_scroll_enabled = false
	var coasting := wide._focus
	await frames(3)
	check("still drifting a moment after the cursor left",
		wide._focus != coasting, in_band)
	await frames(120)
	var held := wide._focus
	await frames(20)
	check("but it does come to a complete stop", wide._focus, held)
	_drop(wide)


func _test_transition_is_a_move_not_a_cut() -> void:
	section("6-6 changing view is a move, not a teleport")
	var rig := _rig()
	rig.transition_duration = 0.4
	rig.set_view(CameraRig.View.GAMEPLAY, true)
	await frames(1)
	var gameplay_tilt := rig.get_tilt()

	rig.set_view(CameraRig.View.BUILD)
	check_true("it announces it is moving", rig.is_transitioning())
	await frames(3)
	var midway := rig.get_tilt()
	check_true("part way there, not there",
		midway > gameplay_tilt and midway < rig.build_tilt)

	section("and it arrives")
	await frames(60)
	check_false("no longer moving", rig.is_transitioning())
	check("at the build angle", rig.get_tilt(), rig.build_tilt)
	check("with things centred on their tiles again", rig.get_ground_anchor(), 0.0)

	_drop(rig)

	section("going back returns to where the player was looking")
	# Needs somewhere to go: with the whole world framed the bounds hold the view
	# centred, so there is no "where the player was" to forget.
	var roomy := _rig(Rect2(-2000.0, -2000.0, 4000.0, 4000.0))
	roomy.transition_duration = 0.2
	roomy.zoom_at(roomy._anchor_screen(), 4.0)
	await frames(90)
	roomy._focus += Vector2(300.0, 200.0)
	await frames(2)
	var remembered := roomy._focus
	check_true("the player has moved off centre",
		remembered.distance_to(Vector2.ZERO) > 100.0)

	roomy.set_view(CameraRig.View.BUILD)
	await frames(90)
	check_true("the build view looks somewhere of its own",
		roomy._focus.distance_to(remembered) > 1.0)

	roomy.set_view(CameraRig.View.GAMEPLAY)
	await frames(90)
	check_approx("same spot (x)", roomy._focus.x, remembered.x, 1.0)
	check_approx("same spot (y)", roomy._focus.y, remembered.y, 1.0)
	_drop(roomy)


## Switching view is presentation only. Nothing in the world may notice.
func _test_main_scene_switches_without_resetting() -> void:
	section("6-7 the real scene changes view without disturbing the world")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)

	var dungeon: Dungeon = main._dungeon
	var creatures: CreatureSystem = main._creatures
	var food: FoodSystem = main._food
	var rig: CameraRig = main.get_node("Camera2D")
	var world: Node2D = main.get_node("World")

	# Something to lose: floor, a rodent, food, water and a puddle.
	for y in 5:
		for x in 8:
			dungeon.place_floor(Vector2i(x, y))
	creatures.spawn(load("res://assets/creatures/rodent/maniac_sewer_rat.tres"),
		dungeon.get_current_floor(), 2)
	food.place(dungeon.get_current_floor(), Vector2i(6, 4))
	food.place(dungeon.get_current_floor(), Vector2i(6, 3),
		FoodSource.DEFAULT_AMOUNT, FoodSource.DEFAULT_NUTRITION, null,
		FoodSource.Kind.WATER)
	dungeon.get_current_floor().add_pee(Vector2i(1, 1), 2.0)
	await frames(2)

	var before := {
		"floor": dungeon.get_current_floor(),
		"tiles": dungeon.get_tile_count(),
		"built": dungeon.get_floor_tile_count(),
		"creatures": creatures.get_creature_count(),
		"food": food.get_count(),
		"pee": dungeon.get_current_floor().get_peed_positions().size(),
		"ticks": SimulationManager.tick_count,
		"day": GameTime.get_total_days(),
	}
	check("starts in the gameplay view", rig.get_view(), CameraRig.View.GAMEPLAY)
	check_true("which is angled", world.scale.y < 1.0)

	rig.toggle_view()
	await frames(90)
	check("now the build view", rig.get_view(), CameraRig.View.BUILD)
	check_approx("world is drawn straight down", world.scale.y, 1.0, 0.001)
	check_true("grid measurements are shown to build against",
		main.get_node("World/DungeonRenderer").show_grid)

	check("the same floor is still current", dungeon.get_current_floor(), before["floor"])
	check("no tile was lost", dungeon.get_tile_count(), before["tiles"])
	check("no floor was lost", dungeon.get_floor_tile_count(), before["built"])
	check("no creature was lost", creatures.get_creature_count(), before["creatures"])
	check("no food was lost", food.get_count(), before["food"])
	check("no puddle was lost",
		dungeon.get_current_floor().get_peed_positions().size(), before["pee"])
	check_true("the clock did not go backwards",
		SimulationManager.tick_count >= before["ticks"])
	check("nor the calendar", GameTime.get_total_days(), before["day"])

	section("and the tile under a screen pixel is unchanged by the switch")
	var probe := Vector2i(4, 2)
	check("build view still finds (4,2)",
		dungeon.world_to_grid(rig.screen_to_world(
			rig.world_to_screen(dungeon.grid_to_world_center(probe)))), probe)
	rig.toggle_view()
	await frames(90)
	check("gameplay view still finds (4,2)",
		dungeon.world_to_grid(rig.screen_to_world(
			rig.world_to_screen(dungeon.grid_to_world_center(probe)))), probe)
	check_false("and the grid measurements are put away again",
		main.get_node("World/DungeonRenderer").show_grid)

	section("standing things are stood up, ground things are not")
	var creature_layer: CreatureLayer = main.get_node("World/CreatureLayer")
	var food_layer: FoodLayer = main.get_node("World/FoodLayer")
	check_approx("creatures are handed the angle",
		creature_layer.view_tilt, rig.get_tilt(), 0.001)
	var rat: Creature = creatures.get_creatures()[0]
	var rat_view: CreatureView = creature_layer.get_view(rat)
	check_true("and undo it on the sprite so the rat stays upright",
		rat_view._sprite.scale.y > rat_view._sprite.scale.x)
	var water: FoodSource = food.get_sources()[1]
	var water_view: FoodView = food_layer.get_view(water)
	check("water is drawn flat, like the floor it is part of",
		water_view._sprite.scale.y, water_view._sprite.scale.x)
	check_true("and under anything standing on it", water_view.z_index < 0)
	# ...but still above the floor it covers. Put it below the dungeon and it
	# vanishes under opaque tiles, which is exactly what happened first time.
	check_true("and above the floor it covers",
		water_view.z_index > main.get_node("World/DungeonRenderer").z_index)
	check_true("as do the stains on that floor",
		main.get_node("World/PeeLayer").z_index
			> main.get_node("World/DungeonRenderer").z_index)

	tree.root.remove_child(main)
	main.queue_free()


## The camera can be handed something to watch without learning what it is.
func _test_following() -> void:
	section("6-8 following keeps a moving point in view")
	# Taller than it is wide. The framed zoom is limited by WIDTH, and the angle
	# halves the vertical, so on a square world the visible slab is still taller
	# than the world even zoomed in — and the bounds would hold the view centred
	# instead of letting it follow anything.
	var rig := _rig(Rect2(-2000.0, -4000.0, 4000.0, 8000.0))
	# Snappier than the game uses. The ease never truly arrives, so how close it
	# gets depends on elapsed SECONDS — pinning it to a frame count would make
	# the tolerance a bet on how fast the machine runs.
	rig.follow_responsiveness = 20.0
	# Held in an array on purpose: a lambda captures a local Vector2 by VALUE, so
	# a plain variable would freeze at its first position and the "it keeps up"
	# check below would be testing nothing. The real one captures a Creature,
	# which is a reference, and so reads its live position.
	var subject := [Vector2(600.0, 400.0)]
	var ask := func() -> Vector2: return subject[0]

	check_false("nothing is being followed yet", rig.is_following())
	rig.follow(ask)
	check_true("now it is", rig.is_following())
	await real_seconds(0.6)
	check_approx("the subject is on the view anchor (x)",
		rig.world_to_screen(subject[0]).x, rig._anchor_screen().x, 4.0)
	check_approx("the subject is on the view anchor (y)",
		rig.world_to_screen(subject[0]).y, rig._anchor_screen().y, 4.0)
	check_true("and it zoomed in to look",
		rig.get_zoom_level() > rig._fit_zoom_for(rig.get_view()) * 1.5)

	section("and it keeps up when the subject moves")
	subject[0] = Vector2(-700.0, -500.0)
	await real_seconds(0.6)
	check_approx("still centred (x)",
		rig.world_to_screen(subject[0]).x, rig._anchor_screen().x, 4.0)
	check_approx("still centred (y)",
		rig.world_to_screen(subject[0]).y, rig._anchor_screen().y, 4.0)

	section("but it trails rather than being welded on")
	# One frame after a jump the camera must NOT already be there, or it is a
	# teleport wearing a follow's clothes.
	#
	# The jump has to land somewhere the bounds would not have pulled the view
	# back from. Near an edge the clamp leaves a gap of its own, and that gap
	# looks exactly like trailing — it hid a welded camera the first time.
	var landing := Vector2(300.0, 200.0)
	check_true("the landing spot is clear of the bounds",
		rig.world_bounds.encloses(rig._visible_world_rect(
			landing, rig.get_zoom_level(), rig.get_tilt())))
	subject[0] = landing
	await frames(1)
	check_true("it has not snapped to the new spot",
		rig.world_to_screen(subject[0]).distance_to(rig._anchor_screen()) > 20.0)

	section("the player taking over ends it")
	await real_seconds(0.6)
	rig._panning = true
	rig.stop_following()
	check_false("no longer following", rig.is_following())
	var parked := rig._focus
	subject[0] = Vector2(-1500.0, -1200.0)
	await real_seconds(0.4)
	check("and the view stays where it was left", rig._focus, parked)

	section("a view change ends it too: framing and following disagree")
	rig.follow(ask)
	check_true("following again", rig.is_following())
	rig.set_view(CameraRig.View.BUILD)
	check_false("the switch let go", rig.is_following())
	await frames(90)
	_drop(rig)


## Editing the dungeon belongs to the build view. The gameplay view looks.
func _test_building_is_build_view_only() -> void:
	section("6-9 the gameplay view cannot build, remove or buy")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(2)
	var dungeon: Dungeon = main._dungeon
	var rig: CameraRig = main.get_node("Camera2D")
	check("starts in the gameplay view", rig.get_view(), CameraRig.View.GAMEPLAY)

	var target := Vector2i(4, 2)
	var at := rig.world_to_screen(dungeon.grid_to_world_center(target))
	check_false("the tile has no floor yet", dungeon.is_walkable(target))

	# Exactly the gesture that builds in the other view.
	_click(main, at, true)
	_click(main, at, false)
	check_false("dragging in the gameplay view built nothing",
		dungeon.is_walkable(target))

	section("and a click there inspects instead")
	var creatures: CreatureSystem = main._creatures
	dungeon.place_floor(target)
	var spawned := creatures.spawn(
		load("res://assets/creatures/rodent/maniac_sewer_rat.tres"),
		dungeon.get_current_floor(), 1)
	spawned[0].grid_position = target
	spawned[0].move_target = target
	await frames(2)
	at = rig.world_to_screen(dungeon.grid_to_world_center(target))
	_click(main, at, true)
	check("the rodent under the cursor was picked up", main._inspected, spawned[0])
	check_true("and the camera is watching it", rig.is_following())

	section("clicking bare ground lets go")
	var empty := rig.world_to_screen(dungeon.grid_to_world_center(Vector2i(0, 4)))
	_click(main, empty, true)
	check("nothing is being inspected", main._inspected, null)
	check_false("and the camera is free again", rig.is_following())

	section("the build view does build")
	rig.set_view(CameraRig.View.BUILD)
	await frames(90)
	var build_target := Vector2i(6, 1)
	check_false("no floor there yet", dungeon.is_walkable(build_target))
	at = rig.world_to_screen(dungeon.grid_to_world_center(build_target))
	_click(main, at, true)
	_click(main, at, false)
	check_true("the same gesture builds here", dungeon.is_walkable(build_target))

	tree.root.remove_child(main)
	main.queue_free()
