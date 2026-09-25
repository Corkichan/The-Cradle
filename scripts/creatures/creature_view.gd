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
## Vertical squash the world is being drawn with. A creature is a STANDING
## thing, so it is scaled back up by this: the floor tips away, the rat does
## not. See [CameraRig].
var view_tilt: float = 1.0
## 0 draws the creature centred on its tile, 1 stands it on the tile.
var ground_anchor: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label: Label = $Label

var _last_horizontal: int = -1
## Unsquashed size the sprite is drawn at, before the tilt is countered.
var _base_scale: float = 1.0
## How far the sprite was raised to stand it on its tile, in local pixels.
## The label is pushed up by the same amount so it never sits over the art.
var _lift: float = 0.0


func bind(p_creature: Creature) -> void:
	creature = p_creature
	name = "Creature%d" % creature.id
	var species := creature.species
	var drawn_height := species.display_height_tiles * Dungeon.TILE_SIZE
	if species.has_idle_sheets():
		# Every strip is a single row, so a sheet's height IS its frame height.
		_base_scale = drawn_height / species.idle_front_sheet.get_height()
		# Pixel art the camera magnifies. Smoothing it would blur the pixels
		# into the mush this art was drawn to avoid.
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_last_horizontal = -1
	else:
		_base_scale = drawn_height / species.front_texture.get_height()
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


## Picks the drawing for the way the creature is facing. Species with idle
## strips get one per direction; the rest fall back to a flipped profile.
func _update_sprite() -> void:
	var species := creature.species
	if creature.facing.x != 0:
		_last_horizontal = creature.facing.x
	if species.has_idle_sheets():
		_show_idle_frame(species)
	else:
		_show_single_texture(species)
	_stand_upright()


## One strip per direction, so nothing is flipped — art drawn for a direction is
## shown as drawn — and north gets a real back view rather than the profile.
func _show_idle_frame(species: CreatureSpecies) -> void:
	_sprite.flip_h = false
	_sprite.hframes = species.idle_frames
	if creature.facing == Vector2i.DOWN:
		_sprite.texture = species.idle_front_sheet
	elif creature.facing == Vector2i.UP:
		_sprite.texture = species.idle_back_sheet
	elif _last_horizontal < 0:
		_sprite.texture = species.idle_left_sheet
	else:
		_sprite.texture = species.idle_right_sheet
	_sprite.frame = _idle_frame(species)


## Which frame of the loop to show.
##
## Driven by the creature's own AGE rather than by real time, so the animation
## stops dead when the simulation is paused and quickens when it runs at 10x,
## without the view ever reading a clock. The id offsets each creature so a
## litter spawned in the same tick does not breathe in perfect unison.
func _idle_frame(species: CreatureSpecies) -> int:
	return posmod(int(creature.age * species.idle_fps) + creature.id,
		species.idle_frames)


## Fallback for species drawn once per view instead of as a strip. The profile
## is flipped by whichever way it natively faces, and north borrows it because
## there is no back drawing to show.
func _show_single_texture(species: CreatureSpecies) -> void:
	_sprite.hframes = 1
	if creature.facing == Vector2i.DOWN:
		_sprite.texture = species.front_texture
		_sprite.flip_h = false
	else:
		_sprite.texture = species.side_texture
		var art_direction := -1 if species.side_faces_left else 1
		_sprite.flip_h = _last_horizontal != art_direction


## Undoes the world's vertical squash on the sprite and, as the view tips
## forward, moves it from being centred on its tile to standing on it.
##
## Standing on the tile is what makes depth sorting mean anything: the node's
## position is its ground contact point, so sorting by that position sorts by
## which creature is nearer the front.
func _stand_upright() -> void:
	var height := _sprite.texture.get_height()
	var upright := _base_scale / maxf(view_tilt, 0.001)
	_sprite.scale = Vector2(_base_scale, upright)
	_sprite.offset.y = -height * 0.5 * ground_anchor
	_lift = height * upright * 0.5 * ground_anchor


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
	# Counter the camera so the text stays screen-sized, and the world's squash
	# so it is not compressed along with the floor, then sit it above the
	# sprite, centred and clear of however far the sprite was raised.
	var inverse := 1.0 / view_zoom
	_label.scale = Vector2(inverse, inverse / maxf(view_tilt, 0.001))
	_label.size = _label.get_combined_minimum_size()
	_label.position = Vector2(
		-_label.size.x * inverse / 2.0,
		-Dungeon.TILE_SIZE * 0.55 - _lift - _label.size.y * _label.scale.y)
