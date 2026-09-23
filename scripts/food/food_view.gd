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
var view_zoom: float = 1.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label: Label = $Label


func bind(p_food: FoodSource) -> void:
	food = p_food
	name = "Food%d" % food.id
	_sprite.texture = _WATER_TEXTURE if food.is_water() else _TEXTURE
	var drawn_tiles := _WATER_TILES if food.is_water() else _FOOD_TILES
	_sprite.scale = Vector2.ONE * (
		drawn_tiles * Dungeon.TILE_SIZE / _sprite.texture.get_height())
	position = Vector2(food.grid_position) * Dungeon.TILE_SIZE \
		+ Vector2.ONE * (Dungeon.TILE_SIZE / 2.0)
	sync()


## Food does not move, so this only refreshes how much is left.
func sync() -> void:
	if not _label.visible:
		return
	_label.text = "%d" % roundi(food.amount)
	var inverse := 1.0 / view_zoom
	_label.scale = Vector2.ONE * inverse
	_label.size = _label.get_combined_minimum_size()
	_label.position = Vector2(
		-_label.size.x * inverse / 2.0,
		Dungeon.TILE_SIZE * 0.3)


func set_label_visible(value: bool) -> void:
	_label.visible = value
	sync()
