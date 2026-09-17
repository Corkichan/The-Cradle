class_name CreatureSpecies
extends Resource

## Everything that makes one kind of creature different from another, as data.
##
## A new creature is a new .tres file, not a new class. Nothing in the creature
## code branches on which species it is.

@export var species_name: String = ""
@export var variant_name: String = ""

@export_group("Vitals")
@export var max_health: float = 10.0
## Hunger gained per simulation second.
@export var hunger_rate: float = 0.5
## At or above this, the creature is HUNGRY.
@export var hungry_threshold: float = 70.0
## Spawned creatures start with a random hunger in [0, this], so a group does
## not all become hungry on the same tick.
@export var initial_hunger_max: float = 30.0

@export_group("Movement")
## Simulation seconds to rest on a tile before choosing the next one.
@export var idle_time_min: float = 1.0
@export var idle_time_max: float = 3.0
## Simulation seconds to cross one tile.
@export var move_duration: float = 0.45

@export_group("Visuals")
## Profile sprite. [member side_faces_left] says which way it looks unflipped.
@export var side_texture: Texture2D
## Sprite used when moving south, towards the camera.
@export var front_texture: Texture2D
@export var side_faces_left: bool = true
## Drawn height, in tiles. One scale is used for every sprite so the creature
## does not change size when it turns.
@export var display_height_tiles: float = 0.9
