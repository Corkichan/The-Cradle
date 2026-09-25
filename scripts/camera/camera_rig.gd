class_name CameraRig
extends Camera2D

## Reusable camera for a 2D world that can be presented at different angles.
##
## Owns framing only: where the view looks, how far in it is zoomed, and how
## steeply the ground is being viewed. It never touches the simulation, never
## asks the dungeon how big it is, and never changes a grid coordinate — the
## world is authored and simulated in one flat coordinate system, and this rig
## only decides how that system is shown.
##
## [b]The angle is one number.[/b] [member tilt] squashes the world vertically:
## 1.0 is straight down, lower values look at the floor from further forward.
## The rig does not apply it — whoever owns the world scene does, because only
## that scene knows which of its nodes are ground and which are standing up.
## See [method get_tilt] and [method get_ground_anchor].
##
## [b]Focus is stored untilted.[/b] [member _focus] is a plain world coordinate;
## the squash is applied only when the camera position is computed. Without this
## the world would slide up the screen as the angle changed, and every screen
## to grid conversion would need to know about the angle.
##
## A new presentation mode is a new entry in [method _preset_for] — zoom, angle
## and ground anchoring are data, so adding one does not touch movement,
## clamping or input.

## The ways the world can be presented. Each is a preset, not a code path.
enum View {
	GAMEPLAY, ## Angled, closer in. Readability of a living world.
	BUILD, ## Straight down, framed wide. Judging layout and distance.
}

@export_group("Bounds")
## World-space rectangle the view is kept over. Supplied by the owner every time
## the world changes shape; the rig has no idea what a tile or a dungeon is, so
## the same rig frames an 8x5 prototype and a 200x200 dungeon unchanged.
@export var world_bounds: Rect2 = Rect2(0, 0, 256, 160):
	set(value):
		world_bounds = value
		if is_inside_tree():
			_refit()
## How far past the edge of the world the view may travel, in world pixels.
## Some overshoot makes edge tiles reachable without fighting the clamp.
@export var bounds_padding: float = 48.0
## Fraction of the usable viewport the bounds fill when the view is framed.
@export var fit_margin: float = 0.88
## Screen pixels reserved on each side as (left, top, right, bottom). The world
## is centred in what is left, so a HUD strip never covers it.
@export var view_margins: Vector4 = Vector4.ZERO

@export_group("Zoom")
## Zoom limits as multiples of the zoom that frames the whole world top-down.
## Expressed as multiples rather than absolutes so they stay meaningful when the
## world grows.
@export var zoom_min_factor: float = 0.5
@export var zoom_max_factor: float = 12.0
## Multiplier applied per wheel notch or key press.
@export var zoom_step: float = 1.15
## How fast zoom catches up to the notch just given. Higher is snappier.
@export var zoom_responsiveness: float = 16.0

@export_group("Edge scrolling")
@export var edge_scroll_enabled: bool = true
## Width of the sensitive band at each screen edge, as a fraction of the
## viewport. Scrolling ramps up across the band rather than starting at full
## speed, so a cursor that only just enters it nudges instead of bolting.
@export_range(0.0, 0.5) var edge_scroll_margin: float = 0.12
## Top speed at the very edge, in SCREEN pixels per second. Screen rather than
## world, so the view travels the same visible distance at any zoom or angle.
@export var edge_scroll_speed: float = 900.0
## How fast scrolling accelerates and decelerates. Higher is more immediate.
@export var edge_scroll_responsiveness: float = 9.0

@export_group("Views")
## Seconds the move between views takes. The view is not teleported: the angle,
## the zoom and the focus are interpolated together, so the camera reads as
## rising into a plan view rather than cutting to one.
@export var transition_duration: float = 0.55
@export var gameplay_tilt: float = 0.5
## Multiples of the zoom that frames the world in that view. Above 1.0 the
## world no longer fits, which on a dungeon this small means panning to see the
## far side — so the gameplay view sits only slightly closer than the plan view.
@export var gameplay_zoom_factor: float = 1.1
@export var build_tilt: float = 1.0
@export var build_zoom_factor: float = 1.0

