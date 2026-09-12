extends Node2D

## Temporary harness for verifying System 0 (SimulationManager), System 0.2
## (GameTime) and System 1 (Dungeon grid).
## Delete this script and its node assignment once real gameplay exists.

## Fraction of the usable viewport the dungeon should occupy, leaving room for
## the axis labels drawn outside the grid.
const _CAMERA_FIT_MARGIN: float = 0.88
## Screen width reserved for the debug HUD. The dungeon is framed in what is
## left, so the HUD never covers the axis labels.
const _HUD_WIDTH: float = 440.0

## Zoom limits, as multiples of the fit-the-whole-dungeon zoom.
const _ZOOM_MIN_FACTOR: float = 0.5
const _ZOOM_MAX_FACTOR: float = 12.0
## Multiplier applied per wheel notch / key press.
const _ZOOM_STEP: float = 1.15

## What a drag does on release.
enum EditMode {
	ADD,    ## Fill the area with blocked (grey) tiles.
	DELETE, ## Clear the area back to walkable floor.
	EXPAND, ## Buy one new floor tile per click.
}

const _MODE_COLOR := {
	EditMode.ADD: Color("ffd166"),
	EditMode.DELETE: Color("ff6b6b"),
	EditMode.EXPAND: Color("6fe08a"),
}

@onready var _renderer: DungeonRenderer = $DungeonRenderer
@onready var _camera: Camera2D = $Camera2D
@onready var _hud: CanvasLayer = $HUD

var _dungeon: Dungeon
var _expansion: DungeonExpansion
var _fit_zoom: float = 1.0
var _dragging: bool = false
var _drag_start: Vector2i = Vector2i.ZERO
## Current edit mode. Explicit rather than inferred from the tile under the
## cursor, so the result of a drag is predictable before it starts.
var _edit_mode: EditMode = EditMode.ADD
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

	_camera.make_current()
	_reset_view()
	set_edit_mode(_edit_mode)

	# HUD lives on a CanvasLayer so the camera does not drag it around.
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_outline_size", 4)
	_hud.add_child(_label)

	SimulationManager.simulation_tick.connect(_on_simulation_tick)
	SimulationManager.paused_changed.connect(func(p): print("paused -> ", p))
	SimulationManager.speed_changed.connect(func(s): print("speed -> ", s, "x"))


func _on_simulation_tick(_delta: float) -> void:
	pass # Real systems do work here. The harness only counts ticks.


func _process(delta: float) -> void:
	# Live proof that world -> grid conversion works: the highlighted tile
	# follows the mouse and the readout below names its coordinate.
	var mouse_local := _renderer.to_local(_renderer.get_global_mouse_position())
	var hover := _dungeon.world_to_grid(mouse_local)
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
		"Year %d   Day %d   %s" % [
			GameTime.get_year(), GameTime.get_day(), GameTime.get_time_string()],
		"total days %8d" % GameTime.get_total_days(),
		"",
		"dungeon    %8s   (%d tiles)" % [
			"%dx%d" % [_dungeon.get_width(), _dungeon.get_height()],
			_dungeon.get_tile_count()],
		"Gold       %8d   Tile Cost %d" % [_expansion.gold, _expansion.tile_cost],
		"hover tile %8s   %s" % [
			str(hover), _describe_hover(hover)],
		"blocked    %8d   zoom %.2fx" % [_count_blocked(), _camera.zoom.x / _fit_zoom],
		"selection  %8s   %s" % _describe_selection(),
		"mode       %8s   [tab] to switch" % EditMode.keys()[_edit_mode],
		"expandable %8d   positions on offer" % _renderer.expandable.size(),
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
		"[wheel] or [+]/[-] zoom at cursor   [R] reset view",
		"[left drag] ADD/DELETE an area   [left click] buy a tile in EXPAND",
		"[space] pause/resume   [1..4] speed 1/2/5/10x",
		"[F1] cap 10 fps  [F2] cap 30  [F3] uncapped",
		"[right] single step while paused",
	])


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


## [size, what release will do] for the HUD.
func _describe_selection() -> Array:
	if not _dragging:
		return ["-", ""]
	var r := _renderer.selection
	return [
		"%dx%d=%d" % [r.size.x, r.size.y, r.size.x * r.size.y],
		"will add grey" if _edit_mode == EditMode.ADD else "will delete grey",
	]


