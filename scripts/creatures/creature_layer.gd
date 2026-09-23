class_name CreatureLayer
extends Node2D

## Shows the creatures living on the floor being viewed.
##
## Keeps one [CreatureView] per creature for its whole life and toggles
## visibility on floor switches, rather than rebuilding views. Views of creatures
## on other floors are hidden and skipped each frame; their creatures keep being
## simulated by [CreatureSystem] regardless.

const _VIEW_SCENE: PackedScene = preload("res://scenes/creatures/creature_view.tscn")

## Amber while a hungry creature has found nothing, green once it has a pile in
## sight. Debug only.
const _COLOR_SEARCHING := Color("ffd166")
const _COLOR_FOUND := Color("6fe08a")

## The creatures to show. Assigning builds views for any that already exist.
var system: CreatureSystem = null:
	set(value):
		system = value
		for creature in system.get_creatures():
			_add_view(creature)
		system.creature_spawned.connect(_add_view)
		system.creature_died.connect(_remove_view)

## Only creatures living here are drawn.
var current_floor: DungeonFloor = null:
	set(value):
		current_floor = value
		_refresh_visibility()

var view_zoom: float = 1.0:
	set(value):
		view_zoom = value
		queue_redraw()
		for view in _views.values():
			view.view_zoom = value

## Draws the area each hungry creature can notice food in. Off by default.
var show_detection_area: bool = false:
	set(value):
		show_detection_area = value
		queue_redraw()

var labels_visible: bool = true:
	set(value):
		labels_visible = value
		for view in _views.values():
			view.set_label_visible(value)

## Creature -> CreatureView
var _views: Dictionary = {}


func get_view(creature: Creature) -> CreatureView:
	return _views.get(creature)


func _process(delta: float) -> void:
	for view in _views.values():
		if view.visible:
			view.sync(delta)
	if show_detection_area:
		queue_redraw()


## The tiles a creature could notice food in form a diamond, because distance is
## counted in steps rather than as the crow flies. Drawn before the children, so
## creatures sit on top of it.
func _draw() -> void:
	if not show_detection_area:
		return
	for creature in _views:
		var view: CreatureView = _views[creature]
		if not view.visible or not creature.alive or creature.asleep:
			continue
		if not creature.is_hungry() and creature.food_target == null:
			continue
		var reach: float = (creature.species.food_detection_radius + 0.5) * Dungeon.TILE_SIZE
		var centre := Vector2(creature.grid_position) * Dungeon.TILE_SIZE 			+ Vector2.ONE * (Dungeon.TILE_SIZE / 2.0)
		var diamond := PackedVector2Array([
			centre + Vector2(0, -reach), centre + Vector2(reach, 0),
			centre + Vector2(0, reach), centre + Vector2(-reach, 0),
			centre + Vector2(0, -reach),
		])
		var colour := _COLOR_FOUND if creature.food_target != null else _COLOR_SEARCHING
		draw_polyline(diamond, Color(colour, 0.5), 2.0 / view_zoom)


func _add_view(creature: Creature) -> void:
	var view: CreatureView = _VIEW_SCENE.instantiate()
	add_child(view)
	view.view_zoom = view_zoom
	view.bind(creature)
	view.set_label_visible(labels_visible)
	_views[creature] = view
	_refresh_visibility()


func _remove_view(creature: Creature) -> void:
	var view: CreatureView = _views.get(creature)
	if view == null:
		return
	_views.erase(creature)
	view.queue_free()


func _refresh_visibility() -> void:
	for creature in _views:
		var view: CreatureView = _views[creature]
		var should_show: bool = creature.dungeon_floor == current_floor
		if should_show and not view.visible:
			# It has been off-screen while its creature kept moving; jump to where
			# the creature is now instead of gliding across the floor.
			view.sync(0.0, true)
		view.visible = should_show