@export_group("Following")
## How fast the view closes on whatever it is following. Low enough that the
## camera trails its subject rather than being welded to it, which reads as a
## camera operator keeping up rather than the world sliding around.
@export var follow_responsiveness: float = 6.0
## Zoom used when following something, as a multiple of the framed zoom. Kept
## modest: close enough to read the creature, wide enough to still see what it
## is walking towards.
@export var inspect_zoom_factor: float = 2.0

var _view: View = View.GAMEPLAY

## Untilted world point shown at [method _anchor_screen].
var _focus: Vector2 = Vector2.ZERO
var _zoom_level: float = 1.0
## Zoom the camera is easing toward, set in whole notches by the wheel.
var _zoom_target: float = 1.0
## Screen pixel the easing zoom keeps pinned — the cursor, usually.
var _zoom_anchor: Vector2 = Vector2.ZERO
var _tilt: float = 1.0
## 0 draws a thing centred on its tile, 1 stands it on the tile. Interpolated
## with the angle so objects rise onto their feet as the view tips forward.
var _ground_anchor: float = 0.0

var _scroll_velocity: Vector2 = Vector2.ZERO
var _panning: bool = false

## Returns the world point to keep in view, or empty when free. A function
## rather than a node reference, so the rig can follow anything that can say
## where it is without knowing what it is.
var _follow: Callable = Callable()

## 1.0 when settled. Below that, a view change is in progress and user camera
## input is ignored — the two would fight over the same focus.
var _progress: float = 1.0
var _from: Dictionary = {}
var _to: Dictionary = {}
## View -> where the player last left it, so returning to a view returns to the
## spot they were looking at rather than resetting them to the middle.
var _saved: Dictionary = {}


func _ready() -> void:
	# Runs before the scene that reads the angle back, so presentation never
	# lags the camera by a frame.
	process_priority = -100
	get_viewport().size_changed.connect(_refit)
	_tilt = _preset_for(_view)["tilt"]
	_ground_anchor = _preset_for(_view)["ground_anchor"]
	_refit()
	_frame_current(true)


func get_view() -> View:
	return _view


## True while a view change is playing.
func is_transitioning() -> bool:
	return _progress < 1.0


## Vertical squash of the world: 1.0 straight down, less looking forward.
func get_tilt() -> float:
	return _tilt


## How far standing objects should be stood on their tile rather than centred
## on it. See [member _ground_anchor].
func get_ground_anchor() -> float:
	return _ground_anchor


func get_zoom_level() -> float:
	return _zoom_level


## Current zoom as a multiple of the framed-top-down zoom, for readouts.
func get_zoom_ratio() -> float:
	return _zoom_level / _base_zoom()


func get_min_zoom() -> float:
	return _base_zoom() * zoom_min_factor


func get_max_zoom() -> float:
	return _base_zoom() * zoom_max_factor


## Changes how the world is presented. The world itself is untouched: nothing is
## rebuilt, reset or recreated, so creatures, traces and the clock carry on
## through the move.
func set_view(value: View, instant: bool = false) -> void:
	if value == _view:
		return
	_saved[_view] = {"focus": _focus, "zoom": _zoom_level}
	_view = value
	var remembered: Dictionary = _saved.get(value, {})
	_begin(
		remembered.get("focus", world_bounds.get_center()),
		remembered.get("zoom", _fit_zoom_for(value) * _preset_for(value)["zoom_factor"]),
		instant)


## Keeps [param point_source]'s answer in view until the player takes over or
## [method stop_following] is called. Zooming stays available while following;
## panning and edge scrolling end it, because those ARE taking over.
func follow(point_source: Callable, zoom_factor: float = 0.0) -> void:
	if not point_source.is_valid():
		return
	_follow = point_source
	var factor := zoom_factor if zoom_factor > 0.0 else inspect_zoom_factor
	_zoom_anchor = _anchor_screen()
	_zoom_target = clampf(_fit_zoom_for(_view) * factor,
		get_min_zoom(), get_max_zoom())


