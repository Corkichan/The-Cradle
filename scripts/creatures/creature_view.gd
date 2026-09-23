class_name CreatureView
extends Node2D

## Draws one [Creature]. Reads the model; never changes it.
##
## The model moves in simulation ticks (20 per second at 1x), which would look
## steppy if copied straight to the screen, so the sprite eases toward the
## model's position every frame. That easing is purely cosmetic: it cannot move
## a creature anywhere the simulation did not, and when the simulation pauses
## the target stops and the sprite settles onto it.

## Higher is snappier. Tuned so a step still reads as a step at 10x speed.
const _FOLLOW_RATE: float = 18.0

var creature: Creature
## Camera zoom, so the label stays a readable screen size at any zoom.
var view_zoom: float = 1.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label: Label = $Label

var _last_horizontal: int = -1


func bind(p_creature: Creature) -> void:
	creature = p_creature
	name = "Creature%d" % creature.id
	var species := creature.species
	var reference_height := species.front_texture.get_height()
	var drawn_height := species.display_height_tiles * Dungeon.TILE_SIZE
	_sprite.scale = Vector2.ONE * (drawn_height / reference_height)
	_last_horizontal = -1 if species.side_faces_left else 1
	sync(0.0, true)


## Updates the drawing from the model. [param snap] skips easing, for when the
## view appears and should not slide in from wherever it last was.
func sync(delta: float, snap: bool = false) -> void:
	var target := _model_position()
	if snap:
		position = target
	else:
		position = position.lerp(target, 1.0 - exp(-_FOLLOW_RATE * delta))
	_update_sprite()
	_update_label()


func set_label_visible(value: bool) -> void:
	_label.visible = value


## Where the model says the creature is, part-way across a step if stepping.
func _model_position() -> Vector2:
	var half := Vector2.ONE * (Dungeon.TILE_SIZE / 2.0)
	var from := Vector2(creature.grid_position) * Dungeon.TILE_SIZE + half
	var to := Vector2(creature.move_target) * Dungeon.TILE_SIZE + half
	return from.lerp(to, creature.move_progress)


## Side sprite for east, west and (lacking a back sprite) north; front sprite
## for south. The side sprite is flipped by whichever way it natively faces, so
## art drawn facing either direction works.
func _update_sprite() -> void:
	var species := creature.species
	if creature.facing.x != 0:
		_last_horizontal = creature.facing.x
	if creature.facing == Vector2i.DOWN:
		_sprite.texture = species.front_texture
		_sprite.flip_h = false
	else:
		_sprite.texture = species.side_texture
		var art_direction := -1 if species.side_faces_left else 1
		_sprite.flip_h = _last_horizontal != art_direction


func _update_label() -> void:
	if not _label.visible:
		return
	_label.text = "%s #%d  %s\nAge %ds  Hunger %d  Water %d" % [
		creature.get_species_name(), creature.id, Creature.State.keys()[creature.state],
		int(creature.age), int(creature.hunger), int(creature.hydration)]
	if creature.asleep:
		_label.modulate = Color("8fb8ff")
	elif creature.is_thirsty():
		_label.modulate = Color("5ad2e6")
	elif creature.is_hungry():
		_label.modulate = Color("ff8a5b")
	else:
		_label.modulate = Color.WHITE
	_sprite.modulate = Color(0.55, 0.6, 0.8) if creature.asleep else Color.WHITE
	# Counter the camera so the text stays screen-sized, then sit it above the
	# sprite, centred.
	var inverse := 1.0 / view_zoom
	_label.scale = Vector2.ONE * inverse
	_label.size = _label.get_combined_minimum_size()
	_label.position = Vector2(
		-_label.size.x * inverse / 2.0,
		-Dungeon.TILE_SIZE * 0.55 - _label.size.y * inverse)
