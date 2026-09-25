class_name DungeonRenderer
extends Node2D

## Placeholder visualisation of a [Dungeon]. Throwaway rectangles and lines,
## not art — enough to confirm grid dimensions, tile coordinates, boundaries
## and alignment before real tiles exist.
##
## Reads from the dungeon and never writes to it: the data model stays the
## source of truth. Redraws only when something changes, so it costs nothing
## per frame and the simulation stays independent of rendering.

const _COLOR_BACKDROP := Color("11131a")
const _COLOR_TILE_A := Color("242a38")
const _COLOR_TILE_B := Color("2b3242")
const _COLOR_EMPTY_A := Color("6e737b")
const _COLOR_EMPTY_B := Color("7c828b")
const _COLOR_GRID_LINE := Color(1, 1, 1, 0.06)
const _COLOR_MAJOR_LINE := Color(1, 1, 1, 0.18)
const _COLOR_BORDER := Color("7fd1c8")
const _COLOR_HOVER := Color("ffd166")
const _COLOR_LABEL := Color(1, 1, 1, 0.45)
const _COLOR_EXPAND := Color("6fe08a")
const _COLOR_EXPAND_FILL := Color("6fe08a", 0.14)

## Heavier line and axis label every this many tiles once the grid is too big
## to mark every one. Small grids use a step of 1 — see [method _step_for].
const _MAJOR_EVERY: int = 5
## At or below this many tiles on an axis, mark every tile instead.
const _MARK_EVERY_TILE_BELOW: int = 12
## Target on-screen size of the axis labels, in pixels.
const _LABEL_SIZE: int = 14

## The dungeon to visualise. Assigning re-renders.
var dungeon: Dungeon = null:
	set(value):
		dungeon = value
		queue_redraw()

## Scale the camera applies to this node. Lines and labels are divided by it so
## they render at a constant SCREEN size instead of being magnified along with
## the grid — without this the decorations are unreadable at any zoom but one.
var view_zoom: float = 1.0:
	set(value):
		var clamped := maxf(value, 0.001)
		if is_equal_approx(clamped, view_zoom):
			return
		view_zoom = clamped
		queue_redraw()

## Vertical squash the world is drawn with. The tiles themselves should squash —
## they are the ground — but the axis labels are text about the grid rather than
## part of it, so they are drawn back out of the squash. See [CameraRig].
var view_tilt: float = 1.0:
	set(value):
		var clamped := maxf(value, 0.001)
		if is_equal_approx(clamped, view_tilt):
			return
		view_tilt = clamped
		queue_redraw()

## Draws the measuring aids — per-tile lines and axis coordinates — which belong
## to a view you are building in, not one you are watching creatures live in.
var show_grid: bool = true:
	set(value):
		if value == show_grid:
			return
		show_grid = value
		queue_redraw()

## Positions offered for purchase, drawn as ghost tiles. Supplied by the caller;
## the renderer does not know what expansion is or what it costs.
var expandable: Array[Vector2i] = []:
	set(value):
		expandable = value
		queue_redraw()

## Tint of the drag preview. Set by the caller so the preview can signal what
## the drag will do; the renderer itself has no notion of edit modes.
var selection_color: Color = Color("ffd166"):
	set(value):
		if value == selection_color:
			return
		selection_color = value
		queue_redraw()

## Area being dragged out, in grid coordinates. An empty rect means no drag in
## progress. Drawn as a preview only — the drag does not touch the data model
## until it is released.
var selection: Rect2i = Rect2i():
	set(value):
		if value == selection:
			return
		selection = value
		queue_redraw()

## Tile currently under the mouse, or any Vector2i outside the dungeon for none.
## Set by the debug harness to prove world -> grid conversion visually.
var hover_tile: Vector2i = Vector2i(-1, -1):
	set(value):
		if value == hover_tile:
			return
		hover_tile = value
		queue_redraw()


