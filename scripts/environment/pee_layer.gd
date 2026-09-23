class_name PeeLayer
extends Node2D

## Draws the urine lying on the floor being viewed.
##
## One sprite per tile, for the life of that tile's puddle. A tile urinated on
## twenty times still has exactly one sprite — it just gets darker — so repeated
## visits cannot pile up nodes.
##
## Reads the tiles and never writes to them. It listens to the floor rather than
## scanning it every frame, so nothing runs per frame at all.

const _TEXTURE: Texture2D = preload("res://assets/environment/rodent_pee.png")
## Amount at which a puddle looks as strong as it ever will.
const _FULL_AT: float = 5.0
const _FAINTEST: float = 0.45

## The floor whose puddles are drawn. Assigning rebuilds from that floor's tiles.
var current_floor: DungeonFloor = null:
	set(value):
		if current_floor != null and current_floor.pee_changed.is_connected(_on_pee_changed):
			current_floor.pee_changed.disconnect(_on_pee_changed)
		current_floor = value
		if current_floor != null:
			current_floor.pee_changed.connect(_on_pee_changed)
		_rebuild()

## Vector2i -> Sprite2D
var _sprites: Dictionary = {}


func get_sprite(grid_position: Vector2i) -> Sprite2D:
	return _sprites.get(grid_position)


## Number of puddles drawn. One per tile, never one per urination.
func get_sprite_count() -> int:
	return _sprites.size()


func _on_pee_changed(grid_position: Vector2i) -> void:
	var tile := current_floor.get_tile(grid_position)
	if tile == null or not tile.has_pee():
		return
	var sprite: Sprite2D = _sprites.get(grid_position)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Pee_%d_%d" % [grid_position.x, grid_position.y]
		sprite.texture = _TEXTURE
		sprite.position = Vector2(grid_position) * Dungeon.TILE_SIZE \
			+ Vector2.ONE * (Dungeon.TILE_SIZE / 2.0)
		add_child(sprite)
		_sprites[grid_position] = sprite
	# More urine darkens the same puddle rather than adding another one.
	sprite.modulate.a = lerpf(_FAINTEST, 1.0, minf(tile.pee_amount / _FULL_AT, 1.0))


func _rebuild() -> void:
	for sprite in _sprites.values():
		sprite.queue_free()
	_sprites.clear()
	if current_floor == null:
		return
	for grid_position in current_floor.get_peed_positions():
		_on_pee_changed(grid_position)
