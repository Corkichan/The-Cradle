class_name FoodSource
extends RefCounted

## A consumable resource sitting on a dungeon tile: a pile of food, or water.
##
## The class is still called FoodSource because it was built for food and the
## name is used in a hundred places; it is now the generic consumable. Renaming
## it to ResourceSource is a mechanical follow-up.
##
## An environmental resource, not something a creature owns: creatures reference
## one and take from it. Anything that eats — rodents now, goblins, slimes or
## adventurers later — uses the same object, so nothing about eating lives here.
##
## Pure data: not a Node, never processes, never draws itself.

## What a source is made of. The only thing that differs is which need one
## serving restores, so there is one class rather than one per resource.
enum Kind {
	FOOD,  ## Restores hunger.
	WATER, ## Restores hydration.
}

const DEFAULT_AMOUNT: float = 100.0
const DEFAULT_NUTRITION: float = 25.0

var id: int
var kind: Kind = Kind.FOOD
## The floor this food sits on. Held directly rather than through [Dungeon], for
## the same reason creatures do: Dungeon answers for whichever floor is viewed.
var dungeon_floor: DungeonFloor
var grid_position: Vector2i
## How much food is left. Never negative.
var amount: float
## How much one serving is worth: taken from [member amount], and restored to
## whichever need this kind of resource serves.
var nutrition: float


func _init(p_id: int, p_floor: DungeonFloor, p_position: Vector2i,
		p_amount: float = DEFAULT_AMOUNT, p_nutrition: float = DEFAULT_NUTRITION,
		p_kind: Kind = Kind.FOOD) -> void:
	id = p_id
	kind = p_kind
	dungeon_floor = p_floor
	grid_position = p_position
	amount = maxf(p_amount, 0.0)
	nutrition = maxf(p_nutrition, 0.0)


func is_water() -> bool:
	return kind == Kind.WATER


func is_depleted() -> bool:
	return amount <= 0.0


## Takes one mouthful and returns what was actually taken — never more than is
## left, so the last bite of a nearly empty pile is smaller than the rest.
func take_bite() -> float:
	var taken := minf(nutrition, amount)
	amount = maxf(amount - taken, 0.0)
	return taken


func _to_string() -> String:
	return "%s#%d(%s, %.0f/%.0f)" % [
		Kind.keys()[kind], id, grid_position, amount, nutrition]
