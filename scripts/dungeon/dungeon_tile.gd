class_name DungeonTile
extends RefCounted

## A single cell of a dungeon floor. Pure data: a tile never draws itself.
##
## Deliberately minimal. Future systems (soil moisture, mushroom growth,
## creature occupancy) add fields here rather than subclassing per terrain —
## one tile type with data on it, not a class hierarchy.

## What has been built on a tile.
##
## Every tile starts EMPTY: it belongs to the dungeon but nothing can walk on it
## until the player places floor. Walls, water, soil and rock are future systems.
enum Terrain {
	EMPTY, ## Part of the dungeon, nothing built yet. Not walkable.
	FLOOR, ## Floor placed by the player. Walkable.
}

## Where this tile sits on its floor's grid.
var grid_position: Vector2i
## What is built here.
var terrain: Terrain
## Whether creatures may enter. Starts as whatever [member terrain] implies, but
## is stored separately so a future system can block a floor tile (occupancy, a
## placed object) without inventing a new terrain.
var walkable: bool


func _init(p_grid_position: Vector2i, p_terrain: Terrain = Terrain.EMPTY) -> void:
	grid_position = p_grid_position
	terrain = p_terrain
	walkable = p_terrain == Terrain.FLOOR


func _to_string() -> String:
	return "DungeonTile(%s, %s, walkable=%s)" % [
		grid_position, Terrain.keys()[terrain], walkable]
