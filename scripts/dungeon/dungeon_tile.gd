class_name DungeonTile
extends RefCounted

## A single cell of a dungeon floor. Pure data: a tile never draws itself.
##
## Deliberately minimal. Future systems (soil moisture, mushroom growth,
## creature occupancy) add fields here rather than subclassing per terrain —
## one tile type with data on it, not a class hierarchy.

## Terrain kinds. Only FLOOR exists at this stage; walls, water, soil and rock
## are future systems.
enum Terrain {
	FLOOR,
}

## Where this tile sits on its floor's grid.
var grid_position: Vector2i
## What this tile is made of.
var terrain: Terrain
## Whether creatures may enter. Stored rather than derived from [member terrain]
## so future systems can block a floor tile without inventing a new terrain.
var walkable: bool


func _init(p_grid_position: Vector2i, p_terrain: Terrain = Terrain.FLOOR,
		p_walkable: bool = true) -> void:
	grid_position = p_grid_position
	terrain = p_terrain
	walkable = p_walkable


func _to_string() -> String:
	return "DungeonTile(%s, %s, walkable=%s)" % [
		grid_position, Terrain.keys()[terrain], walkable]