func stop_following() -> void:
	_follow = Callable()


func is_following() -> bool:
	return _follow.is_valid()


func toggle_view() -> void:
	set_view(View.BUILD if _view == View.GAMEPLAY else View.GAMEPLAY)


## Frames the whole world again in the current view, forgetting where the player
## had wandered to. Recomputed from the CURRENT bounds, so it reframes after the
## world has grown.
func reset_view(instant: bool = false) -> void:
	_refit()
	_saved.erase(_view)
	_frame_current(instant)


## Zooms by [param factor], keeping whatever is under [param screen_position]
## pinned there while the zoom eases in.
func zoom_at(screen_position: Vector2, factor: float) -> void:
	if is_transitioning():
		return
	_zoom_anchor = screen_position
	_zoom_target = clampf(_zoom_target * factor, get_min_zoom(), get_max_zoom())


## Screen pixel -> world coordinate, in the ONE authoritative coordinate system
## the simulation uses. The angle is undone here, so callers convert a click to
## a tile the same way in every view.
##
## Computed from the rig's own state rather than the camera transform, which
## only refreshes at the end of a frame and would answer for the previous one.
func screen_to_world(screen_position: Vector2) -> Vector2:
	return _screen_to_world(screen_position, _focus, _zoom_level, _tilt)


## World coordinate -> screen pixel. The inverse of [method screen_to_world].
func world_to_screen(world_position: Vector2) -> Vector2:
	var offset := Vector2(
		world_position.x - _focus.x,
		(world_position.y - _focus.y) * _tilt)
	return _anchor_screen() + offset * _zoom_level


func _process(delta: float) -> void:
	if _progress < 1.0:
		_advance_transition(delta)
	else:
		_advance_zoom(delta)
		# Edge scrolling runs first and gets to cancel the follow, so pushing the
		# cursor at an edge takes the camera back however it was being driven.
		_advance_edge_scroll(delta)
		if is_following():
			_advance_follow(delta)
	_focus = _clamp_focus(_focus, _zoom_level, _tilt)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed and not is_transitioning()
			if _panning:
				# Taking the camera by hand lets go of whatever it was watching.
				stop_following()
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(event.position, zoom_step)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(event.position, 1.0 / zoom_step)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _panning:
		# Drag the world with the pointer. The screen movement is converted back
		# through zoom and angle so the point grabbed stays under the cursor.
		_focus -= Vector2(event.relative.x, event.relative.y / _tilt) / _zoom_level
		get_viewport().set_input_as_handled()


## The presentation settings of a view. Everything that makes a view a view
## lives here, so a new one is data rather than a new code path.
func _preset_for(view: View) -> Dictionary:
	if view == View.BUILD:
		return {
			"tilt": build_tilt,
			"ground_anchor": 0.0,
			"zoom_factor": build_zoom_factor,
		}
	return {
		"tilt": gameplay_tilt,
		"ground_anchor": 1.0,
		"zoom_factor": gameplay_zoom_factor,
	}


func _viewport_size() -> Vector2:
	return get_viewport_rect().size


## Viewport minus the reserved strips.
func _usable_size() -> Vector2:
	var vp := _viewport_size()
	return Vector2(
		maxf(vp.x - view_margins.x - view_margins.z, 1.0),
		maxf(vp.y - view_margins.y - view_margins.w, 1.0))


## Screen pixel the focus point sits on: the middle of the area nothing has
## reserved, rather than the middle of the window.
func _anchor_screen() -> Vector2:
	var usable := _usable_size()
	return Vector2(view_margins.x + usable.x / 2.0, view_margins.y + usable.y / 2.0)


