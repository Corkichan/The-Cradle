extends Node2D

## Temporary harness for verifying System 0 (SimulationManager), System 0.2
## (GameTime), System 1 (Dungeon grid, tile and floor expansion) and System 2
## (Creature life).
## Delete this script and its node assignment once real gameplay exists.

## Screen width reserved for the debug HUD. The dungeon is framed in what is
## left, so the HUD never covers the axis labels.
const _HUD_WIDTH: float = 440.0

## Prototype creature. None exist at startup; the player spawns them with S.
const _RODENT: CreatureSpecies = preload("res://assets/creatures/rodent/maniac_sewer_rat.tres")
## Food sources dropped in at startup. None can be placed until floor exists, so
## on a fresh dungeon this quietly does nothing and [F] is how food arrives.
const _STARTING_FOOD: int = 4

## What a drag does on release.
enum EditMode {
	PLACE_FLOOR,  ## Build floor on an area so creatures can walk there.
	REMOVE_FLOOR, ## Strip floor from an area, back to bare EMPTY ground.
	EXPAND, ## Buy one new floor tile per click.
}

const _MODE_COLOR := {
	EditMode.PLACE_FLOOR: Color("ffd166"),
	EditMode.REMOVE_FLOOR: Color("ff6b6b"),
	EditMode.EXPAND: Color("6fe08a"),
}

## Everything that lives in world space. Its vertical scale IS the camera
## angle — see [CameraRig] — so the whole world tips as one piece and no layer
## needs its own idea of what the view looks like.
@onready var _world: Node2D = $World
@onready var _renderer: DungeonRenderer = $World/DungeonRenderer
@onready var _creature_layer: CreatureLayer = $World/CreatureLayer
@onready var _food_layer: FoodLayer = $World/FoodLayer
@onready var _pee_layer: PeeLayer = $World/PeeLayer
@onready var _camera: CameraRig = $Camera2D
@onready var _hud: CanvasLayer = $HUD

var _dungeon: Dungeon
var _expansion: DungeonExpansion
var _creatures: CreatureSystem
var _food: FoodSystem
var _starved: int = 0
## The creature the player clicked in the gameplay view, or null. Inspecting is
## looking, never touching: nothing here changes the simulation.
var _inspected: Creature = null
var _controls: Label
var _floor_bar: HBoxContainer
var _dragging: bool = false
var _drag_start: Vector2i = Vector2i.ZERO
## Current edit mode. Explicit rather than inferred from the tile under the
## cursor, so the result of a drag is predictable before it starts.
var _edit_mode: EditMode = EditMode.PLACE_FLOOR
var _label: Label
var _ticks_last_second: int = 0
var _tick_mark: int = 0
var _real_second: float = 0.0


