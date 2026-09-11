class_name RockObstacle
extends StaticBody3D

## Low glacier chunk; collision dimensions are defined by the scene.
@export var size := 0.86
@export var seed_offset := 0

const IceGeometry = preload("res://arena/obstacles/ice_geometry.gd")

func _ready() -> void:
	IceGeometry.build(self, size * 2.1, size * 0.9,
		hash(Vector2(position.x, position.z)) + seed_offset)