func _draw() -> void:
	if dungeon == null:
		return

	var tile_size := Dungeon.TILE_SIZE
	var bounds := dungeon.get_bounds()
	var thin := 1.0 / view_zoom
	var cell := Vector2(tile_size, tile_size)

	# Tiles, straight from the data model. The bounding box is only an iteration
	# range: cells inside it can be empty once the dungeon has been expanded.
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var pos := Vector2i(x, y)
			var tile := dungeon.get_tile(pos)
			if tile == null:
				continue
			var even := (x + y) % 2 == 0
			# Grey where nothing is built yet, dark where floor has been placed.
			# The checker is kept either way so individual tiles stay countable.
			var color := (_COLOR_TILE_A if even else _COLOR_TILE_B)
			if tile.terrain == DungeonTile.Terrain.EMPTY:
				color = _COLOR_EMPTY_A if even else _COLOR_EMPTY_B
			var rect := Rect2(dungeon.grid_to_world(pos), cell)
			draw_rect(rect, color)
			if show_grid:
				draw_rect(rect, _COLOR_GRID_LINE if x % _step_for(bounds.size.x) != 0 					and y % _step_for(bounds.size.y) != 0 else _COLOR_MAJOR_LINE, false, thin)

	# Ghosts for anything on offer.
	for pos in expandable:
		var rect := Rect2(dungeon.grid_to_world(pos), cell)
		draw_rect(rect, _COLOR_EXPAND_FILL)
		draw_rect(rect, _COLOR_EXPAND, false, 2.0 * thin)

	# Outline every edge where a tile meets empty space. This IS the dungeon
	# boundary, which stops being a rectangle as soon as a tile is bought.
	for position in dungeon.get_positions():
		var origin := dungeon.grid_to_world(position)
		if not dungeon.is_valid_position(position + Vector2i.UP):
			draw_line(origin, origin + Vector2(tile_size, 0), _COLOR_BORDER, 2.0 * thin)
		if not dungeon.is_valid_position(position + Vector2i.DOWN):
			draw_line(origin + Vector2(0, tile_size), origin + cell, _COLOR_BORDER, 2.0 * thin)
		if not dungeon.is_valid_position(position + Vector2i.LEFT):
			draw_line(origin, origin + Vector2(0, tile_size), _COLOR_BORDER, 2.0 * thin)
		if not dungeon.is_valid_position(position + Vector2i.RIGHT):
			draw_line(origin + Vector2(tile_size, 0), origin + cell, _COLOR_BORDER, 2.0 * thin)

	if dungeon.is_valid_position(hover_tile) or expandable.has(hover_tile):
		draw_rect(Rect2(dungeon.grid_to_world(hover_tile), cell),
			_COLOR_HOVER, false, 2.0 * thin)

	if selection.has_area():
		var sel := Rect2(
			Vector2(selection.position) * tile_size,
			Vector2(selection.size) * tile_size)
		draw_rect(sel, Color(selection_color, 0.22))
		draw_rect(sel, selection_color, false, 3.0 / view_zoom)

	if show_grid:
		_draw_axis_labels(bounds, tile_size)


## Marks every tile on a small axis, every [constant _MAJOR_EVERY] on a big one.
func _step_for(dimension: int) -> int:
	return 1 if dimension <= _MARK_EVERY_TILE_BELOW else _MAJOR_EVERY


## Column and row numbers outside the grid, plus the two corner coordinates, so
## tile coordinates can be checked against what the data model reports. Keyed to
## the bounding box, whose origin is not necessarily (0,0) after expansion.
##
## Drawn under an inverse-scale transform: the text rasterises at its true pixel
## size and is then scaled back down by the camera, rather than being rendered
## small and magnified into a blur (or rendered huge and clipped).
func _draw_axis_labels(bounds: Rect2i, tile_size: int) -> void:
	var font := ThemeDB.fallback_font
	var top_left := Vector2(bounds.position) * tile_size
	# Undoes the camera zoom AND the world's vertical squash, so the text is
	# neither magnified nor flattened while the view is tipping.
	draw_set_transform(Vector2.ZERO, 0.0,
		Vector2(1.0 / view_zoom, 1.0 / (view_zoom * view_tilt)))

	for x in range(bounds.position.x, bounds.end.x, _step_for(bounds.size.x)):
		draw_string(font,
			_label_point(Vector2(x * tile_size, top_left.y)) + Vector2(3, -6),
			str(x), HORIZONTAL_ALIGNMENT_LEFT, -1, _LABEL_SIZE, _COLOR_LABEL)
	for y in range(bounds.position.y, bounds.end.y, _step_for(bounds.size.y)):
		draw_string(font,
			_label_point(Vector2(top_left.x, y * tile_size)) + Vector2(-26, _LABEL_SIZE),
			str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, _LABEL_SIZE, _COLOR_LABEL)

	draw_string(font, _label_point(top_left) + Vector2(3, -22),
		"(%d,%d)" % [bounds.position.x, bounds.position.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, _LABEL_SIZE, _COLOR_BORDER)
	var last := bounds.end - Vector2i.ONE
	draw_string(font,
		_label_point(Vector2(last.x * tile_size, bounds.end.y * tile_size))
			+ Vector2(-30, 18),
		"(%d,%d)" % [last.x, last.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, _LABEL_SIZE, _COLOR_BORDER)

	draw_set_transform_matrix(Transform2D.IDENTITY)


## A world point in the coordinate space of the label transform above, which
## cancels it — so the pixel offsets added afterwards are plain screen pixels.
func _label_point(world_position: Vector2) -> Vector2:
	return Vector2(
		world_position.x * view_zoom,
		world_position.y * view_zoom * view_tilt)
