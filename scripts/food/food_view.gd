class_name FoodView
extends Node2D

## Draws one [FoodSource] sitting on its tile. Reads the model, never changes it.
##
## The sprite is preloaded here because there is exactly one kind of food. When
## food types arrive, the texture moves into a resource the way creature sprites
## live on [CreatureSpecies].

const _TEXTURE: Texture2D = preload("res://assets/food/Icon43.png")
const _WATER_TEXTURE: Texture2D = preload("res://assets/environment/water.png")
## Food is an object resting on a tile, so it is drawn smaller than one. Water
## is the tile's surface, so it fills it.
const _FOOD_TILES: float = 0.8
const _WATER_TILES: float = 1.0

var food: FoodSource
## Camera zoom, so the label stays a readable screen size at any zoom.
var view_zoom: float = 1.0:
	set(value):
		view_zoom = value
		if food != null:
			sync()
## Vertical squash the world is being drawn with. Water ignores it — water IS
## the floor, so it tips away with the floor. Food does not: it is an object
## standing on the floor. See [CameraRig].
var view_tilt: float = 1.0:
	set(value):
		view_tilt = value
		if food != null:
			sync()
## 0 draws food centred on its tile, 1 stands it on the tile.
var ground_anchor: float = 0.0:
	set(value):
		ground_anchor = value
		if food != null:
			sync()

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label: Label = $Label

## Unsquashed size the sprite is drawn at, before the tilt is countered.
var _base_scale: float = 1.0
## How far the sprite was raised to stand it on its tile, in local pixels.
var _lift: float = 0.0


func bind(p_food: FoodSource) -> void:
	food = p_food
	name = "Food%d" % food.id
	_sprite.texture = _WATER_TEXTURE if food.is_water() else _TEXTURE
	var drawn_tiles := _WATER_TILES if food.is_water() else _FOOD_TILES
	_base_scale = drawn_tiles * Dungeon.TILE_SIZE / _sprite.texture.get_height()
	# Water lies under anything standing on it, whatever their tile positions
	# say, so it is kept out of the depth sort rather than merged into it. It
	# still has to be ABOVE the floor it covers, which is why the dungeon and
	# the stains on it sit lower again — see the layer order in main.tscn.
	z_index = -1 if food.is_water() else 0
	position = Vector2(food.grid_position) * Dungeon.TILE_SIZE \
		+ Vector2.ONE * (Dungeon.TILE_SIZE / 2.0)
	sync()


## Food does not move, so this only refreshes how it is presented and how much
## is left.
func sync() -> void:
	_update_sprite()
	_update_label()


func set_label_visible(value: bool) -> void:
	_label.visible = value
	sync()


## Water is ground and squashes with the floor. Food is an object, so it is
## scaled back up and stood on its tile — which also gives the depth sort a
## ground contact point to sort by.
func _update_sprite() -> void:
	if food.is_water():
		_sprite.scale = Vector2.ONE * _base_scale
		_sprite.offset.y = 0.0
		_lift = 0.0
		return
	var height := _sprite.texture.get_height()
	var upright := _base_scale / maxf(view_tilt, 0.001)
	_sprite.scale = Vector2(_base_scale, upright)
	_sprite.offset.y = -height * 0.5 * ground_anchor
	_lift = height * upright * 0.5 * ground_anchor


func _update_label() -> void:
	if not _label.visible:
		return
	_label.text = "%d" % roundi(food.amount)
	var inverse := 1.0 / view_zoom
	_label.scale = Vector2(inverse, inverse / maxf(view_tilt, 0.001))
	_label.size = _label.get_combined_minimum_size()
	_label.position = Vector2(
		-_label.size.x * inverse / 2.0,
		Dungeon.TILE_SIZE * 0.3 - _lift)