func _ready() -> void:
	# System 1: build the data model, then hand it to the renderer. The
	# renderer reads it; the dungeon knows nothing about being drawn.
	_dungeon = Dungeon.new()
	_expansion = DungeonExpansion.new(_dungeon)
	_renderer.dungeon = _dungeon

	# System 2: creatures are simulated by the system and drawn by the layer.
	# The dungeon starts empty; each rodent stays on the floor it was spawned on.
	_creatures = CreatureSystem.new()
	_creature_layer.current_floor = _dungeon.get_current_floor()
	_creature_layer.system = _creatures

	# System 3: food is part of the world, not part of any creature. The creature
	# system is given a reference so creatures can notice it.
	_food = FoodSystem.new()
	_creatures.food_system = _food
	_food_layer.current_floor = _dungeon.get_current_floor()
	_food_layer.system = _food
	_pee_layer.current_floor = _dungeon.get_current_floor()
	_food.food_depleted.connect(func(f: FoodSource) -> void:
		print("food #%d at %s was finished off" % [f.id, f.grid_position]))
	var initial_food := _food.place_random(_dungeon.get_current_floor(), _STARTING_FOOD,
		FoodSource.DEFAULT_AMOUNT, FoodSource.DEFAULT_NUTRITION, _creatures)
	if initial_food.is_empty():
		print("No floor yet, so no food placed - build some floor, then press F")
	_creatures.creature_died.connect(func(c: Creature) -> void:
		if c == _inspected:
			_stop_inspecting()
		_starved += 1
		print("Rodent #%d starved to death at %s, aged %ds" % [
			c.id, c.grid_position, int(c.age)]))

	# The camera is told the shape of the world and the strip the HUD occupies.
	# It is never told what a tile is, so nothing about 8x5 reaches it.
	_camera.view_margins = Vector4(_HUD_WIDTH, 0.0, 0.0, 0.0)
	_refresh_camera_bounds()
	_camera.make_current()
	_camera.reset_view(true)
	set_edit_mode(_edit_mode)

	# HUD lives on a CanvasLayer so the camera does not drag it around.
	# Floor buttons sit above the readout. The container ignores the mouse so
	# only the buttons themselves swallow clicks; everything else falls through
	# to the grid.
	_floor_bar = HBoxContainer.new()
	_floor_bar.position = Vector2(16, 14)
	_floor_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_bar.add_theme_constant_override("separation", 6)
	_hud.add_child(_floor_bar)

	_label = Label.new()
	_label.position = Vector2(16, 56)
	_style_readout(_label)
	_hud.add_child(_label)

	# The controls are pinned to the bottom of the window rather than following
	# the readout, so they stay visible however short the window is and however
	# many lines the readout grows to.
	_controls = Label.new()
	_style_readout(_controls)
	_controls.text = "\n".join([
		"[S] rodent   [F] food   [W] water   [L] labels   [V] search area",
		"BUILD view: [tab] mode  [left drag] place/remove floor  [click] buy in EXPAND",
		"GAMEPLAY view: [left click] a rodent to inspect and follow it",
		"[space] pause   [1..4] speed 1/2/5/10x   [right] step while paused",
		"[wheel] or [+]/[-] zoom at cursor   [middle drag] pan   [R] reset view",
		"[B] gameplay / build view   [E] edge scrolling   [F1/F2/F3] fps cap",
	])
	_hud.add_child(_controls)

	_rebuild_floor_bar()

	SimulationManager.simulation_tick.connect(_on_simulation_tick)
	SimulationManager.paused_changed.connect(func(p): print("paused -> ", p))
	SimulationManager.speed_changed.connect(func(s): print("speed -> ", s, "x"))


func _on_simulation_tick(_delta: float) -> void:
	pass # Real systems do work here. The harness only counts ticks.