func _count_blocked() -> int:
	var n := 0
	for position in _dungeon.get_positions():
		if not _dungeon.is_walkable(position):
			n += 1
	return n


## Screen pixel -> world pixel for a given zoom, computed directly rather than
## via the camera transform, which only refreshes at end of frame.
func _screen_to_world(screen_position: Vector2, zoom: float) -> Vector2:
	return _camera.position + (screen_position - get_viewport_rect().size / 2.0) / zoom


## Zooms by [param factor], keeping whatever is under [param screen_position]
## pinned there. Zooming toward the cursor doubles as navigation, so no
## separate pan control is needed.
func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var target := clampf(_camera.zoom.x * factor,
		_fit_zoom * _ZOOM_MIN_FACTOR, _fit_zoom * _ZOOM_MAX_FACTOR)
	if is_equal_approx(target, _camera.zoom.x):
		return
	var anchor_world := _screen_to_world(screen_position, _camera.zoom.x)
	_camera.position = anchor_world 		- (screen_position - get_viewport_rect().size / 2.0) / target
	_camera.zoom = Vector2.ONE * target
	_renderer.view_zoom = target


## Viewport minus the strip reserved for the HUD.
func _usable_size() -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(viewport_size.x - _HUD_WIDTH, viewport_size.y)


## Screen pixel the dungeon centre should sit on: the middle of the area the
## HUD is not using, rather than the middle of the window.
func _view_anchor() -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(_HUD_WIDTH + _usable_size().x / 2.0, viewport_size.y / 2.0)


## Frames the whole dungeon again. The fit is recomputed from the CURRENT bounds
## rather than cached from startup, so this reframes after the dungeon has grown.
func _reset_view() -> void:
	var world := _dungeon.get_world_bounds()
	var usable := _usable_size()
	_fit_zoom = minf(
		usable.x / world.size.x,
		usable.y / world.size.y) * _CAMERA_FIT_MARGIN
	_camera.zoom = Vector2.ONE * _fit_zoom
	_camera.position = world.get_center() 		- (_view_anchor() - get_viewport_rect().size / 2.0) / _fit_zoom
	_renderer.view_zoom = _fit_zoom


func set_edit_mode(mode: EditMode) -> void:
	_edit_mode = mode
	_renderer.selection_color = _MODE_COLOR[mode]
	_refresh_expandable()


func toggle_edit_mode() -> void:
	set_edit_mode((_edit_mode + 1) % EditMode.size() as EditMode)


## Ghost tiles are only shown in EXPAND mode, so the other modes stay uncluttered.
func _refresh_expandable() -> void:
	_renderer.expandable = _expansion.get_expandable_positions() 		if _edit_mode == EditMode.EXPAND else ([] as Array[Vector2i])


## Buys the tile under the click. One tile per click — expansion is deliberately
## not a drag operation.
func _try_purchase(grid_position: Vector2i) -> void:
	if not _expansion.purchase_tile(grid_position):
		return
	_refresh_expandable()
	_renderer.queue_redraw()
	print("bought %s for %d gold, balance %d, %d tiles"
		% [grid_position, _expansion.tile_cost, _expansion.gold, _dungeon.get_tile_count()])


## Grid coordinate under a screen pixel. Derived from the event position rather
## than the polled mouse, so the tile acted on is always the tile clicked.
func _grid_at(screen_position: Vector2) -> Vector2i:
	var world := _screen_to_world(screen_position, _camera.zoom.x)
	return _dungeon.world_to_grid(_renderer.to_local(world))


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
	var walkable := _edit_mode == EditMode.DELETE
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			# Cells inside the bounding box can be empty once the dungeon has
			# been expanded into a non-rectangular shape.
			var tile := _dungeon.get_tile(Vector2i(x, y))
			if tile != null:
				tile.walkable = walkable
	_renderer.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_drag(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event.position)
			else:
				_end_drag(event.position)
		elif event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_zoom_at(event.position, _ZOOM_STEP)
				MOUSE_BUTTON_WHEEL_DOWN:
					_zoom_at(event.position, 1.0 / _ZOOM_STEP)


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
			_zoom_at(get_viewport_rect().size / 2.0, _ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(get_viewport_rect().size / 2.0, 1.0 / _ZOOM_STEP)
		KEY_R:
			_reset_view()
		KEY_TAB:
			toggle_edit_mode()
