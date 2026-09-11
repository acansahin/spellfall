class_name TreeObstacle
extends StaticBody3D

## Tall glacier shard; legacy scene/export names keep existing references compatible.
@export var trunk_height := 2.6
@export var canopy_size := 1.15
@export var seed_offset := 0

const IceGeometry = preload("res://arena/obstacles/ice_geometry.gd")

func _ready() -> void:
	IceGeometry.build(self, trunk_height * 0.88, canopy_size * 0.70,
		hash(Vector2(position.x, position.z)) + seed_offset + 7717)