## Zoom that frames the whole world in [param view]. A squashed world is
## shorter, so an angled view can sit closer than a top-down one.
func _fit_zoom_for(view: View) -> float:
	var usable := _usable_size()
	var tilt_value: float = _preset_for(view)["tilt"]
	return minf(
		usable.x / maxf(world_bounds.size.x, 1.0),
		usable.y / maxf(world_bounds.size.y * tilt_value, 1.0)) * fit_margin


## The zoom the limits and the HUD ratio are measured against. Fixed to the
## top-down fit so the limits do not shift underfoot when the view changes.
func _base_zoom() -> float:
	return _fit_zoom_for(View.BUILD)


## Recomputes what "framed" means after the world or the window changed shape,
## and pulls the current zoom back inside the new limits.
func _refit() -> void:
	_zoom_target = clampf(_zoom_target, get_min_zoom(), get_max_zoom())
	_zoom_level = clampf(_zoom_level, get_min_zoom(), get_max_zoom())


func _frame_current(instant: bool) -> void:
	var preset := _preset_for(_view)
	_begin(world_bounds.get_center(),
		_fit_zoom_for(_view) * preset["zoom_factor"], instant)


func _begin(to_focus: Vector2, to_zoom: float, instant: bool) -> void:
	var preset := _preset_for(_view)
	_from = {
		"focus": _focus, "zoom": _zoom_level,
		"tilt": _tilt, "ground_anchor": _ground_anchor,
	}
	_to = {
		"focus": to_focus,
		"zoom": clampf(to_zoom, get_min_zoom(), get_max_zoom()),
		"tilt": preset["tilt"],
		"ground_anchor": preset["ground_anchor"],
	}
	_panning = false
	_scroll_velocity = Vector2.ZERO
	_follow = Callable()
	_progress = 0.0
	if instant or transition_duration <= 0.0:
		_progress = 1.0
		_settle()


func _advance_transition(delta: float) -> void:
	_progress = minf(_progress + delta / maxf(transition_duration, 0.001), 1.0)
	# Eased at both ends, so the camera leaves and arrives gently instead of
	# starting and stopping dead.
	var weight := smoothstep(0.0, 1.0, _progress)
	_focus = (_from["focus"] as Vector2).lerp(_to["focus"], weight)
	_zoom_level = lerpf(_from["zoom"], _to["zoom"], weight)
	_tilt = lerpf(_from["tilt"], _to["tilt"], weight)
	_ground_anchor = lerpf(_from["ground_anchor"], _to["ground_anchor"], weight)
	if _progress >= 1.0:
		_settle()


func _settle() -> void:
	_focus = _to["focus"]
	_zoom_level = _to["zoom"]
	_zoom_target = _zoom_level
	_tilt = _to["tilt"]
	_ground_anchor = _to["ground_anchor"]
	_focus = _clamp_focus(_focus, _zoom_level, _tilt)
	_apply()


func _advance_zoom(delta: float) -> void:
	if is_equal_approx(_zoom_level, _zoom_target):
		return
	var before := screen_to_world(_zoom_anchor)
	_zoom_level = lerpf(_zoom_level, _zoom_target,
		1.0 - exp(-zoom_responsiveness * delta))
	# Snap the last sliver so the easing actually finishes instead of creeping.
	if absf(_zoom_level - _zoom_target) < _zoom_target * 0.002:
		_zoom_level = _zoom_target
	# Whatever was under the anchor has drifted now that the scale changed; move
	# the focus by exactly that drift to put it back.
	_focus += before - screen_to_world(_zoom_anchor)


func _advance_follow(delta: float) -> void:
	var target: Variant = _follow.call()
	if typeof(target) != TYPE_VECTOR2:
		# Whatever was being followed can no longer say where it is.
		stop_following()
		return
	_scroll_velocity = Vector2.ZERO
	_focus = _focus.lerp(target, 1.0 - exp(-follow_responsiveness * delta))


