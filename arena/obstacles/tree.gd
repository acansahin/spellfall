class_name TreeObstacle
extends StaticBody3D

## A tall shard of glacier ice: the piece of cover you cannot shoot over.
##
## It was a tree - a leaning trunk and five leaf masses - and before that a lollipop. It is ice
## now because the arena is, and it shares `IceGeometry` with the low chunk beside it: the two
## differ by a height and a radius, which is two arguments rather than two builders.
##
## The NAME did not follow the art, for the reason written on `rock.gd`: `tree.tscn` is
## instanced by `arena.tscn` and named in ARCHITECTURE.md and TASKS.md, and the export names
## below are what the scene file already stores. Renaming both would churn every one of those
## to describe a colour. What the file IS lives in this doc.
##
## The collision shape is untouched and stays in the scene: what this BLOCKS is a gameplay
## number that four suites measure, and it must not drift because the art changed.

## Height of the shard in metres. Named for the trunk it used to be, and kept because the scene
## file stores it under that name - see the doc above.
@export var trunk_height := 2.6

## Rough radius of the cluster. Same story as `trunk_height`.
@export var canopy_size := 1.15

## Different every instance, and STABLE for each one: seeded from where the shard stands.
@export var seed_offset := 0

const IceGeometry = preload("res://arena/obstacles/ice_geometry.gd")


func _ready() -> void:
	# Taller than it is wide, and past `IceGeometry.TALL_ENOUGH`, so it gets a fourth shard.
	IceGeometry.build(self, trunk_height * 0.88, canopy_size * 0.70,
		hash(Vector2(position.x, position.z)) + seed_offset + 7717)
