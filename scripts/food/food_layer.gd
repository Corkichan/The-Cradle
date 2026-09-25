class_name FoodLayer
extends Node2D

## Shows the food lying on the floor being viewed.
##
## Mirrors [CreatureLayer]: one view per source, hidden rather than rebuilt when
## the player changes floor, and freed when the source is eaten.

const _VIEW_SCENE: PackedScene = preload("res://scenes/food/food_view.tscn")

## The food to show. Assigning builds views for anything already placed.
var system: FoodSystem = null:
	set(value):
		system = value
		for food in system.get_sources():
			_add_view(food)
		system.food_placed.connect(_add_view)
		system.food_depleted.connect(_remove_view)

## Only food lying here is drawn.
var current_floor: DungeonFloor = null:
	set(value):
		current_floor = value
		_refresh_visibility()

var view_zoom: float = 1.0:
	set(value):
		if is_equal_approx(value, view_zoom):
			return
		view_zoom = value
		for view in _views.values():
			view.view_zoom = value

## Vertical squash the world is drawn with. Each view decides what to do with
## it: water tips away with the floor, food stands back up.
var view_tilt: float = 1.0:
	set(value):
		if is_equal_approx(value, view_tilt):
			return
		view_tilt = value
		for view in _views.values():
			view.view_tilt = value

## How far food stands on its tile rather than sits centred on it.
var ground_anchor: float = 0.0:
	set(value):
		if is_equal_approx(value, ground_anchor):
			return
		ground_anchor = value
		for view in _views.values():
			view.ground_anchor = value

var labels_visible: bool = true:
	set(value):
		labels_visible = value
		for view in _views.values():
			view.set_label_visible(value)

## FoodSource -> FoodView
var _views: Dictionary = {}


func get_view(food: FoodSource) -> FoodView:
	return _views.get(food)


## Refreshes the remaining-amount labels. Cheap, and only the visible ones.
func refresh() -> void:
	for view in _views.values():
		if view.visible:
			view.sync()


func _add_view(food: FoodSource) -> void:
	var view: FoodView = _VIEW_SCENE.instantiate()
	add_child(view)
	view.view_zoom = view_zoom
	view.view_tilt = view_tilt
	view.ground_anchor = ground_anchor
	view.bind(food)
	view.set_label_visible(labels_visible)
	_views[food] = view
	_refresh_visibility()


func _remove_view(food: FoodSource) -> void:
	var view: FoodView = _views.get(food)
	if view == null:
		return
	_views.erase(food)
	view.queue_free()


func _refresh_visibility() -> void:
	for food in _views:
		var view: FoodView = _views[food]
		view.visible = food.dungeon_floor == current_floor