func _advance_edge_scroll(delta: float) -> void:
	var desired := Vector2.ZERO
	if edge_scroll_enabled and not _panning and _pointer_inside():
		var vp := _viewport_size()
		var mouse := get_viewport().get_mouse_position()
		desired = Vector2(
			_edge_push(mouse.x, vp.x),
			_edge_push(mouse.y, vp.y)) * edge_scroll_speed
		if desired != Vector2.ZERO:
			# Steering by hand lets go of whatever was being watched.
			stop_following()
	_scroll_velocity = _scroll_velocity.lerp(desired,
		1.0 - exp(-edge_scroll_responsiveness * delta))
	if desired == Vector2.ZERO and _scroll_velocity.length() < 1.0:
		_scroll_velocity = Vector2.ZERO
	if _scroll_velocity == Vector2.ZERO:
		return
	# Screen pixels per second back into world units, through zoom and angle.
	_focus += Vector2(_scroll_velocity.x, _scroll_velocity.y / _tilt) \
		* delta / _zoom_level


## -1..1 push away from an edge, ramping across the sensitive band.
func _edge_push(position_on_axis: float, axis_size: float) -> float:
	var band := axis_size * edge_scroll_margin
	if band <= 0.0:
		return 0.0
	if position_on_axis < band:
		return -clampf(1.0 - position_on_axis / band, 0.0, 1.0)
	if position_on_axis > axis_size - band:
		return clampf(1.0 - (axis_size - position_on_axis) / band, 0.0, 1.0)
	return 0.0


## Edge scrolling must not creep while the pointer is somewhere else entirely,
## or the view drifts away while the player is using another window.
func _pointer_inside() -> bool:
	if not get_window().has_focus():
		return false
	return Rect2(Vector2.ZERO, _viewport_size()).has_point(
		get_viewport().get_mouse_position())


func _screen_to_world(screen_position: Vector2, focus: Vector2,
		zoom_value: float, tilt_value: float) -> Vector2:
	var offset := (screen_position - _anchor_screen()) / zoom_value
	return Vector2(focus.x + offset.x, focus.y + offset.y / tilt_value)


## The slab of world currently on screen, in untilted world coordinates.
func _visible_world_rect(focus: Vector2, zoom_value: float,
		tilt_value: float) -> Rect2:
	var top_left := _screen_to_world(Vector2.ZERO, focus, zoom_value, tilt_value)
	var bottom_right := _screen_to_world(
		_viewport_size(), focus, zoom_value, tilt_value)
	return Rect2(top_left, bottom_right - top_left)


## Keeps the visible slab over the world. A world smaller than the view is
## centred instead of clamped, so a tiny dungeon does not get shoved into a
## corner by its own bounds.
func _clamp_focus(focus: Vector2, zoom_value: float, tilt_value: float) -> Vector2:
	var allowed := world_bounds.grow(bounds_padding)
	var visible := _visible_world_rect(focus, zoom_value, tilt_value)
	var shift := Vector2.ZERO
	for axis in 2:
		if visible.size[axis] >= allowed.size[axis]:
			# Too big to pan: sit the middle of the world on the view anchor, not
			# in the middle of the window, or a reserved strip covers it.
			shift[axis] = allowed.get_center()[axis] - focus[axis]
		elif visible.position[axis] < allowed.position[axis]:
			shift[axis] = allowed.position[axis] - visible.position[axis]
		elif visible.end[axis] > allowed.end[axis]:
			shift[axis] = allowed.end[axis] - visible.end[axis]
	return focus + shift


## Pushes the rig's state onto the Camera2D. The squash is applied ONLY here:
## everywhere else the focus is a plain world coordinate.
func _apply() -> void:
	position = Vector2(_focus.x, _focus.y * _tilt) \
		- (_anchor_screen() - _viewport_size() / 2.0) / _zoom_level
	zoom = Vector2.ONE * _zoom_level
