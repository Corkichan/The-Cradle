class_name CreatureLayer
extends Node2D

## Shows the creatures living on the floor being viewed.
##
## Keeps one [CreatureView] per creature for its whole life and toggles
## visibility on floor switches, rather than rebuilding views. Views of creatures
## on other floors are hidden and skipped each frame; their creatures keep being
## simulated by [CreatureSystem] regardless.

const _VIEW_SCENE: PackedScene = preload("res://scenes/creatures/creature_view.tscn")

## The creatures to show. Assigning builds views for any that already exist.
var system: CreatureSystem = null:
	set(value):
		system = value
		for creature in system.get_creatures():
			_add_view(creature)
		system.creature_spawned.connect(_add_view)

## Only creatures living here are drawn.
var current_floor: DungeonFloor = null:
	set(value):
		current_floor = value
		_refresh_visibility()

var view_zoom: float = 1.0:
	set(value):
		view_zoom = value
		for view in _views.values():
			view.view_zoom = value

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


func _add_view(creature: Creature) -> void:
	var view: CreatureView = _VIEW_SCENE.instantiate()
	add_child(view)
	view.view_zoom = view_zoom
	view.bind(creature)
	view.set_label_visible(labels_visible)
	_views[creature] = view
	_refresh_visibility()


func _refresh_visibility() -> void:
	for creature in _views:
		var view: CreatureView = _views[creature]
		var should_show: bool = creature.dungeon_floor == current_floor
		if should_show and not view.visible:
			# It has been off-screen while its creature kept moving; jump to where
			# the creature is now instead of gliding across the floor.
			view.sync(0.0, true)
		view.visible = should_show
