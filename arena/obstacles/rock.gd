class_name RockObstacle
extends StaticBody3D

## A low chunk of glacier ice: the short piece of cover, the one a spell clears.
##
## It was a boulder built of three angular lumps, and before that a textured barrel. It is ice
## now because the arena is, and the build moved to `IceGeometry` - a rock and a tree stopped
## being different things when both became broken ice, and what separates them is a height and
## a radius rather than two builders. The scene keeps this script so the two heights stay two
## editable scenes rather than one scene with a flag.
##
## The NAME did not follow the art, and that is deliberate. `rock.tscn` is instanced by
## `arena.tscn`, named in ARCHITECTURE.md, and recorded in TASKS.md as what four suites
## measure; renaming the file to match a shade of blue would break those references and rewrite
## a history that was accurate when it was written. What the file IS lives in this doc.
##
## The collision shape is untouched and stays in the scene: what a rock BLOCKS is a gameplay
## number that four suites measure, and it must not drift because the art changed.

## Rough radius of the cluster, in metres. The collision cylinder is 0.7, so the art is a
## little wider than what it stops - which is what you want, or a wizard slides along an
## invisible wall a hand's width outside the ice.
@export var size := 0.86

## Different every instance, and STABLE for each one: seeded from where the chunk stands, so
## two of them are two of them and neither changes shape between runs. A screenshot taken twice
## has to be the same screenshot, or nothing can be compared to anything.
@export var seed_offset := 0

const IceGeometry = preload("res://arena/obstacles/ice_geometry.gd")


func _ready() -> void:
	# Wider than it is tall, which is what keeps it reading as something you shoot OVER.
	IceGeometry.build(self, size * 2.1, size * 0.9,
		hash(Vector2(position.x, position.z)) + seed_offset)