## Same look for both readouts.
func _style_readout(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_outline_size", 4)


func _process(delta: float) -> void:
	_apply_presentation()

	# The camera drops what it is following the moment the player steers, so the
	# selection follows the camera rather than the camera obeying a stale one.
	if _inspected != null and not _camera.is_following():
		_inspected = null

	# Recomputed rather than anchored so it follows a resized window.
	_controls.position = Vector2(
		16, get_viewport_rect().size.y - _controls.size.y - 10)

	# Food does not move, but the amount on its label changes as it is eaten.
	_food_layer.refresh()

	# Live proof that world -> grid conversion works: the highlighted tile
	# follows the mouse and the readout below names its coordinate.
	# Converted through the camera, which knows the angle, so the tile under the
	# cursor is the same tile in both views.
	var hover := _grid_at(get_viewport().get_mouse_position())
	_renderer.hover_tile = hover

	# Measure ticks per REAL second. This is the number that proves
	# the simulation is independent from the render frame rate.
	_real_second += delta
	if _real_second >= 1.0:
		_real_second -= 1.0
		_ticks_last_second = SimulationManager.tick_count - _tick_mark
		_tick_mark = SimulationManager.tick_count

	var expected := SimulationManager.TICKS_PER_SECOND * SimulationManager.get_speed()
	_label.text = "\n".join([
		"Y%d D%d  %s   total days %d" % [GameTime.get_year(), GameTime.get_day(),
			GameTime.get_time_string(), GameTime.get_total_days()],
		"floor %d/%d   %dx%d  %d tiles   built %d/%d   zoom %.2fx" % [
			_dungeon.get_current_floor_index() + 1, _dungeon.get_floor_count(),
			_dungeon.get_width(), _dungeon.get_height(), _dungeon.get_tile_count(),
			_dungeon.get_floor_tile_count(), _dungeon.get_tile_count(),
			_camera.get_zoom_ratio()],
		"",
		"Rodents %d   %d here  %d asleep  %d starved" % [
			_creatures.get_creature_count(), _here().size(), _asleep_here(), _starved],
		"Water   %d   %d thirsty  %d seeking  %d drinking" % [
			_sources_of(FoodSource.Kind.WATER), _counting_thirsty(),
			_counting_intent(Creature.Intent.SEEK_WATER),
			_counting_intent(Creature.Intent.DRINK)],
		"Food    %d   %d left  %d seeking  %d eating" % [
			_sources_of(FoodSource.Kind.FOOD), roundi(_food_remaining()),
			_counting_intent(Creature.Intent.SEEK_FOOD),
			_counting_intent(Creature.Intent.EAT)],
		"Pee     %d tiles   %.0f total" % [_peed_tiles(), _pee_total()],
		"Gold %d   tile %d   floor %d" % [
			_expansion.gold, _expansion.tile_cost, _expansion.get_floor_cost()],
		"",
		"mode %s   expandable %d   selection %s %s" % ([
			EditMode.keys()[_edit_mode], _renderer.expandable.size()]
			+ _describe_selection()),
		"hover %s  %s" % [str(hover), _describe_hover(hover)],
		"inspecting %s" % _describe_inspection(),
		"view %s   tilt %.2f   edge scroll %s" % [
			CameraRig.View.keys()[_camera.get_view()], _camera.get_tilt(),
			"on" if _camera.edge_scroll_enabled else "off"],
		"",
		"sim %.1fs  %d ticks  %d/s (expect %d)" % [
			SimulationManager.get_simulation_time(), SimulationManager.tick_count,
			_ticks_last_second, expected],
		"fps %d (cap %s)   speed %sx   %s" % [
			Engine.get_frames_per_second(),
			"none" if Engine.max_fps == 0 else str(Engine.max_fps),
			SimulationManager.get_speed(),
			"PAUSED" if SimulationManager.is_paused() else "running"],
	])


func _here() -> Array[Creature]:
	return _creatures.get_creatures_on(_dungeon.get_current_floor())


## Tiles on this floor that have been urinated on, and how much in total.
func _peed_tiles() -> int:
	return _dungeon.get_current_floor().get_peed_positions().size()


func _pee_total() -> float:
	var total := 0.0
	for position in _dungeon.get_current_floor().get_peed_positions():
		total += _dungeon.get_tile(position).pee_amount
	return total


## Food left on the floor being viewed, for the readout.
func _food_remaining() -> float:
	var total := 0.0
	for food in _food.get_sources_on(_dungeon.get_current_floor()):
		total += food.amount
	return total


func _sources_of(kind: FoodSource.Kind) -> int:
	var count := 0
	for source in _food.get_sources_on(_dungeon.get_current_floor()):
		if source.kind == kind:
			count += 1
	return count


func _counting_thirsty() -> int:
	var count := 0
	for creature in _here():
		if creature.is_thirsty():
			count += 1
	return count


func _counting_intent(intent: Creature.Intent) -> int:
	var count := 0
	for creature in _here():
		if creature.intent == intent:
			count += 1
	return count


func _asleep_here() -> int:
	var count := 0
	for creature in _here():
		if creature.asleep:
			count += 1
	return count


func _describe_hover(grid_position: Vector2i) -> String:
	var tile := _dungeon.get_tile(grid_position)
	if tile != null:
		return "%s  walkable=%s  world=%s" % [
			DungeonTile.Terrain.keys()[tile.terrain],
			tile.walkable,
			_dungeon.grid_to_world(grid_position)]
	if _expansion.can_expand_at(grid_position):
		return "BUYABLE  cost %d  %s" % [
			_expansion.get_expansion_cost(grid_position),
			"click to buy" if _expansion.can_afford(grid_position) else "NOT ENOUGH GOLD"]
	return "outside dungeon"


## The creature standing on, or stepping onto, a tile. Null for an empty one.
func _creature_at(grid_position: Vector2i) -> Creature:
	for creature in _here():
		if creature.grid_position == grid_position 				or creature.move_target == grid_position:
			return creature
	return null


## Looks at whatever was clicked. Clicking a creature hands the camera a way to
## ask where that creature is, so the view follows it; clicking anywhere else
## lets go. Nothing here writes to the simulation — this is the gameplay view's
## whole interaction, and it is read-only by design.
func _inspect_at(screen_position: Vector2) -> void:
	var creature := _creature_at(_grid_at(screen_position))
	if creature == null:
		_stop_inspecting()
		return
	_inspected = creature
	# A function rather than the creature itself, so the camera follows a point
	# and never learns what a creature is.
	_camera.follow(func() -> Vector2:
		var half := Vector2.ONE * (Dungeon.TILE_SIZE / 2.0)
		var from := Vector2(creature.grid_position) * Dungeon.TILE_SIZE + half
		var to := Vector2(creature.move_target) * Dungeon.TILE_SIZE + half
		return from.lerp(to, creature.move_progress))
	print("inspecting %s #%d at %s" % [
		creature.get_variant_name(), creature.id, creature.grid_position])


func _stop_inspecting() -> void:
	_inspected = null
	_camera.stop_following()


func _describe_inspection() -> String:
	if _inspected == null:
		return "- (click a rodent in the gameplay view)"
	return "%s #%d  %s  age %ds  hunger %d  water %d  at %s" % [
		_inspected.get_variant_name(), _inspected.id,
		Creature.State.keys()[_inspected.state], int(_inspected.age),
		int(_inspected.hunger), int(_inspected.hydration), _inspected.grid_position]


## [size, what release will do] for the HUD.
func _describe_selection() -> Array:
	if not _dragging:
		return ["-", ""]
	var r := _renderer.selection
	return [
		"%dx%d=%d" % [r.size.x, r.size.y, r.size.x * r.size.y],
		"will place floor" if _edit_mode == EditMode.PLACE_FLOOR else "will remove floor",
	]


## Hands the camera's framing to the things that draw.
##
## The camera decides HOW the world is presented; this decides WHAT that means
## for each layer, because only the scene knows which of its layers are ground
## and which are standing on it. The dungeon, the pee and the water tip away
## with the floor; the rodents and the food are stood back up.
##
## None of this touches a grid coordinate. A tile is at the same place in both
## views — it is only drawn from a different angle.
func _apply_presentation() -> void:
	var tilt := _camera.get_tilt()
	var anchor := _camera.get_ground_anchor()
	var zoom_level := _camera.get_zoom_level()

	_world.scale.y = tilt

	_renderer.view_zoom = zoom_level
	_renderer.view_tilt = tilt
	# Measuring aids belong to the view you build in.
	_renderer.show_grid = _camera.get_view() == CameraRig.View.BUILD

	_creature_layer.view_zoom = zoom_level
	_creature_layer.view_tilt = tilt
	_creature_layer.ground_anchor = anchor

	_food_layer.view_zoom = zoom_level
	_food_layer.view_tilt = tilt
	_food_layer.ground_anchor = anchor


## Tells the camera the shape of the world whenever that shape changes. The
## camera stores it as a plain rectangle, so buying a tile or switching to a
## floor of another size reframes without the camera knowing either happened.
func _refresh_camera_bounds() -> void:
	_camera.world_bounds = _dungeon.get_world_bounds()


## Rebuilds the floor buttons. Cheap enough to redo whenever the floor list or
## the selection changes, which avoids tracking button state separately.
func _rebuild_floor_bar() -> void:
	for child in _floor_bar.get_children():
		child.queue_free()
		_floor_bar.remove_child(child)

	for index in _dungeon.get_floor_count():
		var button := Button.new()
		button.text = "Floor %d" % (index + 1)
		if index == _dungeon.get_current_floor_index():
			button.text = "[ %s ]" % button.text
		# Buttons must never take keyboard focus, or Tab would drive focus
		# navigation instead of reaching the edit-mode shortcut.
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_switch_floor.bind(index))
		_floor_bar.add_child(button)

	var build := Button.new()
	build.text = "Build New Floor - %d Gold" % _expansion.get_floor_cost()
	build.focus_mode = Control.FOCUS_NONE
	build.disabled = not _expansion.can_afford_floor()
	build.pressed.connect(_on_build_floor_pressed)
	_floor_bar.add_child(build)


