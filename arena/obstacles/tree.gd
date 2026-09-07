class_name TreeObstacle
extends StaticBody3D

## A tree, built out of a leaning trunk and a cluster of leaf masses.
##
## It was a cylinder with one sphere on top, which is a lollipop, and the same argument applies
## as to the rock beside it: a texture cannot change a silhouette. What makes a tree read as a
## tree from above - and above is where this camera is - is an IRREGULAR OUTLINE. One sphere
## has the most regular outline there is.
##
## Five overlapping canopy masses at different heights and sizes, and a trunk in two segments
## with a bend in it. The trunk barely shows from this angle; the bend is there because its
## shadow does.
##
## The collision shape is untouched and stays in the scene: what a tree BLOCKS is a gameplay
## number that four suites measure, and it must not drift because the art changed.

## Height of the trunk in metres, from the ground to where the canopy sits.
@export var trunk_height := 2.6

## Rough radius of the whole leaf mass.
@export var canopy_size := 1.15

## Different every instance, and STABLE for each one: seeded from where the tree stands.
@export var seed_offset := 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(Vector2(position.x, position.z)) + seed_offset + 7717
	_build()


func _build() -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load("res://assets/materials/bark.png")
	bark.roughness = 1.0
	bark.uv1_scale = Vector3(0.85, 0.85, 0.85)
	bark.uv1_triplanar = true

	var leaf := StandardMaterial3D.new()
	leaf.albedo_texture = load("res://assets/materials/canopy.png")
	leaf.roughness = 0.9
	leaf.uv1_scale = Vector3(0.75, 0.75, 0.75)
	leaf.uv1_triplanar = true

	# --- the trunk, in two segments with a bend ---------------------------------------------
	var lean := _rng.randf_range(0.04, 0.11)
	var facing := _rng.randf_range(0.0, TAU)
	var lower := _segment(self, trunk_height * 0.55, 0.30, 0.25, bark)
	lower.position = Vector3(0.0, trunk_height * 0.275, 0.0)
	lower.rotation = Vector3(cos(facing) * lean, 0.0, sin(facing) * lean)

	var upper_at := Vector3(
		sin(facing) * lean * trunk_height * 0.5, trunk_height * 0.55,
		cos(facing) * lean * trunk_height * 0.5)
	var upper := _segment(self, trunk_height * 0.5, 0.24, 0.19, bark)
	upper.position = upper_at + Vector3(0.0, trunk_height * 0.25, 0.0)
	# Bent back the other way, so the trunk is an S rather than a stick at an angle.
	upper.rotation = Vector3(-cos(facing) * lean * 0.7, 0.0, -sin(facing) * lean * 0.7)

	# A flare where the trunk meets the ground. Two segments of a cone, and it is the whole of
	# why the tree looks planted rather than dropped.
	var root := _segment(self, 0.34, 0.30, 0.46, bark)
	root.position = Vector3(0.0, 0.16, 0.0)

	# --- the canopy: several masses, not one -------------------------------------------------
	var top := trunk_height * 1.02
	_leaf_mass(Vector3(0.0, top + canopy_size * 0.42, 0.0), canopy_size, leaf)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + _rng.randf_range(-0.5, 0.5)
		var reach := canopy_size * _rng.randf_range(0.52, 0.78)
		var lift := canopy_size * _rng.randf_range(-0.10, 0.46)
		_leaf_mass(
			Vector3(cos(angle) * reach, top + canopy_size * 0.36 + lift, sin(angle) * reach),
			canopy_size * _rng.randf_range(0.50, 0.72), leaf)


func _segment(parent: Node3D, height: float, top: float, bottom: float,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 7
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.set_surface_override_material(0, mat)
	parent.add_child(node)
	return node


## One rounded mass of leaves, squashed and turned so no two are the same shape.
func _leaf_mass(at: Vector3, radius: float, mat: StandardMaterial3D) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	# Seven and four: enough to be round, few enough that the edge of the mass is faceted and
	# therefore reads against the mass beside it instead of blending into one smooth blob.
	mesh.radial_segments = 7
	mesh.rings = 4
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.set_surface_override_material(0, mat)
	node.position = at
	node.scale = Vector3(1.0, _rng.randf_range(0.72, 0.94), 1.0)
	node.rotation.y = _rng.randf_range(0.0, TAU)
	add_child(node)
