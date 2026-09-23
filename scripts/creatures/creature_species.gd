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

@export_group("Food")
## How far away, in steps, it notices food. It knows nothing beyond this, so it
## never walks straight to a pile on the far side of the dungeon.
@export var food_detection_radius: int = 5
## Once hunger falls to this it stops seeking and goes back to wandering.
@export var sated_threshold: float = 30.0
## Simulation seconds spent on each mouthful.
@export var eat_duration: float = 1.0

@export_group("Water")
## Hydration lost per simulation second. What leaves the body this way is what
## fills the bladder, so a creature that never drinks cannot urinate.
@export var hydration_rate: float = 0.1
## At or below this it goes looking for water.
@export var thirsty_threshold: float = 40.0
## Once hydration reaches this it stops drinking.
@export var sated_hydration: float = 90.0
## How far away, in steps, it notices water.
@export var water_detection_radius: int = 3
## Simulation seconds spent on each sip.
@export var drink_duration: float = 1.0

@export_group("Movement")
## Simulation seconds to rest before setting off on the next trip.
@export var idle_time_min: float = 1.0
@export var idle_time_max: float = 3.0
## Simulation seconds to cross one tile. Larger is a slower walk.
@export var move_duration: float = 1.0
## Tiles walked in one trip before resting. Creatures cross several tiles at a
## time rather than stopping after every one, so they actually travel.
@export var trip_steps_min: int = 3
@export var trip_steps_max: int = 8

@export_group("Sleep")
## Hour it falls asleep and the hour it wakes, on the 24 hour clock. A window
## that wraps past midnight (22 to 6) is normal. Swap the two numbers for a
## creature that sleeps through the day instead.
@export_range(0, 23) var sleep_start_hour: int = 22
@export_range(0, 23) var wake_hour: int = 6

@export_group("Urination")
## Bladder content at which the creature must go. It fills only with hydration
## the body has actually used, so this is a water budget, not a clock.
@export var bladder_capacity: float = 4.0
## How much urine one go leaves on the tile.
@export var urination_amount: float = 1.0

@export_group("Visuals")
## Profile sprite. [member side_faces_left] says which way it looks unflipped.
@export var side_texture: Texture2D
## Sprite used when moving south, towards the camera.
@export var front_texture: Texture2D
@export var side_faces_left: bool = true
## Drawn height, in tiles. One scale is used for every sprite so the creature
## does not change size when it turns.
@export var display_height_tiles: float = 0.9


## True if [param hour] falls inside this species' sleeping hours. Equal start
## and wake hours mean it never sleeps.
func is_sleep_hour(hour: int) -> bool:
	if sleep_start_hour == wake_hour:
		return false
	if sleep_start_hour < wake_hour:
		return hour >= sleep_start_hour and hour < wake_hour
	# The window wraps past midnight.
	return hour >= sleep_start_hour or hour < wake_hour