## Shows another floor. Each floor has its own size and shape, so the view is
## reframed and the ghost tiles recomputed for the new floor.
func _switch_floor(index: int) -> void:
	if not _dungeon.set_current_floor(index):
		return
	_refresh_expandable()
	_rebuild_floor_bar()
	_refresh_camera_bounds()
	_camera.reset_view()
	_renderer.queue_redraw()
	_creature_layer.current_floor = _dungeon.get_current_floor()
	_food_layer.current_floor = _dungeon.get_current_floor()
	_pee_layer.current_floor = _dungeon.get_current_floor()
	print("switched to floor %d (%dx%d, %d tiles)" % [
		index + 1, _dungeon.get_width(), _dungeon.get_height(),
		_dungeon.get_tile_count()])


func _on_build_floor_pressed() -> void:
	var index := _expansion.create_floor()
	if index < 0:
		print("Not enough Gold (need %d, have %d)"
			% [_expansion.get_floor_cost(), _expansion.gold])
		return
	print("built floor %d for %d gold, balance %d"
		% [index + 1, _expansion.get_floor_cost(), _expansion.gold])
	_switch_floor(index)


## Debug: drop one water source on a free floor tile of the floor being viewed.
func _drop_water_here() -> void:
	var placed := _food.place_random(_dungeon.get_current_floor(), 1,
		FoodSource.DEFAULT_AMOUNT, FoodSource.DEFAULT_NUTRITION, _creatures,
		FoodSource.Kind.WATER)
	if placed.is_empty():
		print("Nowhere to put water: needs a floored tile with nothing on it")
	else:
		print("dropped water #%d at %s (amount %.0f)" % [
			placed[0].id, placed[0].grid_position, placed[0].amount])


## Debug: drop one food source on a free floor tile of the floor being viewed.
func _drop_food_here() -> void:
	var placed := _food.place_random(_dungeon.get_current_floor(), 1,
		FoodSource.DEFAULT_AMOUNT, FoodSource.DEFAULT_NUTRITION, _creatures)
	if placed.is_empty():
		print("Nowhere to put food: needs a floored tile with no creature or food on it")
	else:
		print("dropped food #%d at %s (amount %.0f, nutrition %.0f)" % [
			placed[0].id, placed[0].grid_position, placed[0].amount, placed[0].nutrition])


## Debug spawn: one rodent on the floor being viewed, if it has a free tile.
func _spawn_rodent_here() -> void:
	var spawned := _creatures.spawn(_RODENT, _dungeon.get_current_floor(), 1)
	if spawned.is_empty():
		print("No free tile for a rodent on this floor")
	else:
		print("spawned %s #%d at %s on floor %d" % [_RODENT.variant_name, spawned[0].id,
			spawned[0].grid_position, _dungeon.get_current_floor_index() + 1])


func set_edit_mode(mode: EditMode) -> void:
	_edit_mode = mode
	_renderer.selection_color = _MODE_COLOR[mode]
	_refresh_expandable()


func toggle_edit_mode() -> void:
	set_edit_mode((_edit_mode + 1) % EditMode.size() as EditMode)


## Ghost tiles are only shown in EXPAND mode, so the other modes stay uncluttered.
func _refresh_expandable() -> void:
	_renderer.expandable = _expansion.get_expandable_positions() 		if _edit_mode == EditMode.EXPAND and _camera != null 		and _camera.get_view() == CameraRig.View.BUILD 		else ([] as Array[Vector2i])


## Buys the tile under the click. One tile per click — expansion is deliberately
## not a drag operation.
func _try_purchase(grid_position: Vector2i) -> void:
	if not _expansion.purchase_tile(grid_position):
		return
	_refresh_camera_bounds()
	_refresh_expandable()
	_rebuild_floor_bar()
	_renderer.queue_redraw()
	print("bought %s for %d gold, balance %d, %d tiles"
		% [grid_position, _expansion.tile_cost, _expansion.gold, _dungeon.get_tile_count()])


## Grid coordinate under a screen pixel. Derived from the event position rather
## than the polled mouse, so the tile acted on is always the tile clicked.
func _grid_at(screen_position: Vector2) -> Vector2i:
	return _dungeon.world_to_grid(_camera.screen_to_world(screen_position))


## Clamps a grid coordinate into the dungeon, so a drag that runs off the edge
## still selects the tiles it covered rather than nothing.
func _clamp_to_grid(grid_position: Vector2i) -> Vector2i:
	var bounds := _dungeon.get_bounds()
	return Vector2i(
		clampi(grid_position.x, bounds.position.x, bounds.end.x - 1),
		clampi(grid_position.y, bounds.position.y, bounds.end.y - 1))


## Inclusive rectangle spanning two grid corners, in either drag direction.
func _rect_between(a: Vector2i, b: Vector2i) -> Rect2i:
	var top_left := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var bottom_right := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)


## Starts a drag. The whole gesture applies [member _edit_mode] uniformly, so
## dragging over mixed tiles never leaves a checkerboard of toggles.
func _begin_drag(screen_position: Vector2) -> void:
	var start := _grid_at(screen_position)
	if _edit_mode == EditMode.EXPAND:
		_try_purchase(start)
		return
	if not _dungeon.is_valid_position(start):
		return
	_dragging = true
	_drag_start = start
	_renderer.selection = Rect2i(start, Vector2i.ONE)


func _update_drag(screen_position: Vector2) -> void:
	if not _dragging:
		return
	_renderer.selection = _rect_between(
		_drag_start, _clamp_to_grid(_grid_at(screen_position)))


## Applies the drag on release. This is the only point the DATA MODEL changes;
## everything before it was preview. The renderer then reflects the new state.
func _end_drag(screen_position: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	var rect := _rect_between(
		_drag_start, _clamp_to_grid(_grid_at(screen_position)))
	_renderer.selection = Rect2i()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			# Cells inside the bounding box can be empty once the dungeon has
			# been expanded into a non-rectangular shape.
			var position := Vector2i(x, y)
			if _edit_mode == EditMode.PLACE_FLOOR:
				_dungeon.place_floor(position)
			else:
				_dungeon.remove_floor(position)
	_renderer.queue_redraw()


## The left button means different things in the two views, and only one of
## them touches the dungeon. Building, removing and buying are BUILD VIEW ONLY:
## in the gameplay view you are watching a world, not editing one.
func _unhandled_input(event: InputEvent) -> void:
	var building := _camera.get_view() == CameraRig.View.BUILD
	if event is InputEventMouseMotion:
		if building:
			_update_drag(event.position)
	elif event is InputEventMouseButton 			and event.button_index == MOUSE_BUTTON_LEFT:
		if not building:
			if event.pressed:
				_inspect_at(event.position)
		elif event.pressed:
			_begin_drag(event.position)
		else:
			_end_drag(event.position)


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
		KEY_EQUAL, KEY_KP_ADD:
			_camera.zoom_at(get_viewport_rect().size / 2.0, _camera.zoom_step)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_camera.zoom_at(get_viewport_rect().size / 2.0, 1.0 / _camera.zoom_step)
		KEY_R:
			_camera.reset_view()
		KEY_B:
			# Not tab: tab already cycles the edit mode.
			_stop_inspecting()
			_dragging = false
			_renderer.selection = Rect2i()
			_camera.toggle_view()
			_refresh_expandable()
		KEY_E:
			_camera.edge_scroll_enabled = not _camera.edge_scroll_enabled
		KEY_TAB:
			toggle_edit_mode()
		KEY_S:
			_spawn_rodent_here()
		KEY_F:
			_drop_food_here()
		KEY_W:
			_drop_water_here()
		KEY_V:
			_creature_layer.show_detection_area = not _creature_layer.show_detection_area
		KEY_L:
			_creature_layer.labels_visible = not _creature_layer.labels_visible
			_food_layer.labels_visible = _creature_layer.labels_visible
